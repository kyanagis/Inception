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
mysql_uid=$(id -u mysql)
mysql_gid=$(id -g mysql)
case "$mysql_uid:$mysql_gid" in
    *[!0-9:]*) fail "Invalid mysql account identity" ;;
esac
for directory in /run/mysqld "$base"; do
    owner=$(stat -c '%u:%g' "$directory")
    case "$owner" in
        0:0)
            chmod 0750 "$directory"
            chown mysql:mysql "$directory"
            ;;
        "$mysql_uid:$mysql_gid")
            [ "$(stat -c %a "$directory")" = 750 ] || fail "Invalid database directory permissions"
            ;;
        *) fail "Invalid database directory ownership";;
    esac
done
# Hold one exclusive lock through bootstrap and the foreground server. The
# descriptor is deliberately inherited by mariadbd (which does not daemonize).
[ ! -L "$base/.inception-lock" ] || fail "Symlink database lock rejected"
[ ! -e "$base/.inception-lock" ] || [ -f "$base/.inception-lock" ] || fail "Invalid database lock file"
exec 9>> "$base/.inception-lock"
flock -n 9 || fail "Database volume is already in use"
printf '%s\n%s\n%s\n' "$MYSQL_DATABASE" "$MYSQL_USER" "$MYSQL_BACKUP_USER" > /run/mysqld/expected-identity
recover_metadata_preparations "$base" .inception-prepare-db. .inception-identity /run/mysqld/expected-identity inception-bootstrap-v1
cleanup() {
    rm -f /run/mysqld/expected-identity /run/mysqld/bootstrap.sql /run/mysqld/validate.sql /run/mysqld/bootstrap.log
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT
trap 'exit 129' HUP
bootstrap() {
    # Logs can contain SQL and passwords: never print them, and remove on exit.
    timeout --signal=TERM --kill-after=5s 90s gosu mysql mariadbd --no-defaults --bootstrap --skip-networking --datadir="$1" < "$2" > /run/mysqld/bootstrap.log 2>&1 || fail "Offline database initialization or validation failed; existing data and credentials were preserved"
}
validate_accounts() {
    # Bootstrap bypasses authentication. Explicitly validate only the native-
    # password account format managed by this project; reject unsupported
    # plugins, alternative authentication, locks, expiry and host overrides.
    cat > /run/mysqld/validate.sql <<SQL
FLUSH PRIVILEGES;
IF (SELECT COUNT(*) FROM mysql.global_priv WHERE User='') <> 0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Anonymous host overrides are unsupported'; END IF;
SQL
    for account in root app backup; do
        case "$account" in
            root) user=root; host=localhost; password=$root_password;;
            app) user=$MYSQL_USER; host=%; password=$app_password;;
            backup) user=$MYSQL_BACKUP_USER; host=%; password=$backup_password;;
        esac
        cat >> /run/mysqld/validate.sql <<SQL
IF (SELECT COUNT(*) FROM mysql.global_priv WHERE User='${user}') <> 1 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Managed account missing or host override present'; END IF;
IF (SELECT COUNT(*) FROM mysql.global_priv WHERE User='${user}' AND Host='${host}' AND JSON_UNQUOTE(JSON_EXTRACT(Priv,'$.plugin'))='mysql_native_password' AND BINARY JSON_UNQUOTE(JSON_EXTRACT(Priv,'$.authentication_string'))=BINARY PASSWORD('${password}') AND COALESCE(JSON_LENGTH(JSON_EXTRACT(Priv,'$.auth_or')),0)=0 AND COALESCE(JSON_UNQUOTE(JSON_EXTRACT(Priv,'$.account_locked')),'false') IN ('false','0') AND COALESCE(JSON_UNQUOTE(JSON_EXTRACT(Priv,'$.password_lifetime')),'0')='0' AND CAST(COALESCE(JSON_UNQUOTE(JSON_EXTRACT(Priv,'$.password_last_changed')),'0') AS UNSIGNED)>0) <> 1 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Managed account secret or authentication policy differs'; END IF;
SQL
    done
    cat >> /run/mysqld/validate.sql <<SQL
