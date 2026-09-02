#!/bin/sh
set -eu

[ -r /run/secrets/db_password ] || { echo "Missing database password secret" >&2; exit 1; }
password=$(tr -d '\r\n' < /run/secrets/db_password)
[ -n "$password" ] || { echo "Empty database password secret" >&2; exit 1; }

timestamp=$(date -u +%Y%m%dT%H%M%SZ)
work_dir="/backups/.partial-${timestamp}-$$"
final_dir="/backups/${timestamp}"
mkdir -p "$work_dir"
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM

MYSQL_PWD="$password" mariadb-dump \
  --host=mariadb \
  --user="$MYSQL_USER" \
  --single-transaction \
  --quick \
  --skip-lock-tables \
  "$MYSQL_DATABASE" | gzip -9 > "$work_dir/database.sql.gz"
unset password

tar --create --gzip --file="$work_dir/wordpress.tar.gz" --directory=/source/wordpress .
(cd "$work_dir" && sha256sum database.sql.gz wordpress.tar.gz > SHA256SUMS)
mv "$work_dir" "$final_dir"
trap - EXIT HUP INT TERM

find /backups -mindepth 1 -maxdepth 1 -type d -mtime +7 -name '20??????T??????Z' -exec rm -rf -- {} +
printf 'Backup completed: %s\n' "$final_dir"
