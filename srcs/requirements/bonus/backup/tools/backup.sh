#!/bin/sh
set -eu
umask 077

: "${MYSQL_DATABASE:?MYSQL_DATABASE is required}"
: "${MYSQL_USER:?MYSQL_USER is required}"
: "${MYSQL_BACKUP_USER:?MYSQL_BACKUP_USER is required}"
case "$MYSQL_DATABASE:$MYSQL_USER:$MYSQL_BACKUP_USER" in *[!A-Za-z0-9_:]*) echo 'Invalid database identifiers' >&2; exit 2;; esac
retention=${BACKUP_RETENTION_DAYS:-7}
case "$retention" in ''|*[!0-9]*) echo 'Invalid backup retention' >&2; exit 2;; esac
[ "$retention" -ge 1 ] && [ "$retention" -le 3650 ] || { echo 'Invalid backup retention' >&2; exit 2; }
[ ! -L /backups ] && [ -d /backups ] || { echo 'Invalid backup directory' >&2; exit 1; }
[ ! -L /backups/.backup.lock ] || { echo 'Invalid backup lock' >&2; exit 1; }
exec 9>>/backups/.backup.lock
if ! flock -n 9; then
  printf '%s SKIPPED backup already running\n' "$(date -u +%FT%TZ)" >&2
  exit 75
fi

work_dir=
client_file=
cleanup() {
  result=$?
  set +e
  trap - EXIT
  [ -z "$client_file" ] || rm -f -- "$client_file"
  [ -z "$work_dir" ] || rm -rf -- "$work_dir"
  if [ "$result" -ne 0 ]; then
    printf '%s FAILED backup exit=%s\n' "$(date -u +%FT%TZ)" "$result" >&2
  fi
  exit "$result"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
printf '%s STARTED backup\n' "$(date -u +%FT%TZ)" >&2
/usr/local/bin/backup-manifest prune-partial /backups
/usr/local/bin/backup-manifest check-source /source

[ -f /run/secrets/db_backup_password ] && [ -r /run/secrets/db_backup_password ] || { echo 'Missing database secret' >&2; exit 1; }
client_file=$(mktemp /run/backup-client.XXXXXXXXXX)
/usr/local/bin/backup-manifest client-options "$client_file"
unsupported=$(mariadb --defaults-extra-file="$client_file" --connect-timeout=10 --batch --skip-column-names \
  --execute="SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='$MYSQL_DATABASE' AND TABLE_TYPE='BASE TABLE' AND ENGINE <> 'InnoDB'")
[ "$unsupported" = 0 ] || { echo 'Backup requires InnoDB tables' >&2; exit 1; }
server_version=$(mariadb --defaults-extra-file="$client_file" --connect-timeout=10 --batch --skip-column-names --execute='SELECT VERSION()')
client_version=$(mariadb-dump --version)

timestamp=$(date -u +%Y%m%dT%H%M%SZ)
work_dir=$(mktemp -d "/backups/.partial-${timestamp}-XXXXXXXXXX")
final_dir="/backups/${work_dir##*/.partial-}"
[ ! -e "$final_dir" ] && [ ! -L "$final_dir" ] || { echo 'Backup name already exists' >&2; exit 1; }
mariadb-dump --defaults-extra-file="$client_file" --single-transaction --quick --skip-lock-tables \
  "$MYSQL_DATABASE" > "$work_dir/database.sql"
rm -f -- "$client_file"
client_file=
gzip -- "$work_dir/database.sql"
tar --create --gzip --file="$work_dir/wordpress.tar.gz" --directory=/source/html .
/usr/local/bin/backup-manifest create "$work_dir" "$server_version" "$client_version"
/usr/local/bin/backup-manifest verify "$work_dir"
mv -T -- "$work_dir" "$final_dir"
work_dir=
if ! /usr/local/bin/backup-manifest retain /backups "$retention" "$final_dir"; then
  printf '%s WARNING backup complete; retention failed\n' "$(date -u +%FT%TZ)" >&2
fi
printf '%s COMPLETED backup %s\n' "$(date -u +%FT%TZ)" "$final_dir" >&2
