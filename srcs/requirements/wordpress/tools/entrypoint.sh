#!/bin/sh
set -eu

read_secret() {
  secret_path=$1
  [ -r "$secret_path" ] || { echo "Missing secret: $secret_path" >&2; exit 1; }
  secret_value=$(tr -d '\r\n' < "$secret_path")
  [ -n "$secret_value" ] || { echo "Empty secret: $secret_path" >&2; exit 1; }
  printf '%s' "$secret_value"
}

validate_name() {
  case "$2" in
    ''|*[!A-Za-z0-9_-]*) echo "$1 contains unsupported characters" >&2; exit 2 ;;
  esac
}

if [ "${1:-}" != "php-fpm8.2" ]; then
  exec "$@"
fi

: "${DOMAIN_NAME:?DOMAIN_NAME is required}"
: "${MYSQL_DATABASE:?MYSQL_DATABASE is required}"
: "${MYSQL_USER:?MYSQL_USER is required}"
: "${WP_TITLE:?WP_TITLE is required}"
: "${WP_ADMIN_USER:?WP_ADMIN_USER is required}"
: "${WP_ADMIN_EMAIL:?WP_ADMIN_EMAIL is required}"
: "${WP_USER:?WP_USER is required}"
: "${WP_USER_EMAIL:?WP_USER_EMAIL is required}"

validate_name MYSQL_DATABASE "$MYSQL_DATABASE"
validate_name MYSQL_USER "$MYSQL_USER"
validate_name WP_ADMIN_USER "$WP_ADMIN_USER"
validate_name WP_USER "$WP_USER"
case "$WP_ADMIN_USER" in
  *[Aa][Dd][Mm][Ii][Nn]*) echo "WP_ADMIN_USER must not contain admin" >&2; exit 2 ;;
esac
if [ "$WP_ADMIN_USER" = "$WP_USER" ]; then
  echo "The administrator and regular user must be different" >&2
  exit 2
fi

install -d -o www-data -g www-data -m 0755 /run/php /var/www/html
if [ ! -f /var/www/html/wp-includes/version.php ]; then
  cp -R --no-preserve=ownership,mode,timestamps /usr/src/wordpress/. /var/www/html/
fi
chown -R www-data:www-data /var/www/html

db_password=$(read_secret /run/secrets/db_password)
printf '%s\n' "$db_password" > /run/php/db_password
chmod 0440 /run/php/db_password
chown www-data:www-data /run/php/db_password

as_wp() {
  runuser -u www-data -- wp --path=/var/www/html "$@"
}

ready=0
for _attempt in $(seq 1 60); do
  if MYSQL_PWD="$db_password" mariadb-admin \
      --host=mariadb --user="$MYSQL_USER" ping --silent >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 1
done
unset db_password
if [ "$ready" -ne 1 ]; then
  echo "MariaDB did not become ready" >&2
  exit 1
fi

if [ ! -f /var/www/html/wp-config.php ]; then
  as_wp config create \
    --dbname="$MYSQL_DATABASE" \
    --dbuser="$MYSQL_USER" \
    --dbpass=placeholder \
    --dbhost=mariadb:3306 \
    --dbcharset=utf8mb4 \
    --skip-check
  as_wp config set FORCE_SSL_ADMIN true --raw
  as_wp config set DISALLOW_FILE_EDIT true --raw
  as_wp config set WP_AUTO_UPDATE_CORE minor
  as_wp config set WP_REDIS_HOST redis
  as_wp config set WP_REDIS_PORT 6379 --raw
  as_wp config set WP_REDIS_DATABASE 0 --raw
  as_wp config set WP_REDIS_PREFIX "${DOMAIN_NAME}:"
  as_wp config shuffle-salts
fi

as_wp config set DB_PASSWORD "trim( file_get_contents( '/run/php/db_password' ) )" --raw
as_wp config set WP_REDIS_GRACEFUL true --raw

if ! as_wp core is-installed >/dev/null 2>&1; then
  admin_password=$(read_secret /run/secrets/wp_admin_password)
  if ! printf '%s\n' "$admin_password" | as_wp core install \
      --url="https://${DOMAIN_NAME}" \
      --title="$WP_TITLE" \
      --admin_user="$WP_ADMIN_USER" \
      --admin_email="$WP_ADMIN_EMAIL" \
      --skip-email \
      --prompt=admin_password >/dev/null 2>&1; then
    echo "WordPress core installation failed" >&2
    exit 1
  fi
  unset admin_password
fi

if ! as_wp user get "$WP_USER" >/dev/null 2>&1; then
  user_password=$(read_secret /run/secrets/wp_user_password)
  if ! printf '%s\n' "$user_password" | as_wp user create "$WP_USER" "$WP_USER_EMAIL" \
      --role=author --prompt=user_pass >/dev/null 2>&1; then
    echo "WordPress regular-user creation failed" >&2
    exit 1
  fi
  unset user_password
fi

as_wp option update home "https://${DOMAIN_NAME}" >/dev/null
as_wp option update siteurl "https://${DOMAIN_NAME}" >/dev/null
as_wp rewrite structure '/%postname%/' --hard >/dev/null 2>&1

exec "$@"
