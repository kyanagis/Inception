#!/bin/sh
set -eu

if [ "${1:-}" != "busybox" ]; then
  exec "$@"
fi

: "${BACKUP_SCHEDULE:?BACKUP_SCHEDULE is required}"
: "${MYSQL_DATABASE:?MYSQL_DATABASE is required}"
: "${MYSQL_USER:?MYSQL_USER is required}"
if ! printf '%s\n' "$BACKUP_SCHEDULE" | grep -Eq '^[0-9*/?, -]+$'; then
  echo "Invalid BACKUP_SCHEDULE" >&2
  exit 2
fi
case "$MYSQL_DATABASE:$MYSQL_USER" in *[!A-Za-z0-9_:]*) echo "Invalid database identifiers" >&2; exit 2;; esac

mkdir -p /tmp/crontabs
printf '%s /usr/local/bin/backup-now\n' "$BACKUP_SCHEDULE" > /tmp/crontabs/root
chmod 0600 /tmp/crontabs/root

exec "$@"
