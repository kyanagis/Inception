#!/bin/sh
set -eu

project_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$project_dir"
compose='docker --host unix:///var/run/docker.sock compose --env-file srcs/.env -f srcs/docker-compose.yml --profile bonus'
fail() { printf 'Restore test: %s\n' "$*" >&2; exit 1; }

DOMAIN_NAME=$(sed -n 's/^DOMAIN_NAME=//p' srcs/.env)
[ -n "$DOMAIN_NAME" ] || fail 'Missing DOMAIN_NAME'

latest=$($compose exec -T backup sh -ec "ls -1 /backups | grep -E '^[0-9]{8}T[0-9]{6}Z-' | sort | tail -n 1")
[ -n "$latest" ] || fail 'No committed backup directory found'
$compose exec -T backup /usr/local/bin/backup-manifest verify "/backups/$latest"

restore_db="inception_restore_probe_$$"
cleanup() {
  $compose exec -T mariadb sh -ec '
    root=$(tr -d "\r\n" < /run/secrets/db_root_password)
    mariadb -uroot -p"$root" -e "DROP DATABASE IF EXISTS $1"
  ' sh "$restore_db" >/dev/null 2>&1 || true
}
trap cleanup EXIT HUP INT TERM

$compose exec -T mariadb sh -ec '
  root=$(tr -d "\r\n" < /run/secrets/db_root_password)
  mariadb -uroot -p"$root" -e "CREATE DATABASE $1 CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
' sh "$restore_db"

$compose exec -T backup sh -ec 'gzip -dc "/backups/$1/database.sql.gz"' sh "$latest" |
  $compose exec -T mariadb sh -ec '
    root=$(tr -d "\r\n" < /run/secrets/db_root_password)
    exec mariadb -uroot -p"$root" "$1"
  ' sh "$restore_db"

restored_site=$($compose exec -T mariadb sh -ec '
  root=$(tr -d "\r\n" < /run/secrets/db_root_password)
  mariadb -N -B -uroot -p"$root" "$1" -e "SELECT option_value FROM wp_options WHERE option_name = '''siteurl''' LIMIT 1"
' sh "$restore_db")
[ "$restored_site" = "https://$DOMAIN_NAME" ] ||
  fail "Restored database siteurl mismatch: $restored_site"

$compose exec -T mariadb sh -ec '
  root=$(tr -d "\r\n" < /run/secrets/db_root_password)
  mariadb -N -B -uroot -p"$root" "$1" -e "SHOW TABLES LIKE '''wp_options'''" | grep -Fx wp_options
' sh "$restore_db" >/dev/null || fail 'Restored database is missing wp_options'

$compose exec -T backup sh -ec '
  set -eu
  restore=$(mktemp -d /tmp/inception-restore.XXXXXXXX)
  trap '''rm -rf "$restore"''' EXIT HUP INT TERM
  tar -xzf "/backups/$1/wordpress.tar.gz" -C "$restore"
  test -f "$restore/wp-settings.php"
  test -f "$restore/wp-includes/version.php"
  test -d "$restore/wp-content"
' sh "$latest" || fail 'WordPress file restore drill failed'

cleanup
trap - EXIT HUP INT TERM
printf 'Backup restore drill passed: %s\n' "$latest"
