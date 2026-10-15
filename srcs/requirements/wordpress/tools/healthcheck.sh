#!/bin/sh
set -eu

nc -z 127.0.0.1 9000
runuser -u www-data -- wp --path=/var/www/html db check --quiet >/dev/null 2>&1

case "${WP_REDIS_DISABLED:-1}" in
  0)
    [ -f /var/www/html/wp-content/object-cache.php ] &&
      [ ! -L /var/www/html/wp-content/object-cache.php ]
    runuser -u www-data -- php -r '
      $password = trim(file_get_contents("/run/php/redis_password"));
      if ($password === "") {
          exit(2);
      }
      $redis = new Redis();
      if (!$redis->connect("redis", 6379, 1.0)) {
          exit(3);
      }
      if (!$redis->auth(["wordpress", $password])) {
          exit(4);
      }
      $pong = $redis->ping();
      if ($pong !== true && $pong !== "+PONG" && $pong !== "PONG") {
          exit(5);
      }
    ' >/dev/null 2>&1
    ;;
  1)
    [ ! -e /var/www/html/wp-content/object-cache.php ] &&
      [ ! -L /var/www/html/wp-content/object-cache.php ]
    ;;
  *)
    exit 1
    ;;
esac
