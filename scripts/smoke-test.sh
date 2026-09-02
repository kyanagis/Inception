#!/bin/sh
set -eu

project_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"
set -a
# shellcheck disable=SC1091
. srcs/.env
set +a

compose='docker compose --env-file srcs/.env -f srcs/docker-compose.yml'

$compose ps --status running --services | grep -Fx mariadb >/dev/null
$compose ps --status running --services | grep -Fx wordpress >/dev/null
$compose ps --status running --services | grep -Fx nginx >/dev/null

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

curl --fail --silent --show-error --insecure \
  --resolve "$DOMAIN_NAME:443:127.0.0.1" "https://$DOMAIN_NAME/" >/dev/null

protocol=$(printf '' | openssl s_client -connect 127.0.0.1:443 -servername "$DOMAIN_NAME" 2>/dev/null \
  | sed -n -e 's/^Protocol: //p' -e 's/^ *Protocol  *: //p' | head -n 1)
case "$protocol" in
  TLSv1.2|TLSv1.3) ;;
  *) echo "Unexpected TLS protocol: ${protocol:-unknown}" >&2; exit 1 ;;
esac

if curl --silent --max-time 2 http://127.0.0.1:80 >/dev/null 2>&1; then
  echo "Port 80 unexpectedly accepts HTTP" >&2
  exit 1
fi

admin_count=$($compose exec -T --user www-data wordpress wp user list --role=administrator --field=user_login --path=/var/www/html | wc -l)
user_count=$($compose exec -T --user www-data wordpress wp user list --field=user_login --path=/var/www/html | wc -l)
[ "$admin_count" -eq 1 ]
[ "$user_count" -ge 2 ]

echo "Mandatory stack smoke test passed at https://$DOMAIN_NAME"
