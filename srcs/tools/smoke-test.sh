#!/bin/sh
set -eu

project_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$project_dir"
DOMAIN_NAME=$(docker compose --env-file srcs/.env -f srcs/docker-compose.yml config --format json | jq -er '.services.nginx.environment.DOMAIN_NAME')

compose='docker compose --env-file srcs/.env -f srcs/docker-compose.yml'

running=$($compose ps --status running --services | sort)
[ "$running" = "$(printf '%s\n' mariadb nginx wordpress | sort)" ] || {
  printf 'Unexpected mandatory service set:\n%s\n' "$running" >&2
  exit 1
}

for service in mariadb wordpress nginx; do
  container_id=$($compose ps --quiet "$service")
  [ -n "$container_id" ]
  health=$(docker inspect --format '{{.State.Health.Status}}' "$container_id")
  [ "$health" = healthy ] || {
    echo "$service is not healthy: $health" >&2
    exit 1
  }
done

[ -z "$(docker port "$($compose ps --quiet mariadb)")" ]
[ -z "$(docker port "$($compose ps --quiet wordpress)")" ]
docker port "$($compose ps --quiet nginx)" 443/tcp | grep -Eq '(^|:)443$'
published=$(docker ps --filter label=com.docker.compose.project=inception --format '{{.Names}} {{.Ports}}')
printf '%s\n' "$published" | awk '
  /inception-nginx-/ {if ($0 !~ /:443->443\/tcp/) exit 1; next}
  /->/ {exit 1}
' || { printf 'Unexpected published port:\n%s\n' "$published" >&2; exit 1; }

curl --fail --silent --show-error --cacert secrets/tls_certificate.pem \
  --resolve "$DOMAIN_NAME:443:127.0.0.1" "https://$DOMAIN_NAME/" >/dev/null
[ "$(curl --silent --insecure --output /dev/null --write-out '%{http_code}' \
  --resolve invalid.example:443:127.0.0.1 https://invalid.example/)" = 421 ]
[ "$(curl --silent --cacert secrets/tls_certificate.pem --output /dev/null --write-out '%{http_code}' \
  --resolve "$DOMAIN_NAME:443:127.0.0.1" "https://$DOMAIN_NAME/xmlrpc.php")" = 403 ]

./srcs/tools/verify-tls.sh

if curl --silent --max-time 2 http://127.0.0.1:80 >/dev/null 2>&1; then
  echo "Port 80 unexpectedly accepts HTTP" >&2
  exit 1
fi

admin_count=$($compose exec -T --user www-data wordpress wp user list --role=administrator --field=user_login --path=/var/www/html | wc -l)
user_count=$($compose exec -T --user www-data wordpress wp user list --field=user_login --path=/var/www/html | wc -l)
[ "$admin_count" -eq 1 ]
[ "$user_count" -ge 2 ]
admin_name=$($compose exec -T --user www-data wordpress wp user list --role=administrator --field=user_login --path=/var/www/html)
case "$admin_name" in *[Aa][Dd][Mm][Ii][Nn]*) echo 'Administrator login contains prohibited admin substring' >&2; exit 1;; esac
# WordPress deliberately has no Internet egress: both of its networks are
# internal. The Docker build already authenticates the upstream WordPress
# archive with a pinned SHA-256, so verify the running immutable core against
# that local, authenticated copy instead of calling api.wordpress.org.
$compose exec -T wordpress diff -qr \
  --exclude=wp-content \
  --exclude=wp-config.php \
  --exclude=.htaccess \
  /usr/src/wordpress /var/www/html >/dev/null
$compose exec -T wordpress sh -ec '
  test "$(stat -c %U:%G /var/www/html/wp-settings.php)" = root:www-data
  test "$(stat -c %a /var/www/html/wp-settings.php)" = 644
  runuser -u www-data -- test ! -w /var/www/html/wp-settings.php
  test "$(stat -c %U:%G /var/www/html/wp-content/uploads)" = www-data:www-data
'
[ "$($compose exec -T --user www-data wordpress wp option get home --path=/var/www/html)" = "https://$DOMAIN_NAME" ]
[ "$($compose exec -T --user www-data wordpress wp option get siteurl --path=/var/www/html)" = "https://$DOMAIN_NAME" ]
$compose exec -T mariadb mariadb-healthcheck

echo "Mandatory stack smoke test passed at https://$DOMAIN_NAME"
