#!/bin/sh
set -eu
umask 077

if [ "${1:-}" != "busybox" ]; then
  exec "$@"
fi

: "${BACKUP_SCHEDULE:?BACKUP_SCHEDULE is required}"
: "${MYSQL_DATABASE:?MYSQL_DATABASE is required}"
: "${MYSQL_USER:?MYSQL_USER is required}"
: "${MYSQL_BACKUP_USER:?MYSQL_BACKUP_USER is required}"
case "$MYSQL_DATABASE:$MYSQL_USER:$MYSQL_BACKUP_USER" in *[!A-Za-z0-9_:]*) echo "Invalid database identifiers" >&2; exit 2;; esac
/usr/local/bin/backup-schedule "$BACKUP_SCHEDULE"
install -d -m 0700 /run/crontabs
printf '%s /usr/local/bin/backup-now\n' "$BACKUP_SCHEDULE" > /run/crontabs/root
chmod 0600 /run/crontabs/root
export TZ=UTC
exec "$@"
