#!/bin/sh
set -eu

nc -z 127.0.0.1 9000
runuser -u www-data -- wp --path=/var/www/html db check --quiet >/dev/null 2>&1

case "${WP_REDIS_DISABLED:-1}" in
  0)
    runuser -u www-data -- wp --path=/var/www/html plugin is-active redis-cache >/dev/null 2>&1
    [ -f /var/www/html/wp-content/object-cache.php ] &&
      [ ! -L /var/www/html/wp-content/object-cache.php ]
    runuser -u www-data -- wp --path=/var/www/html eval '
      global $wp_object_cache;
      if (!method_exists($wp_object_cache, "redis_status") || !$wp_object_cache->redis_status()) {
          exit(1);
      }
    ' >/dev/null 2>&1
    ;;
  1)
    # Mandatory mode must not accidentally keep the Redis drop-in enabled from
    # a previous bonus run.  The plugin itself may remain installed/active.
    [ ! -e /var/www/html/wp-content/object-cache.php ] &&
      [ ! -L /var/www/html/wp-content/object-cache.php ]
    ;;
  *)
    exit 1
    ;;
esac
