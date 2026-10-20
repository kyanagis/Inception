#!/bin/sh
set -eu
umask 077
[ -f /var/lib/mysql/data/.inception-complete ] && [ ! -L /var/lib/mysql/data/.inception-complete ] || exit 1
[ "$(cat /var/lib/mysql/data/.inception-complete)" = inception-database-v1 ] || exit 1
[ -f /var/lib/mysql/data/.inception-identity ] && [ ! -L /var/lib/mysql/data/.inception-identity ] || exit 1
[ ! -d /var/lib/mysql/.inception-bootstrap ] || exit 1
work=$(mktemp -d /run/mysqld/.health.XXXXXX)
trap 'rm -rf "$work"' EXIT
trap 'exit 1' HUP INT TERM
printf '%s\n%s\n%s\n' "${MYSQL_DATABASE:?}" "${MYSQL_USER:?}" "${MYSQL_BACKUP_USER:?}" > "$work/identity"
cmp -s "$work/identity" /var/lib/mysql/data/.inception-identity || exit 1
for account in root app backup; do
    case "$account" in
        root) user=root; file=/run/secrets/db_root_password;;
        app) user=${MYSQL_USER:?}; file=/run/secrets/db_password;;
        backup) user=${MYSQL_BACKUP_USER:?}; file=/run/secrets/db_backup_password;;
    esac
    [ -f "$file" ] && [ ! -L "$file" ] || exit 1
    password=$(cat "$file")
    [ "${#password}" -eq 64 ] || exit 1
    case "$password" in *[!0-9a-fA-F]*) exit 1;; esac
    printf '[client]\nuser=%s\npassword=%s\nprotocol=socket\nsocket=/run/mysqld/mysqld.sock\n' "$user" "$password" > "$work/client.cnf"
    if [ "$account" != root ]; then
        printf 'database=%s\n' "${MYSQL_DATABASE:?}" >> "$work/client.cnf"
    fi
    mariadb --defaults-file="$work/client.cnf" --batch --skip-column-names -e 'SELECT 1' >/dev/null 2>&1 || exit 1
done
