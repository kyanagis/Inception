#!/bin/sh
set -eu
umask 077
fail() { printf '%s\n' "$*" >&2; exit 1; }
. /usr/local/lib/inception/prepare-state.sh
secret() {
    [ -f "$1" ] && [ ! -L "$1" ] || fail "Missing or invalid secret"
    value=$(cat "$1")
    [ "${#value}" -eq 64 ] || fail "Secret must contain 64 hexadecimal characters"
    case "$value" in *[!0-9a-fA-F]*) fail "Invalid secret format";; esac
    printf '%s' "$value"
}
[ "${1:-}" = mariadbd ] || exec "$@"
: "${MYSQL_DATABASE:?MYSQL_DATABASE required}"
: "${MYSQL_USER:?MYSQL_USER required}"
: "${MYSQL_BACKUP_USER:?MYSQL_BACKUP_USER required}"
case "$MYSQL_DATABASE:$MYSQL_USER:$MYSQL_BACKUP_USER" in *[!a-zA-Z0-9_:]*|:*|*::*|*:) fail "Invalid database identifiers";; esac
[ "$MYSQL_USER" != root ] || fail "Application database user must not be root"
[ "$MYSQL_BACKUP_USER" != root ] && [ "$MYSQL_BACKUP_USER" != "$MYSQL_USER" ] || fail "Backup database user must be distinct"
root_password=$(secret /run/secrets/db_root_password)
app_password=$(secret /run/secrets/db_password)
backup_password=$(secret /run/secrets/db_backup_password)
base=/var/lib/mysql
staging=$base/.inception-bootstrap
data=$base/data
[ ! -L "$base" ] && [ ! -L "$data" ] && [ ! -L "$staging" ] || fail "Symlink database path rejected"
mkdir -p /run/mysqld "$base"
for directory in /run/mysqld "$base"; do
    owner=$(stat -c '%u:%g' "$directory")
    case "$owner" in
        0:0)
            chmod 0750 "$directory"
            chown mysql:mysql "$directory"
            ;;
        100:101)
            [ "$(stat -c %a "$directory")" = 750 ] || fail "Invalid database directory permissions"
            ;;
        *) fail "Invalid database directory ownership";;
    esac
done
printf '[client]\nuser=root\npassword=%s\nprotocol=socket\nsocket=/run/mysqld/mysqld.sock\n' "$root_password" > /run/mysqld/root-client.cnf
printf '[client]\nuser=%s\npassword=%s\nprotocol=socket\nsocket=/run/mysqld/mysqld.sock\ndatabase=%s\n' "$MYSQL_USER" "$app_password" "$MYSQL_DATABASE" > /run/mysqld/app-client.cnf
printf '[client]\nuser=%s\npassword=%s\nprotocol=socket\nsocket=/run/mysqld/mysqld.sock\ndatabase=%s\n' "$MYSQL_BACKUP_USER" "$backup_password" "$MYSQL_DATABASE" > /run/mysqld/backup-client.cnf
printf '%s\n%s\n%s\n' "$MYSQL_DATABASE" "$MYSQL_USER" "$MYSQL_BACKUP_USER" > /run/mysqld/expected-identity
printf '%s\n%s\n' "$MYSQL_DATABASE" "$MYSQL_USER" > /run/mysqld/legacy-identity
recover_metadata_preparations "$base" .inception-prepare-db. .inception-identity /run/mysqld/expected-identity inception-bootstrap-v1
bootstrap_pid=
cleanup() {
    if [ -n "$bootstrap_pid" ]; then
        mariadb-admin --defaults-file=/run/mysqld/root-client.cnf shutdown >/dev/null 2>&1 ||
            mariadb-admin --protocol=socket --socket=/run/mysqld/mysqld.sock --user=root shutdown >/dev/null 2>&1 || true
        wait "$bootstrap_pid" 2>/dev/null || true
    fi
    rm -f /run/mysqld/root-client.cnf /run/mysqld/app-client.cnf /run/mysqld/backup-client.cnf /run/mysqld/expected-identity /run/mysqld/legacy-identity
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT
trap 'exit 129' HUP
start_private() {
    gosu mysql mariadbd --console --datadir="$1" --skip-networking --socket=/run/mysqld/mysqld.sock --pid-file=/run/mysqld/mysqld.pid &
    bootstrap_pid=$!
    for attempt in $(seq 1 60); do
        if [ -S /run/mysqld/mysqld.sock ] && {
            mariadb --defaults-file=/run/mysqld/root-client.cnf --batch --skip-column-names -e 'SELECT 1' >/dev/null 2>&1 ||
            mariadb --protocol=socket --socket=/run/mysqld/mysqld.sock --user=root --batch --skip-column-names -e 'SELECT 1' >/dev/null 2>&1
        }; then
            server_pid=$(cat /run/mysqld/mysqld.pid)
            [ -d "/proc/$server_pid" ] || fail "Private database PID is not running"
            bootstrap_pid=$server_pid
            return
        fi
        if [ -f /run/mysqld/mysqld.pid ]; then
            server_pid=$(cat /run/mysqld/mysqld.pid)
            [ -d "/proc/$server_pid" ] || fail "Private database startup failed"
            bootstrap_pid=$server_pid
        elif [ ! -d "/proc/$bootstrap_pid" ]; then
            fail "Private database startup failed"
        fi
        sleep 1
    done
    fail "Private database startup timed out"
}
verify_accounts() {
    mariadb --defaults-file=/run/mysqld/root-client.cnf --batch --skip-column-names -e 'SELECT 1' >/dev/null 2>&1 || fail "Root database secret does not match existing data"
    mariadb --defaults-file=/run/mysqld/app-client.cnf --batch --skip-column-names -e 'SELECT 1' >/dev/null 2>&1 || fail "Application database secret does not match existing data"
    mariadb --defaults-file=/run/mysqld/backup-client.cnf --batch --skip-column-names -e 'SELECT 1' >/dev/null 2>&1 || fail "Backup database secret does not match existing data"
}
stop_private() {
    mariadb-admin --defaults-file=/run/mysqld/root-client.cnf shutdown >/dev/null 2>&1 || fail "Private database shutdown failed"
    wait "$bootstrap_pid"
    bootstrap_pid=
}
if [ -e "$data" ]; then
    [ -d "$data" ] && [ -f "$data/.inception-complete" ] || fail "Unrecognized existing database; preserving data"
    [ ! -e "$staging" ] || fail "Unexpected bootstrap directory alongside committed database"
    if cmp -s /run/mysqld/legacy-identity "$data/.inception-identity"; then
        start_private "$data"
        mariadb --defaults-file=/run/mysqld/root-client.cnf >/dev/null 2>&1 <<SQL
CREATE USER IF NOT EXISTS '${MYSQL_BACKUP_USER}'@'%' IDENTIFIED BY '${backup_password}';
ALTER USER '${MYSQL_BACKUP_USER}'@'%' IDENTIFIED BY '${backup_password}';
GRANT SELECT, SHOW VIEW, TRIGGER, EVENT ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_BACKUP_USER}'@'%';
FLUSH PRIVILEGES;
SQL
        verify_accounts
        stop_private
        cp /run/mysqld/expected-identity "$data/.inception-identity.tmp"
        chown mysql:mysql "$data/.inception-identity.tmp"
        chmod 0600 "$data/.inception-identity.tmp"
        mv -T "$data/.inception-identity.tmp" "$data/.inception-identity"
    else
        cmp -s /run/mysqld/expected-identity "$data/.inception-identity" || fail "Database identifiers changed; restore original configuration"
    fi
    start_private "$data"
    verify_accounts
    stop_private
