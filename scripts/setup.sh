#!/bin/sh
set -eu

project_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
env_file="$project_dir/srcs/.env"

if [ ! -f "$env_file" ]; then
  echo "Missing $env_file" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
. "$env_file"
set +a

domain_name=${DOMAIN_NAME:-}
case "$domain_name" in
  *.42.fr) login=${domain_name%.42.fr} ;;
  *) echo "DOMAIN_NAME must be <login>.42.fr" >&2; exit 2 ;;
esac
case "$login" in
  ''|[!a-z]*|*[!a-z0-9-]*|*-)
    echo "DOMAIN_NAME contains an invalid 42 login" >&2
    exit 2
    ;;
esac
if [ "${#login}" -gt 32 ]; then
  echo "DOMAIN_NAME contains a 42 login longer than 32 characters" >&2
  exit 2
fi
case "$login" in
  root|inception)
    echo "DOMAIN_NAME contains a reserved login" >&2
    exit 2
    ;;
esac

expected_data_path="/home/$login/data"
if [ "${DATA_PATH:-}" != "$expected_data_path" ]; then
  echo "DATA_PATH must be $expected_data_path for DOMAIN_NAME=$domain_name" >&2
  exit 2
fi

if [ ! -d "$(dirname -- "$DATA_PATH")" ]; then
  echo "Creating $DATA_PATH requires its parent home directory to exist" >&2
  exit 2
fi
mkdir -p "$DATA_PATH/wordpress" "$DATA_PATH/mariadb" "$DATA_PATH/backups"
current_uid=$(id -u)
for data_directory in "$DATA_PATH" "$DATA_PATH/wordpress" "$DATA_PATH/mariadb" "$DATA_PATH/backups"; do
  if [ "$(stat -c %u "$data_directory")" = "$current_uid" ]; then
    chmod 0750 "$data_directory"
  fi
done

secrets_dir="$project_dir/secrets"
mkdir -p "$secrets_dir"
chmod 0700 "$secrets_dir"
umask 077

generate_secret() {
  target=$1
  if [ ! -s "$target" ]; then
    openssl rand -hex 32 > "$target"
  fi
}

generate_secret "$secrets_dir/db_password.txt"
generate_secret "$secrets_dir/db_root_password.txt"
generate_secret "$secrets_dir/wp_admin_password.txt"
generate_secret "$secrets_dir/wp_user_password.txt"
generate_secret "$secrets_dir/ftp_password.txt"

if [ ! -s "$secrets_dir/tls_private_key.pem" ] || [ ! -s "$secrets_dir/tls_certificate.pem" ]; then
  openssl req -x509 -newkey ec \
    -pkeyopt ec_paramgen_curve:prime256v1 \
    -sha256 -nodes -days 365 \
    -keyout "$secrets_dir/tls_private_key.pem" \
    -out "$secrets_dir/tls_certificate.pem" \
    -subj "/CN=$DOMAIN_NAME" \
    -addext "subjectAltName=DNS:$DOMAIN_NAME,DNS:localhost,IP:127.0.0.1" \
    -addext "keyUsage=critical,digitalSignature,keyAgreement" \
    -addext "extendedKeyUsage=serverAuth" >/dev/null 2>&1
fi
chmod 0600 "$secrets_dir"/*.txt "$secrets_dir/tls_private_key.pem"
chmod 0644 "$secrets_dir/tls_certificate.pem"

printf 'Setup complete for https://%s\n' "$DOMAIN_NAME"
