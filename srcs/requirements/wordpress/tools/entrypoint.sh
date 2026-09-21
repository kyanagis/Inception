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
[ "${1:-}" = php-fpm8.2 ] || exec "$@"
: "${DOMAIN_NAME:?DOMAIN_NAME required}"
: "${MYSQL_DATABASE:?MYSQL_DATABASE required}"
: "${MYSQL_USER:?MYSQL_USER required}"
: "${WP_TITLE:?WP_TITLE required}"
: "${WP_ADMIN_USER:?WP_ADMIN_USER required}"
: "${WP_ADMIN_EMAIL:?WP_ADMIN_EMAIL required}"
: "${WP_USER:?WP_USER required}"
: "${WP_USER_EMAIL:?WP_USER_EMAIL required}"
case "$MYSQL_DATABASE:$MYSQL_USER" in *[!A-Za-z0-9_:]*|:*|*:) fail "Invalid database identifiers";; esac
case "$WP_ADMIN_USER:$WP_USER" in *[!A-Za-z0-9_:-]*|:*|*:) fail "Invalid WordPress usernames";; esac
case "$WP_ADMIN_USER" in *[Aa][Dd][Mm][Ii][Nn]*) fail "Administrator name must not contain admin";; esac
[ "$WP_ADMIN_USER" != "$WP_USER" ] || fail "WordPress users must differ"
case "$DOMAIN_NAME" in *[!a-z0-9.-]*|.*|*..*) fail "Invalid domain";; esac
case "$DOMAIN_NAME" in *.42.fr) ;; *) fail "Domain must end in .42.fr";; esac
export WP_REDIS_DISABLED=${WP_REDIS_DISABLED:-1}
case "$WP_REDIS_DISABLED" in 0|1) ;; *) fail "WP_REDIS_DISABLED must be 0 or 1";; esac
base=/var/www
html=$base/html
state=$base/.inception-state
staging=$base/.inception-wordpress
for path in "$base" "$html" "$state" "$staging"; do [ ! -L "$path" ] || fail "Symlink WordPress path rejected"; done
mkdir -p /run/php
chmod 0755 /run/php
chown www-data:www-data /run/php
cleanup() { rm -f /run/php/app-client.cnf /run/php/wp-admin-password /run/php/wp-user-password /run/php/expected-identity; }
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT
trap 'exit 129' HUP
for pair in db:db_password redis:redis_password wp-admin:wp_admin_password wp-user:wp_user_password; do
    target=${pair%%:*}
    name=${pair#*:}
    password=$(secret "/run/secrets/$name")
    case "$target" in db) runtime=/run/php/db_password;; redis) runtime=/run/php/redis_password;; *) runtime=/run/php/$target-password;; esac
    printf '%s\n' "$password" > "$runtime"
    chmod 0400 "$runtime"
    chown www-data:www-data "$runtime"
    if [ "$target" = db ]; then
        printf '[client]\nhost=mariadb\nuser=%s\npassword=%s\ndatabase=%s\n' "$MYSQL_USER" "$password" "$MYSQL_DATABASE" > /run/php/app-client.cnf
    fi
done
unset password value
printf '%s\n%s\n%s\n%s\n%s\n' "$DOMAIN_NAME" "$MYSQL_DATABASE" "$MYSQL_USER" "$WP_ADMIN_USER" "$WP_USER" > /run/php/expected-identity
recover_metadata_preparations "$base" .inception-prepare-wp. identity /run/php/expected-identity inception-wordpress-state-v1
if [ -d "$state" ]; then
    [ ! -L "$state/identity" ] && cmp -s /run/php/expected-identity "$state/identity" || fail "WordPress identity changed or incomplete; preserving data"
