#!/bin/sh
set -eu

project_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"

./scripts/setup.sh >/dev/null
docker compose --env-file srcs/.env -f srcs/docker-compose.yml config --quiet

for image in mariadb wordpress nginx redis ftp static-site adminer backup; do
  count=$(find "srcs/requirements" -type f -name Dockerfile -path "*/$image/*" | wc -l)
  if [ "$count" -ne 1 ]; then
    echo "Expected exactly one Dockerfile for $image" >&2
    exit 1
  fi
done

if rg -n --glob 'Dockerfile' --glob 'docker-compose.yml' \
  'latest|tail[[:space:]]+-f|sleep[[:space:]]+infinity|while[[:space:]]+true|network_mode:[[:space:]]*host|links:' srcs; then
  echo "A prohibited pattern was found" >&2
  exit 1
fi

if rg -n '^[[:space:]]*image:[[:space:]]*[A-Za-z0-9_.-]+[[:space:]]*$' srcs/docker-compose.yml; then
  echo "Every image must have an explicit non-latest tag" >&2
  exit 1
fi

if rg -n '(PASSWORD|PASSWD|SECRET)[[:space:]]*=' srcs/requirements --glob 'Dockerfile'; then
  echo "A credential-like assignment was found in a Dockerfile" >&2
  exit 1
fi

if rg -n '^FROM[[:space:]]+' srcs/requirements --glob 'Dockerfile' \
    | rg -v ':FROM[[:space:]]+(debian|alpine):[0-9]'; then
  echo "Every service must build directly from an explicitly versioned Debian or Alpine base" >&2
  exit 1
fi

if ! rg -q '^[[:space:]]*ssl_protocols[[:space:]]+TLSv1\.2[[:space:]]+TLSv1\.3;' \
    srcs/requirements/nginx/conf/nginx.conf.template; then
  echo "NGINX must allow exactly TLS 1.2 and TLS 1.3" >&2
  exit 1
fi

restart_count=$(docker compose --env-file srcs/.env -f srcs/docker-compose.yml \
  --profile bonus config | rg -c '^[[:space:]]+restart:[[:space:]]+unless-stopped$')
# Compose preserves the reusable x-security extension in addition to expanding
# it into all eight services.
if [ "$restart_count" -ne 9 ]; then
  echo "Every mandatory and bonus service must restart after a crash" >&2
  exit 1
fi

nginx_config=srcs/requirements/nginx/conf/nginx.conf.template
if ! awk '
  index($0, "uploads|files") && index($0, "deny all") { uploads_deny = NR }
  index($0, "wp-config\\.php") && index($0, "deny all") { sensitive_deny = NR }
  $0 ~ /location ~ \\.php\$/ { php_handler = NR }
  END {
    exit !(uploads_deny && sensitive_deny && php_handler \
      && uploads_deny < php_handler && sensitive_deny < php_handler)
  }
' "$nginx_config"; then
  echo "NGINX deny rules must precede the generic PHP regex location" >&2
  exit 1
fi

tls_verify_count=$(rg -c -- '-verify_return_error' scripts/verify-tls.sh)
if [ "$tls_verify_count" -ne 2 ]; then
  echo "Both TLS protocol checks must fail on certificate verification errors" >&2
  exit 1
fi

if ! rg -q -- '--rmi[[:space:]]+all' Makefile; then
  echo "fclean must remove explicitly tagged Compose images" >&2
  exit 1
fi

echo "Static validation passed. Run 'make up' and './scripts/smoke-test.sh' for integration tests."
