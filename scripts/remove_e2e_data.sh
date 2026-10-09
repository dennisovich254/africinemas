#!/usr/bin/env bash
# Removes the browser tests' cinemas and accounts from the local project database (one-off,
# 2026-10-09). Before scripts/e2e_env.sh gave e2e runs a scratch database, every local run
# left its cinemas ("Nova Cinemas", slug e2e-cinema-...) and accounts (...@example.com)
# in the project's own database, beside the real ones.
#
#   scripts/remove_e2e_data.sh        report what would go (changes nothing)
#   scripts/remove_e2e_data.sh --yes  back up, then remove it
#
# Test data is told apart by owner: everything owned by a test cinema (slug e2e-...) or a
# test account (an @example.com email), their roots, their logins, and the claims whose
# key or value names one of their records. Nothing owned by any other cinema or account
# is touched. With --yes, the tables are first copied into e2e_backup_<date>_<table> in
# the same database, the removal is one SQL statement (all or nothing), and the test
# cinemas' poster folders are moved to storage/.e2e-removed-<date>/, not deleted.
# Stop the app first (Ctrl-C the server): it refuses to run while a Jac server is up.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

if pgrep -f "jac run" > /dev/null; then
    echo "A Jac server is running (jac run). Stop it first, then run this again." >&2
    exit 1
fi

SETS="
e2e_t AS (SELECT id, (props->'archetype'->>'principal_root_id')::uuid pr FROM anchors
          WHERE arch_type = 'Tenant' AND props->'archetype'->>'slug' LIKE 'e2e-%'),
real_t AS (SELECT id, (props->'archetype'->>'principal_root_id')::uuid pr FROM anchors
           WHERE arch_type = 'Tenant' AND props->'archetype'->>'slug' NOT LIKE 'e2e-%'),
e2e_u AS (SELECT DISTINCT (u.doc->>'root_id')::uuid r FROM identity_users u,
          jsonb_array_elements(u.doc->'identities') i
          WHERE i->>'type' = 'email' AND i->>'value_normalized' LIKE '%@example.com'),
real_u AS (SELECT DISTINCT (u.doc->>'root_id')::uuid r FROM identity_users u,
           jsonb_array_elements(u.doc->'identities') i
           WHERE i->>'type' = 'email' AND i->>'value_normalized' NOT LIKE '%@example.com'),
E AS (SELECT pr r FROM e2e_t UNION SELECT r FROM e2e_u EXCEPT SELECT r FROM real_u),
R AS (SELECT pr r FROM real_t UNION SELECT r FROM real_u),
TN AS (SELECT id, kind FROM anchors
       WHERE root_id IN (SELECT r FROM E) OR (arch_type = 'Root' AND id IN (SELECT r FROM E))),
TID AS (SELECT id FROM TN UNION SELECT r FROM E),
YID AS (SELECT id FROM anchors WHERE root_id IN (SELECT r FROM R) UNION SELECT r FROM R),
c AS (SELECT k.key, (SELECT array_agg(m[1]::uuid) FROM regexp_matches(
          k.key || ' ' || coalesce(k.value::text, ''),
          '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})', 'g') m) u
      FROM kv_state k WHERE k.key LIKE 'africinemas:claim:%'),
TC AS (SELECT key FROM c
       WHERE (key LIKE 'africinemas:claim:tenant-slug:e2e-%'
              OR EXISTS (SELECT 1 FROM unnest(u) x WHERE x IN (SELECT id FROM TID)))
         AND NOT EXISTS (SELECT 1 FROM unnest(u) x WHERE x IN (SELECT id FROM YID))
         AND NOT (key LIKE 'africinemas:claim:tenant-slug:%'
                  AND key NOT LIKE 'africinemas:claim:tenant-slug:e2e-%')),
TU AS (SELECT user_id FROM identity_users WHERE (doc->>'root_id')::uuid IN (SELECT r FROM E))"

sql() { jac db sql "$1" 2>&1 | tail -n "${2:-1}"; }

echo "Kept (every other cinema): $(sql "SELECT string_agg(props->'archetype'->>'name' || ' (' || (props->'archetype'->>'slug') || ')', ', ') FROM anchors WHERE arch_type = 'Tenant' AND props->'archetype'->>'slug' NOT LIKE 'e2e-%'")"
echo "Test data found:"
sql "WITH $SETS SELECT
  (SELECT count(*) FROM e2e_t) || ' test cinemas, ' ||
  (SELECT count(*) FROM e2e_u) || ' test people''s accounts, ' ||
  (SELECT count(*) FROM TU) || ' logins in all (with the test cinemas'' own), ' ||
  (SELECT count(*) FROM TN WHERE kind = 'NodeAnchor') || ' records, ' ||
  (SELECT count(*) FROM TN WHERE kind = 'EdgeAnchor') || ' links, ' ||
  (SELECT count(*) FROM TC) || ' claims'"

if [[ "${1:-}" != "--yes" ]]; then
    echo "Nothing changed. Run with --yes to back up and remove it."
    exit 0
fi

stamp=$(date +%Y%m%d_%H%M%S)
echo "Backing up the tables into e2e_backup_${stamp}_<table>..."
for table in anchors kv_state identity_users identity_lookups sso_lookups; do
    sql "CREATE TABLE e2e_backup_${stamp}_${table} AS SELECT * FROM ${table}" > /dev/null
done
ids=$(sql "WITH $SETS SELECT string_agg(id::text, ' ') FROM e2e_t")

echo "Removing..."
sql "WITH $SETS,
d_a AS (DELETE FROM anchors WHERE id IN (SELECT id FROM TN) RETURNING kind),
d_k AS (DELETE FROM kv_state WHERE key IN (SELECT key FROM TC) RETURNING 1),
d_l AS (DELETE FROM identity_lookups WHERE user_id IN (SELECT user_id FROM TU) RETURNING 1),
d_s AS (DELETE FROM sso_lookups WHERE user_id IN (SELECT user_id FROM TU) RETURNING 1),
d_u AS (DELETE FROM identity_users WHERE user_id IN (SELECT user_id FROM TU) RETURNING 1)
SELECT 'removed ' || (SELECT count(*) FROM d_a WHERE kind = 'NodeAnchor') || ' records, '
  || (SELECT count(*) FROM d_a WHERE kind = 'EdgeAnchor') || ' links, '
  || (SELECT count(*) FROM d_k) || ' claims, '
  || (SELECT count(*) FROM d_u) || ' logins'"

moved=0
aside="storage/.e2e-removed-${stamp}"
for id in $ids; do
    if [[ -d "storage/tenant/$id" ]]; then
        mkdir -p "$aside"
        mv "storage/tenant/$id" "$aside/"
        moved=$((moved + 1))
    fi
done
echo "Moved $moved test poster folders to $aside/ (delete it once you're happy)."
echo "Left now: $(sql "SELECT count(*) || ' cinemas' FROM anchors WHERE arch_type = 'Tenant'")"
echo "Backups: e2e_backup_${stamp}_* tables (drop them with jac db sql once you're happy)."
