#!/bin/sh
set -eu

if [ "${1:-}" != "nginx" ]; then
  exec "$@"
fi

: "${DOMAIN_NAME:?DOMAIN_NAME is required}"
case "$DOMAIN_NAME" in
  ''|*[!a-z0-9.-]*) echo "DOMAIN_NAME contains unsupported characters" >&2; exit 2 ;;
esac
[ -r /run/secrets/tls_certificate ] || { echo "TLS certificate is missing" >&2; exit 1; }
[ -r /run/secrets/tls_private_key ] || { echo "TLS private key is missing" >&2; exit 1; }

sed "s/__DOMAIN_NAME__/${DOMAIN_NAME}/g" \
  /etc/nginx/nginx.conf.template > /tmp/nginx.conf
nginx -t -c /tmp/nginx.conf
exec nginx -c /tmp/nginx.conf -g 'daemon off;'
