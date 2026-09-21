#!/bin/sh
set -eu
umask 077
[ -f /var/lib/mysql/data/.inception-complete ] || exit 1
[ ! -d /var/lib/mysql/.inception-bootstrap ] || exit 1
work=$(mktemp -d /run/mysqld/.health.XXXXXX)
trap 'rm -rf "$work"' EXIT
trap 'exit 1' HUP INT TERM
for account in root app; do
    case "$account" in
        root) user=root; file=/run/secrets/db_root_password;;
        app) user=${MYSQL_USER:?}; file=/run/secrets/db_password;;
    esac
    password=$(cat "$file")
    [ "${#password}" -eq 64 ] || exit 1
    case "$password" in *[!0-9a-fA-F]*) exit 1;; esac
    printf '[client]\nuser=%s\npassword=%s\nprotocol=socket\nsocket=/run/mysqld/mysqld.sock\n' "$user" "$password" > "$work/client.cnf"
    mariadb --defaults-file="$work/client.cnf" --batch --skip-column-names -e 'SELECT 1' >/dev/null 2>&1 || exit 1
done
