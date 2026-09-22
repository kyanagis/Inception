#!/bin/sh
set -eu

project_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$project_dir"
compose='docker --host unix:///var/run/docker.sock compose --env-file srcs/.env -f srcs/docker-compose.yml --profile bonus'
fail() { printf 'Bonus test: %s\n' "$*" >&2; exit 1; }

DOMAIN_NAME=$(sed -n 's/^DOMAIN_NAME=//p' srcs/.env)
FTP_PORT=$(sed -n 's/^FTP_PORT=//p' srcs/.env)
[ -n "$DOMAIN_NAME" ] && [ -n "$FTP_PORT" ] || fail 'Missing DOMAIN_NAME or FTP_PORT'

expected=$(printf '%s\n' adminer backup ftp mariadb nginx redis static-site wordpress | sort)
running=$($compose ps --status running --services | sort)
[ "$running" = "$expected" ] || {
  printf 'Expected bonus service set:\n%s\nActual:\n%s\n' "$expected" "$running" >&2
  exit 1
}

for service in mariadb wordpress nginx redis static-site adminer; do
  container_id=$($compose ps --quiet "$service")
  [ -n "$container_id" ] || fail "$service container missing"
  health=$(docker inspect --format '{{.State.Health.Status}}' "$container_id")
  [ "$health" = healthy ] || fail "$service is not healthy: $health"
done

for service in ftp backup; do
  container_id=$($compose ps --quiet "$service")
  [ -n "$container_id" ] || fail "$service container missing"
  [ "$(docker inspect --format '{{.State.Status}}' "$container_id")" = running ] || fail "$service is not running"
done

# Bonus exposure contract: Adminer/static site are loopback-only, Redis stays
# private, while FTPS is intentionally published.
adminer_port=$(docker port "$($compose ps --quiet adminer)" 8080/tcp)
static_port=$(docker port "$($compose ps --quiet static-site)" 8080/tcp)
printf '%s\n' "$adminer_port" | grep -Fx '127.0.0.1:8080' >/dev/null || fail 'Adminer must bind only to 127.0.0.1:8080'
printf '%s\n' "$static_port" | grep -Fx '127.0.0.1:8081' >/dev/null || fail 'Static site must bind only to 127.0.0.1:8081'
[ -z "$(docker port "$($compose ps --quiet redis)")" ] || fail 'Redis must not publish a host port'

curl --fail --silent --show-error http://127.0.0.1:8080/ >/dev/null
curl --fail --silent --show-error http://127.0.0.1:8081/ >/dev/null
$compose exec -T redis /usr/local/bin/redis-healthcheck
$compose exec -T wordpress sh -ec '
  plugin=/var/www/html/wp-content/plugins/redis-cache
  test "$(stat -c %U:%G "$plugin")" = root:www-data
  runuser -u www-data -- test -r "$plugin/redis-cache.php"
  runuser -u www-data -- test -x "$plugin"
'
$compose exec -T --user www-data wordpress wp plugin is-active redis-cache --path=/var/www/html >/dev/null ||
  fail 'Redis Cache plugin is not active after bonus convergence'
$compose exec -T wordpress test -f /var/www/html/wp-content/object-cache.php ||
  fail 'Redis object-cache drop-in is missing after bonus convergence'
cache_probe="inception_smoke_$(date +%s)_$"
$compose exec -T --user www-data wordpress wp eval "
  global \$wp_object_cache;
  if (!method_exists(\$wp_object_cache, 'redis_status') || !\$wp_object_cache->redis_status()) {
      fwrite(STDERR, 'redis_status=false\\n');
      exit(11);
  }
  if (!wp_cache_set('$cache_probe', 'ok', 'inception-smoke', 30)) {
      fwrite(STDERR, 'wp_cache_set failed\\n');
      exit(12);
  }
  if (wp_cache_get('$cache_probe', 'inception-smoke') !== 'ok') {
      fwrite(STDERR, 'wp_cache_get mismatch\\n');
      exit(13);
  }
  wp_cache_delete('$cache_probe', 'inception-smoke');
" --path=/var/www/html >/dev/null ||
  fail 'WordPress Redis object-cache functional probe failed'

# Prove explicit FTPS negotiates TLS with the generated certificate.
timeout 15 openssl s_client -starttls ftp   -connect "127.0.0.1:$FTP_PORT"   -servername "$DOMAIN_NAME"   -verify_hostname "$DOMAIN_NAME"   -verify_return_error   -CAfile secrets/ftps_certificate.pem </dev/null >/dev/null 2>&1 ||
  fail 'FTPS TLS negotiation failed'

# Create a real backup and verify its newest committed directory.
$compose exec -T backup /usr/local/bin/backup-now
latest=$($compose exec -T backup sh -ec "ls -1 /backups | grep -E '^[0-9]{8}T[0-9]{6}Z-' | sort | tail -n 1")
[ -n "$latest" ] || fail 'No committed backup directory found'
$compose exec -T backup /usr/local/bin/backup-manifest verify "/backups/$latest"

printf 'Bonus stack smoke test passed at https://%s\n' "$DOMAIN_NAME"
