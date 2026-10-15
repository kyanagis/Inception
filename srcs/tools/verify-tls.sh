#!/bin/sh
set -eu
project_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$project_dir"
domain=$(docker compose --env-file srcs/.env -f srcs/docker-compose.yml config --format json | jq -er '.services.nginx.environment.DOMAIN_NAME')
certificate=secrets/tls_certificate.pem
[ -r "$certificate" ] || { echo "Run make setup first" >&2; exit 1; }
for protocol in -tls1_2 -tls1_3; do
  timeout 15 openssl s_client -connect 127.0.0.1:443 -servername "$domain" \
    -verify_hostname "$domain" -verify_return_error -CAfile "$certificate" \
    "$protocol" </dev/null >/dev/null 2>&1
done
result=$(mktemp)
trap 'rm -f "$result"' EXIT HUP INT TERM
for protocol in -tls1 -tls1_1; do
  if timeout 15 openssl s_client -connect 127.0.0.1:443 -servername "$domain" \
      -cipher 'ALL:@SECLEVEL=0' "$protocol" </dev/null >"$result" 2>&1; then
    echo "Legacy protocol accepted: $protocol" >&2; exit 1
  fi
  grep -Eq 'alert protocol version|alert number 70' "$result" || {
    echo "No server protocol rejection established: $protocol" >&2
    cat "$result" >&2; exit 1
  }
done
printf 'Verified TLS 1.2/1.3 and server rejection of TLS 1.0/1.1 for %s\n' "$domain"
