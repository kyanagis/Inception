#!/bin/sh
set -eu

project_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"
set -a
# shellcheck disable=SC1091
. srcs/.env
set +a

certificate=secrets/tls_certificate.pem
[ -r "$certificate" ] || { echo "Run 'make setup' first" >&2; exit 1; }

local_fingerprint=$(openssl x509 -in "$certificate" -noout -fingerprint -sha256)
remote_fingerprint=$(printf '' | openssl s_client \
  -connect 127.0.0.1:443 -servername "$DOMAIN_NAME" -showcerts 2>/dev/null \
  | openssl x509 -noout -fingerprint -sha256)

[ "$local_fingerprint" = "$remote_fingerprint" ] || {
  echo "The certificate served on port 443 does not match the local certificate" >&2
  exit 1
}

printf '' | openssl s_client \
  -connect 127.0.0.1:443 \
  -servername "$DOMAIN_NAME" \
  -verify_hostname "$DOMAIN_NAME" \
  -verify_return_error \
  -CAfile "$certificate" \
  -tls1_2 >/dev/null 2>&1

printf '' | openssl s_client \
  -connect 127.0.0.1:443 \
  -servername "$DOMAIN_NAME" \
  -verify_hostname "$DOMAIN_NAME" \
  -verify_return_error \
  -CAfile "$certificate" \
  -tls1_3 >/dev/null 2>&1

for legacy_protocol in -tls1 -tls1_1; do
  if printf '' | openssl s_client \
      -connect 127.0.0.1:443 \
      -servername "$DOMAIN_NAME" \
      "$legacy_protocol" >/dev/null 2>&1; then
    echo "A legacy TLS protocol was unexpectedly accepted: $legacy_protocol" >&2
    exit 1
  fi
done

printf '%s\nTLS 1.2/1.3 verification and TLS 1.0/1.1 rejection passed for %s\n' \
  "$local_fingerprint" "$DOMAIN_NAME"
