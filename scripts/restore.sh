#!/usr/bin/env bash
# Restore a backup made by scripts/backup.sh (plan P16.5, docs/runbooks/backups.md) into
# an EMPTY database and an empty media folder, then check that it brought back what the
# backup recorded: the cinemas, movies, showtimes, orders, tickets and media files.
#
#   scripts/restore.sh /path/to/africinemas-20261030T020000Z.tar.gpg
#
#   JAC_DB_URL             the database to restore into: it must be empty (required)
#   AFRICINEMAS_MEDIA_DIR  the media folder to restore into: empty or missing (required)
#   PG_BIN                 the folder of pg_restore and psql, if not on PATH
#
# Decrypting needs the backup key's private half in this user's gpg keyring; it is never
# kept on the app server. It never writes over data: a database with tables, or a media
# folder with files, is refused.
set -euo pipefail
umask 077

backup="${1:?usage: scripts/restore.sh <backup .tar.gpg>}"
: "${JAC_DB_URL:?set JAC_DB_URL to the empty database to restore into}"
: "${AFRICINEMAS_MEDIA_DIR:?set AFRICINEMAS_MEDIA_DIR to the empty media folder to restore into}"
media="$AFRICINEMAS_MEDIA_DIR"
pg="${PG_BIN:+$PG_BIN/}"

sql() { "${pg}psql" -X -A -t -v ON_ERROR_STOP=1 -d "$JAC_DB_URL" -c "$1"; }
count() { sql "SELECT count(*) FROM anchors WHERE arch_type LIKE '%.$1'"; }
# A value from the backup's manifest by its dotted path, e.g. counts.cinemas.
field() {
    python3 -c 'import json, sys
d = json.load(open(sys.argv[1]))
for k in sys.argv[2].split("."):
    d = d[k]
print(d)' "$manifest" "$1"
}

tables="$(sql "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public'")"
if [[ "$tables" != "0" ]]; then
    echo "refused: the database already has $tables table(s); restore into an empty one" >&2
    exit 1
fi
if [[ -d "$media" && -n "$(ls -A "$media")" ]]; then
    echo "refused: $media isn't empty; restore into an empty media folder" >&2
    exit 1
fi

if [[ -f "$backup.sha256" ]]; then
    (cd "$(dirname "$backup")" && sha256sum --quiet -c "$(basename "$backup").sha256")
    echo "The backup file's checksum matches."
else
    echo "warning: no $backup.sha256 beside it; the file's checksum isn't checked" >&2
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
echo "Decrypting..."
gpg --batch --quiet --decrypt "$backup" | tar -C "$work" -xf -
inner="$(find "$work" -mindepth 1 -maxdepth 1 -type d | head -1)"
manifest="$inner/manifest.json"
[[ -f "$manifest" ]] || { echo "not a backup made by scripts/backup.sh: no manifest" >&2; exit 1; }
for part in db media; do
    file="$inner/$part.$([[ $part == db ]] && echo dump || echo tar)"
    if [[ "$(sha256sum "$file" | cut -d' ' -f1)" != "$(field "${part}_sha256")" ]]; then
        echo "refused: $(basename "$file") doesn't match the backup's manifest" >&2
        exit 1
    fi
done
echo "Made $(field created_at); its parts match their checksums."

echo "Restoring the database..."
"${pg}pg_restore" --no-owner --no-privileges --exit-on-error \
    -d "$JAC_DB_URL" "$inner/db.dump"
echo "Restoring the media folder..."
mkdir -p "$media"
tar -C "$media" -xf "$inner/media.tar"

# Brought back what the backup recorded?
failed=0
check() {
    local what="$1" want="$2" got="$3"
    if [[ "$want" == "$got" ]]; then
        printf '  %-10s %s\n' "$what" "$got"
    else
        printf '  %-10s %s, but the backup had %s\n' "$what" "$got" "$want" >&2
        failed=1
    fi
}
echo "Checking what came back:"
check anchors "$(field counts.anchors)" "$(sql "SELECT count(*) FROM anchors")"
for pair in cinemas:Tenant movies:Movie showtimes:Screening orders:Order tickets:Ticket; do
    check "${pair%%:*}" "$(field "counts.${pair%%:*}")" "$(count "${pair##*:}")"
done
check "media" "$(field media_files)" "$(find "$media" -type f | wc -l | tr -d ' ')"
if (( failed )); then
    echo "The restore does NOT match the backup (see above)." >&2
    exit 1
fi
echo "Restored, and it matches the backup."
