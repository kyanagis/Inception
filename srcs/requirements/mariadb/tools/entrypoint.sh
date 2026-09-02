#!/bin/sh
set -eu

read_secret() {
  secret_path=$1
  [ -r "$secret_path" ] || { echo "Missing secret: $secret_path" >&2; exit 1; }
  secret_value=$(tr -d '\r\n' < "$secret_path")
  [ -n "$secret_value" ] || { echo "Empty secret: $secret_path" >&2; exit 1; }
  printf '%s' "$secret_value"
}

validate_identifier() {
  case "$2" in
    ''|*[!A-Za-z0-9_]*) echo "$1 contains unsupported characters" >&2; exit 2 ;;
  esac
}

escape_sql_string() {
  printf '%s' "$1" | sed "s/'/''/g"
}

if [ "${1:-}" != "mariadbd" ]; then
  exec "$@"
fi

: "${MYSQL_DATABASE:?MYSQL_DATABASE is required}"
: "${MYSQL_USER:?MYSQL_USER is required}"
validate_identifier MYSQL_DATABASE "$MYSQL_DATABASE"
validate_identifier MYSQL_USER "$MYSQL_USER"

mkdir -p /run/mysqld /var/lib/mysql
chown mysql:mysql /run/mysqld
chown -R mysql:mysql /var/lib/mysql

if [ ! -d /var/lib/mysql/mysql ]; then
  db_password=$(read_secret /run/secrets/db_password)
  root_password=$(read_secret /run/secrets/db_root_password)
  db_password_sql=$(escape_sql_string "$db_password")
  root_password_sql=$(escape_sql_string "$root_password")

  gosu mysql mariadb-install-db \
    --auth-root-authentication-method=normal \
    --datadir=/var/lib/mysql \
    --skip-test-db >/dev/null

  gosu mysql mariadbd \
    --datadir=/var/lib/mysql \
    --skip-networking \
    --socket=/run/mysqld/mysqld.sock \
    --pid-file=/run/mysqld/mysqld.pid &
  bootstrap_pid=$!
  trap 'kill "$bootstrap_pid" 2>/dev/null || true; wait "$bootstrap_pid" 2>/dev/null || true' EXIT HUP INT TERM

  ready=0
  for _attempt in $(seq 1 60); do
    if mariadb-admin --protocol=socket --socket=/run/mysqld/mysqld.sock ping --silent >/dev/null 2>&1; then
      ready=1
      break
    fi
    sleep 1
  done
  if [ "$ready" -ne 1 ]; then
    echo "MariaDB bootstrap did not become ready" >&2
    exit 1
  fi

  mariadb --protocol=socket --socket=/run/mysqld/mysqld.sock <<SQL
SET SESSION sql_mode = 'NO_BACKSLASH_ESCAPES';
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${db_password_sql}';
ALTER USER '${MYSQL_USER}'@'%' IDENTIFIED BY '${db_password_sql}';
GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
ALTER USER 'root'@'localhost' IDENTIFIED BY '${root_password_sql}';
DELETE FROM mysql.user WHERE User = '';
FLUSH PRIVILEGES;
SHUTDOWN;
SQL
  wait "$bootstrap_pid"
  trap - EXIT HUP INT TERM
  unset db_password root_password db_password_sql root_password_sql
fi

exec gosu mysql "$@"
