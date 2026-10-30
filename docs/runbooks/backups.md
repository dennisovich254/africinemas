# Runbook: backups, and restoring one (plan P16.5)

Every night AfriCinemas backs up **everything a cinema would lose**: the database (cinemas, staff, movies, showtimes, seats, orders, tickets, payments, snacks, invoices) and the **media folder** (posters, backdrops, home page photos, logos, verification documents, support screenshots).

- **One file a night,** encrypted to the team's **backup key**. Only the key's public half is on the server, so someone who steals the server or the storage can't read a backup.
- **Copied off the server** every night.
- **Kept 35 days** (owner, 2026-10-30), here and off the server. The privacy policy says so: data deleted from AfriCinemas is gone from every backup within 35 days.
- **Checked in** as the job "The nightly backup". If no backup has been copied off the server for 36 hours, the console's overview shows it as stopped, and the team is emailed (P16.2).

The scripts are `scripts/backup.sh` and `scripts/restore.sh`. Each says what it does at the top.

## What a backup does NOT contain: the secrets

These are kept in the deployment's secret store, and a **second copy offline** (a password manager the founders share, or printed in a safe), **never in a backup**:

| Secret | Without it, after a restore |
|---|---|
| The backup key's **private half** and its passphrase | No backup can be opened at all |
| `AFRICINEMAS_FILES_KEY` | Verification documents can't be read |
| `AFRICINEMAS_MPESA_KEY` | Every cinema has to connect its M-Pesa again |
| `AFRICINEMAS_TICKET_KEY` | Tickets already sold no longer scan at the door |
| `JAC_SERVE_AUTH_SECRET` | Everyone is signed out (they sign in again; nothing is lost) |

Check the offline copy whenever a secret changes.

## Setting it up on a server (once)

1. **Tools.** Install the Postgres client tools, the **same major version as the database or newer** (now 18), and rclone:
   ```bash
   sudo apt install postgresql-client-18 rclone gnupg
   ```
2. **The backup key,** made once, **on a team member's computer, not the server**:
   ```bash
   gpg --quick-gen-key "AfriCinemas backups <backups@africinemas.co.ke>" default default never
   gpg --armor --export backups@africinemas.co.ke > backup-key.pub.asc
   gpg --armor --export-secret-keys backups@africinemas.co.ke > backup-key.SECRET.asc
   ```
   Put `backup-key.SECRET.asc` and its passphrase in the secret store and the offline copy, then delete the file. Copy only `backup-key.pub.asc` to the server, and import it as the app's user:
   ```bash
   gpg --import backup-key.pub.asc
   ```
3. **Off the server.** Make a bucket at the storage provider (chosen with hosting in P17.3) that **only allows adding files**, with no deletes or overwrites by the server's key, except for the 35-day clean-up (or let the bucket's own lifecycle rule delete files after 35 days, and drop the `rclone delete` line). Configure it with `rclone config` as the app's user, and check it with `rclone lsd <remote>:`.
4. **Settings,** in the environment cron runs with (beside the app's own):
   ```bash
   JAC_DB_URL=...                                  # the app's database, as the app has it
   AFRICINEMAS_MEDIA_DIR=/srv/africinemas/storage  # as the app has it
   AFRICINEMAS_BACKUP_GPG_RECIPIENT=backups@africinemas.co.ke
   AFRICINEMAS_BACKUP_DIR=/var/backups/africinemas
   AFRICINEMAS_BACKUP_REMOTE=<remote>:africinemas-backups
   ```
5. **Every night at 02:00 East Africa Time** (23:00 UTC), as the app's user, in `crontab -e`:
   ```cron
   0 23 * * * cd /srv/africinemas && . /etc/africinemas/backup.env && scripts/backup.sh >> /var/log/africinemas-backup.log 2>&1
   ```
6. **Run it once by hand** and check that it ends with `Done: ..., copied off the server and checked in.` The console's overview then lists "The nightly backup" as running.

When the media moves to object storage (P17.3, `[scale.storage]`), back up the bucket with the provider's versioning and a copy in another region instead of the media folder, and change this runbook.

## Restoring

Restore **into an empty database and an empty media folder**; the script refuses anything else, so it can't overwrite live data by mistake. It checks the file's checksum, decrypts it, checks the parts against their checksums, restores, and then checks that the cinemas, movies, showtimes, orders, tickets and media files it brought back are the numbers the backup recorded.

On a machine with the backup key's private half imported (`gpg --import backup-key.SECRET.asc`) and the tools of step 1:

1. **Get the backup,** with its `.sha256` file beside it. Last night's is the newest:
   ```bash
   rclone lsl <remote>:africinemas-backups | sort -k2,3 | tail -4
   rclone copy <remote>:africinemas-backups/africinemas-<stamp>.tar.gpg ./
   rclone copy <remote>:africinemas-backups/africinemas-<stamp>.tar.gpg.sha256 ./
   ```
2. **Make an empty database** on the Postgres server you're restoring to (`createdb africinemas_restored`), and pick an empty folder for the media.
3. **Restore:**
   ```bash
   JAC_DB_URL=postgresql://<user>@<host>/africinemas_restored \
   AFRICINEMAS_MEDIA_DIR=/srv/africinemas/storage-restored \
   scripts/restore.sh ./africinemas-<stamp>.tar.gpg
   ```
   It ends with `Restored, and it matches the backup.` If it says it does NOT match, don't use it: try the night before, and tell the team.
4. **Start the app on it,** with the **same secrets as before** (the table above), `JAC_DB_URL` pointing at the restored database and `AFRICINEMAS_MEDIA_DIR` at the restored folder. Give `JAC_DB_URL` as `postgresql://<user>@<host>:<port>/<database>`: Jac ignores a socket path or port given as `?host=...&port=...`, and tries `127.0.0.1:5432`.
5. **Check it as a person would:** sign in to the back office, open a cinema's Screenings and Orders, and open its storefront to see the posters. Scan one ticket from before the backup.

### After a disaster in production

Do the steps above onto the new database and folder, then point the app at them and restart it. Everything after the backup's time (at most one day) is lost: **payments made since then are still in M-Pesa**. Each cinema's M-Pesa statement for that day shows them; the daily M-Pesa check (reconcile) and the cinema's own records find the bookings to re-enter. Tell the cinemas (P16.7, P16.8) what time the restore goes back to.

## Rehearsing a restore (every quarter)

A backup that has never been restored is only an assumption. Every quarter, and after any change to these scripts or to the database's major version, someone **other than the last person who did it** restores last night's backup into a scratch server by the steps above (any machine with Postgres; it never touches production), starts the app on it, does step 5, and writes the date and what they found in the log below. Then they delete the scratch copy: it holds real customers' data.

| Date | Who | Backup restored | Result |
|---|---|---|---|
| 2026-10-30 | Claude (P16.5, from a development database) | The night's backup, from the off-the-server copy | Matched: 11 cinemas, 11 movies, 26 showtimes, 40 orders, 56 tickets, 237 media files; the app started on it and served a cinema; all 10 posters and 19 confirmed bookings back; a second restore into the same database refused. Not yet done by someone who didn't write the runbook. |
