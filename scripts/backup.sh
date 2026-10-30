#!/usr/bin/env bash
# The nightly backup (plan P16.5, docs/runbooks/backups.md): the database and the media
# folder, in one file encrypted to the team's backup key, copied off the server, and kept
# AFRICINEMAS_BACKUP_KEEP_DAYS days (35, owner 2026-10-30). Run from cron as the app's user.
#
#   JAC_DB_URL                        the app's Postgres database (required)
#   AFRICINEMAS_BACKUP_GPG_RECIPIENT  the backup key's id or email; only its public half is
#                                     on the server (required)
#   AFRICINEMAS_MEDIA_DIR             the media folder (default ./storage, as the app)
#   AFRICINEMAS_BACKUP_DIR            where backups are written (default /var/backups/africinemas)
#   AFRICINEMAS_BACKUP_REMOTE         an rclone destination, e.g. "b2:africinemas-backups";
#                                     empty: kept on this server only, and not checked in
#   AFRICINEMAS_BACKUP_KEEP_DAYS      days to keep, here and off the server (default 35)
#   PG_BIN                            the folder of pg_dump and psql, if not on PATH
#
# A backup copied off the server checks in as the job "nightly_backup" (P16.2), so a
# night without one alerts the team. Nothing here prints a customer's details.
set -euo pipefail
umask 077

: "${JAC_DB_URL:?set JAC_DB_URL to the app database}"
: "${AFRICINEMAS_BACKUP_GPG_RECIPIENT:?set AFRICINEMAS_BACKUP_GPG_RECIPIENT to the backup key}"
media="${AFRICINEMAS_MEDIA_DIR:-./storage}"
dest="${AFRICINEMAS_BACKUP_DIR:-/var/backups/africinemas}"
remote="${AFRICINEMAS_BACKUP_REMOTE:-}"
keep="${AFRICINEMAS_BACKUP_KEEP_DAYS:-35}"
pg="${PG_BIN:+$PG_BIN/}"

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
name="africinemas-$stamp"
mkdir -p "$dest"
work="$(mktemp -d "$dest/.work-XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir "$work/$name"

sql() { "${pg}psql" -X -A -t -v ON_ERROR_STOP=1 -d "$JAC_DB_URL" -c "$1"; }
count() { sql "SELECT count(*) FROM anchors WHERE arch_type LIKE '%.$1'"; }

echo "Dumping the database..."
"${pg}pg_dump" --format=custom --no-owner --no-privileges \
    --file "$work/$name/db.dump" "$JAC_DB_URL"

echo "Packing the media folder..."
if [[ -d "$media" ]]; then
    # Leftovers of scripts/remove_e2e_data.sh are test cinemas' files, not ours to keep.
    tar -C "$media" --exclude='./.e2e-removed-*' -cf "$work/$name/media.tar" .
else
    echo "warning: no media folder at $media; the backup has no media" >&2
    tar -cf "$work/$name/media.tar" -T /dev/null
fi

# What the restore checks it brought back (scripts/restore.sh).
cat > "$work/$name/manifest.json" <<EOF
{
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "db_sha256": "$(sha256sum "$work/$name/db.dump" | cut -d' ' -f1)",
  "media_sha256": "$(sha256sum "$work/$name/media.tar" | cut -d' ' -f1)",
  "media_files": $(tar -tf "$work/$name/media.tar" | grep -vc '/$' || true),
  "counts": {
    "anchors": $(sql "SELECT count(*) FROM anchors"),
    "cinemas": $(count Tenant),
    "movies": $(count Movie),
    "showtimes": $(count Screening),
    "orders": $(count Order),
    "tickets": $(count Ticket)
  }
}
EOF

echo "Encrypting..."
tar -C "$work" -cf - "$name" \
    | gpg --batch --yes --trust-model always \
        --recipient "$AFRICINEMAS_BACKUP_GPG_RECIPIENT" \
        --encrypt --output "$dest/$name.tar.gpg"
(cd "$dest" && sha256sum "$name.tar.gpg" > "$name.tar.gpg.sha256")
echo "Written $dest/$name.tar.gpg ($(du -h "$dest/$name.tar.gpg" | cut -f1))."

# Older than the keeping time, here...
find "$dest" -maxdepth 1 -name 'africinemas-*.tar.gpg*' -mtime +"$keep" -delete

if [[ -z "$remote" ]]; then
    echo "warning: AFRICINEMAS_BACKUP_REMOTE is empty: not copied off the server, and not checked in" >&2
    exit 0
fi

echo "Copying off the server to $remote..."
rclone copy "$dest/$name.tar.gpg" "$remote"
rclone copy "$dest/$name.tar.gpg.sha256" "$remote"
rclone check --one-way --include "$name.tar.gpg*" "$dest" "$remote"
# ...and there.
rclone delete --min-age "${keep}d" --include 'africinemas-*.tar.gpg*' "$remote"

# Checked in as a job (core/platform/jobs.jac), as every 12 hours: silent, and the team
# alerted, after 36 hours without a backup copied off the server.
sql "INSERT INTO kv_state (key, value, expires_at)
     VALUES ('africinemas:claim:job-ran:nightly_backup',
             '{\"at\": \"$(date -u +%Y-%m-%dT%H:%M:%S+00:00)\", \"every\": 43200}', NULL)
     ON CONFLICT (key) DO UPDATE
         SET value = EXCLUDED.value, expires_at = NULL, updated_at = now()" > /dev/null
echo "Done: $name, copied off the server and checked in."