else
    for entry in "$base"/* "$base"/.[!.]* "$base"/..?*; do
        [ -e "$entry" ] || [ -L "$entry" ] || continue
        [ "$entry" = "$staging" ] || fail "Unknown database contents; preserving data"
    done
    if [ -e "$staging" ]; then
        [ -d "$staging" ] && [ ! -L "$staging/.inception-owned" ] && [ -f "$staging/.inception-owned" ] || fail "Unrecognized staging directory"
        [ "$(cat "$staging/.inception-owned")" = inception-bootstrap-v1 ] || fail "Unrecognized staging marker"
        cmp -s /run/mysqld/expected-identity "$staging/.inception-identity" || fail "Bootstrap identifiers changed"
        if [ ! -f "$staging/.inception-complete" ]; then rm -rf -- "$staging"; fi
    fi
    if [ ! -d "$staging" ]; then
        publish_metadata "$base" .inception-prepare-db. .inception-identity /run/mysqld/expected-identity inception-bootstrap-v1 "$staging"
        chmod 0750 "$staging"
        chown mysql:mysql "$staging"
        gosu mysql mariadb-install-db --auth-root-authentication-method=normal --datadir="$staging" --skip-test-db >/dev/null
        start_private "$staging"
        mariadb --protocol=socket --socket=/run/mysqld/mysqld.sock >/dev/null 2>&1 <<SQL
CREATE DATABASE \`${MYSQL_DATABASE}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER '${MYSQL_USER}'@'%' IDENTIFIED BY '${app_password}';
GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
CREATE USER '${MYSQL_BACKUP_USER}'@'%' IDENTIFIED BY '${backup_password}';
GRANT SELECT, SHOW VIEW, TRIGGER, EVENT ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_BACKUP_USER}'@'%';
ALTER USER 'root'@'localhost' IDENTIFIED BY '${root_password}';
DELETE FROM mysql.global_priv WHERE User = '' OR (User = 'root' AND Host <> 'localhost');
FLUSH PRIVILEGES;
SQL
        verify_accounts
        stop_private
        printf '%s\n' inception-database-v1 > "$staging/.inception-complete.tmp"
        mv "$staging/.inception-complete.tmp" "$staging/.inception-complete"
    else
        start_private "$staging"
        verify_accounts
        stop_private
    fi
    mv -T "$staging" "$data"
fi
cleanup
trap - EXIT HUP INT TERM
unset root_password app_password backup_password value
exec gosu mysql "$@" --console --datadir="$data"