IF (SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='${MYSQL_DATABASE}') <> 1 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Managed database is missing'; END IF;
IF (SELECT COUNT(*) FROM mysql.db WHERE User='${MYSQL_USER}' AND Host='%' AND BINARY Db=BINARY '${MYSQL_DATABASE}' AND Select_priv='Y' AND Insert_priv='Y' AND Update_priv='Y' AND Delete_priv='Y' AND Create_priv='Y' AND Drop_priv='Y' AND Alter_priv='Y' AND Index_priv='Y') <> 1 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Application database privileges differ'; END IF;
IF (SELECT COUNT(*) FROM mysql.db WHERE User='${MYSQL_BACKUP_USER}' AND Host='%' AND BINARY Db=BINARY '${MYSQL_DATABASE}' AND Select_priv='Y' AND Show_view_priv='Y' AND Trigger_priv='Y' AND Event_priv='Y') <> 1 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Backup database privileges differ'; END IF;
SQL
    bootstrap "$1" /run/mysqld/validate.sql
    rm -f /run/mysqld/validate.sql /run/mysqld/bootstrap.log
}
committed_state() {
    [ -d "$1" ] && [ ! -L "$1/.inception-complete" ] && [ -f "$1/.inception-complete" ] && [ "$(cat "$1/.inception-complete")" = inception-database-v1 ] || fail "Unrecognized completion marker; preserving data"
    [ ! -L "$1/.inception-identity" ] && [ -f "$1/.inception-identity" ] && cmp -s /run/mysqld/expected-identity "$1/.inception-identity" || fail "Database identity or legacy format differs; restore original configuration or migrate explicitly from a verified backup"
}
if [ -e "$data" ]; then
    committed_state "$data"
    [ ! -e "$staging" ] || fail "Unexpected bootstrap directory alongside committed database"
    validate_accounts "$data"

else
    for entry in "$base"/* "$base"/.[!.]* "$base"/..?*; do
        [ -e "$entry" ] || [ -L "$entry" ] || continue
        [ "$entry" = "$base/.inception-lock" ] || [ "$entry" = "$staging" ] || fail "Unknown database contents; preserving data"
    done
    if [ -e "$staging" ]; then
        [ -d "$staging" ] && [ ! -L "$staging/.inception-owned" ] && [ -f "$staging/.inception-owned" ] || fail "Unrecognized staging directory"
        [ "$(cat "$staging/.inception-owned")" = inception-bootstrap-v1 ] || fail "Unrecognized staging marker"
        [ ! -L "$staging/.inception-identity" ] && cmp -s /run/mysqld/expected-identity "$staging/.inception-identity" || fail "Bootstrap identifiers changed"
        [ ! -L "$staging/.inception-complete" ] || fail "Symlink completion marker rejected"
        if [ ! -e "$staging/.inception-complete" ]; then rm -rf -- "$staging"; else committed_state "$staging"; fi
    fi
    if [ ! -d "$staging" ]; then
        publish_metadata "$base" .inception-prepare-db. .inception-identity /run/mysqld/expected-identity inception-bootstrap-v1 "$staging"
        chmod 0750 "$staging"
        chown mysql:mysql "$staging"
        gosu mysql mariadb-install-db --auth-root-authentication-method=normal --datadir="$staging" --skip-test-db >/dev/null
        bootstrap_sql=/run/mysqld/bootstrap.sql
        cat > "$bootstrap_sql" <<SQL
FLUSH PRIVILEGES;
CREATE DATABASE \`${MYSQL_DATABASE}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER '${MYSQL_USER}'@'%' IDENTIFIED BY '${app_password}';
GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
CREATE USER '${MYSQL_BACKUP_USER}'@'%' IDENTIFIED BY '${backup_password}';
GRANT SELECT, SHOW VIEW, TRIGGER, EVENT ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_BACKUP_USER}'@'%';
ALTER USER 'root'@'localhost' IDENTIFIED BY '${root_password}';
DELETE FROM mysql.global_priv WHERE User = '' OR (User = 'root' AND Host <> 'localhost');
FLUSH PRIVILEGES;
SQL
        bootstrap "$staging" "$bootstrap_sql"
        rm -f "$bootstrap_sql" /run/mysqld/bootstrap.log
        validate_accounts "$staging"
        printf '%s\n' inception-database-v1 > "$staging/.inception-complete.tmp"
        mv "$staging/.inception-complete.tmp" "$staging/.inception-complete"
    else
        validate_accounts "$staging"
    fi
    mv -T "$staging" "$data"
fi
cleanup
trap - EXIT HUP INT TERM
unset root_password app_password backup_password value password
exec gosu mysql "$@" --console --datadir="$data"