else
    if [ -d "$html" ]; then rmdir "$html" 2>/dev/null || fail "Unknown existing WordPress data; preserving data"; fi
    for entry in "$base"/* "$base"/.[!.]* "$base"/..?*; do
        [ -e "$entry" ] || [ -L "$entry" ] || continue
        fail "Unknown WordPress volume contents; preserving data"
    done
    publish_metadata "$base" .inception-prepare-wp. identity /run/php/expected-identity inception-wordpress-state-v1 "$state"
fi
ready=0
for attempt in $(seq 1 60); do
    if mariadb --defaults-file=/run/php/app-client.cnf --batch --skip-column-names -e 'SELECT 1' >/dev/null 2>&1; then ready=1; break; fi
    sleep 1
done
[ "$ready" = 1 ] || fail "Database authentication did not succeed"
if [ -d "$html" ] && [ ! -f "$state/complete" ] &&
    [ -z "$(find "$html" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
    rmdir "$html"
fi
if [ ! -e "$html" ]; then
    [ ! -e "$staging" ] || rm -rf -- "$staging"
    mkdir "$staging"
    chmod 0755 "$staging"
    chown www-data:www-data "$staging"
    cp -R /usr/src/wordpress/. "$staging/"
    [ -f "$staging/wp-includes/version.php" ] && [ -f "$staging/wp-settings.php" ] || fail "Incomplete WordPress distribution"
    diff -qr /usr/src/wordpress "$staging" >/dev/null || fail "WordPress staging verification failed"
    chown -R www-data:www-data "$staging"
    mv -T "$staging" "$html"
fi
[ -d "$html" ] && [ -f "$html/wp-includes/version.php" ] || fail "Invalid committed WordPress files"
[ ! -L "$html/wp-config.php" ] || fail "Symlink WordPress configuration rejected"
if [ ! -f "$html/wp-config.php" ]; then
    config=$(mktemp "$html/.wp-config.XXXXXX")
    php /usr/local/lib/inception/configure.php > "$config"
    php -l "$config" >/dev/null || fail "Invalid generated WordPress configuration"
    chmod 0640 "$config"
    chown www-data:www-data "$config"
    mv -T "$config" "$html/wp-config.php"
fi
as_wp() { runuser -u www-data -- wp --path="$html" "$@"; }
if ! as_wp core is-installed >/dev/null 2>&1; then
    tables=$(mariadb --defaults-file=/run/php/app-client.cnf --batch --skip-column-names -e 'SHOW TABLES') || fail "Unable to inspect existing WordPress schema"
    [ -z "$tables" ] || fail "Incomplete WordPress database; preserve data and restore or explicitly reset an unused installation"
    if ! as_wp core install --url="https://$DOMAIN_NAME" --title="$WP_TITLE" --admin_user="$WP_ADMIN_USER" --admin_email="$WP_ADMIN_EMAIL" --skip-email --prompt=admin_password < /run/php/wp-admin-password >/dev/null 2>&1; then
        fail "WordPress installation failed; existing tables preserved"
    fi
fi
as_wp eval-file /usr/local/lib/inception/check-account.php "$WP_ADMIN_USER" administrator /run/php/wp-admin-password >/dev/null
[ "$(as_wp option get home)" = "https://$DOMAIN_NAME" ] && [ "$(as_wp option get siteurl)" = "https://$DOMAIN_NAME" ] || fail "WordPress URL differs from configured domain"
if ! as_wp user get "$WP_USER" --field=ID >/dev/null 2>&1; then
    [ ! -f "$state/complete" ] || fail "Configured WordPress user has been removed; preserving database"
    as_wp user create "$WP_USER" "$WP_USER_EMAIL" --role=author --prompt=user_pass < /run/php/wp-user-password >/dev/null 2>&1 || fail "WordPress regular-user creation failed"
fi
as_wp eval-file /usr/local/lib/inception/check-account.php "$WP_USER" author /run/php/wp-user-password >/dev/null
chown -R www-data:www-data "$html/wp-content"
if [ "$WP_REDIS_DISABLED" = 0 ]; then
    as_wp plugin activate redis-cache >/dev/null
    as_wp redis enable >/dev/null
else
    as_wp redis disable >/dev/null 2>&1 || true
fi
if [ ! -f "$state/complete" ]; then
    as_wp rewrite structure '/%postname%/' --hard >/dev/null 2>&1
    printf '%s\n' inception-wordpress-v1 > "$state/complete.tmp"
    mv "$state/complete.tmp" "$state/complete"
fi
mkdir -p "$html/wp-content/uploads"
find "$html" -xdev -type d -exec chown root:www-data {} + -exec chmod 0755 {} +
find "$html" -xdev -type f -exec chown root:www-data {} + -exec chmod 0644 {} +
find "$html/wp-content/uploads" -xdev -type d -exec chown www-data:www-data {} + -exec chmod 0755 {} +
find "$html/wp-content/uploads" -xdev -type f -exec chown www-data:www-data {} + -exec chmod 0644 {} +
chown root:www-data "$html/wp-config.php"
chmod 0640 "$html/wp-config.php"
cleanup
trap - EXIT HUP INT TERM
exec "$@"
