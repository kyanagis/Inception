#!/bin/sh
set -eu

project_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$project_dir"
./srcs/tools/preflight.sh
umask 077
secrets_dir="$project_dir/secrets"
[ ! -L "$secrets_dir" ] || { echo 'Refusing a symlink secrets directory' >&2; exit 1; }
mkdir -p "$secrets_dir"
chmod 0700 "$secrets_dir"
exec 9>"$secrets_dir/.setup.lock"
flock -x 9
config=$(docker compose --env-file srcs/.env -f srcs/docker-compose.yml config --format json)
domain_name=$(printf '%s' "$config" | jq -er '.services.wordpress.environment.DOMAIN_NAME')
case "$domain_name" in
  *.42.fr) login=${domain_name%.42.fr} ;;
  *) echo 'DOMAIN_NAME must be <login>.42.fr' >&2; exit 2 ;;
esac
case "$login" in ''|[!a-z]*|*[!a-z0-9-]*|*-|root|inception) echo 'Invalid login' >&2; exit 2;; esac
[ "${#login}" -le 32 ] || exit 2
established=false
volumes=$(docker --host unix:///var/run/docker.sock volume ls --format '{{.Name}}')
if printf '%s\n' "$volumes" | grep -Fx inception_mariadb_data >/dev/null; then
  established=true
fi
for name in db_password db_root_password db_backup_password wp_admin_password wp_user_password ftp_password redis_password; do
  target="$secrets_dir/$name.txt"
  [ ! -L "$target" ] || { echo "Refusing symlink secret: $name" >&2; exit 1; }
  if [ -e "$target" ]; then
    [ -f "$target" ] && [ "$(wc -c < "$target")" -ge 64 ] && [ "$(wc -c < "$target")" -le 65 ] &&
      LC_ALL=C grep -Eq '^[0-9a-fA-F]{64}$' "$target" || { echo "Invalid existing secret: $name" >&2; exit 1; }
  else
    case "$name" in
      db_backup_password|redis_password) ;;
      *) [ "$established" = false ] || { echo "Missing secret with existing database volume: $name" >&2; exit 1; } ;;
    esac
    temporary=$(mktemp "$secrets_dir/.secret.XXXXXXXX")
    openssl rand -hex 32 > "$temporary"
    mv -T "$temporary" "$target"
  fi
  chmod 0600 "$target"
done

certificate="$secrets_dir/tls_certificate.pem"
private_key="$secrets_dir/tls_private_key.pem"
verify_pair() {
  cert=$1
  key=$2
  [ -s "$cert" ] && [ -s "$key" ] || return 1
  openssl x509 -in "$cert" -noout -checkend 86400 >/dev/null 2>&1 || return 1
  openssl x509 -in "$cert" -noout -ext subjectAltName 2>/dev/null | tr ',' '\n' |
    sed 's/^[[:space:]]*//' | grep -Fx "DNS:$domain_name" >/dev/null || return 1
  openssl verify -CAfile "$cert" -verify_hostname "$domain_name" "$cert" >/dev/null 2>&1 || return 1
  cert_public=$(openssl x509 -in "$cert" -pubkey -noout 2>/dev/null) || return 1
  key_public=$(openssl pkey -in "$key" -pubout 2>/dev/null) || return 1
  [ "$cert_public" = "$key_public" ] || return 1
  printf '%s\n' "$key_public" | openssl pkey -pubin -text -noout 2>/dev/null |
    grep -F 'ASN1 OID:' >/dev/null

}
publish_links() {
  for pair in 'tls_certificate.pem:certificate.pem' 'tls_private_key.pem:private-key.pem'; do
    link=${pair%%:*}
    file=${pair#*:}
    temporary=$(mktemp -d "$secrets_dir/.tls-link.XXXXXXXX")
    ln -s "tls/active/$file" "$temporary/link"
    mv -Tf "$temporary/link" "$secrets_dir/$link"
    rmdir "$temporary"
  done
}
if ! verify_pair "$certificate" "$private_key"; then
  for pair in 'tls_certificate.pem:certificate.pem' 'tls_private_key.pem:private-key.pem'; do
    link=${pair%%:*}
    file=${pair#*:}
    if [ -e "$secrets_dir/$link" ] || [ -L "$secrets_dir/$link" ]; then
      [ "$(readlink "$secrets_dir/$link" || :)" = "tls/active/$file" ] &&
        [ ! -L "$secrets_dir/tls/.managed" ] &&
        [ "$(cat "$secrets_dir/tls/.managed" 2>/dev/null || :)" = inception-tls-v1 ] || {
          echo 'External TLS certificate/key is invalid; refusing replacement' >&2; exit 1;
        }
    fi
  done
  [ -z "$(docker --host unix:///var/run/docker.sock ps -q --filter label=com.docker.compose.project=inception)" ] || {
    echo 'Stop the stack before creating or renewing its certificate' >&2; exit 1;
  }
  [ ! -L "$secrets_dir/tls" ] || { echo 'Refusing symlink TLS directory' >&2; exit 1; }
  mkdir -p "$secrets_dir/tls"
  active=$(readlink "$secrets_dir/tls/active" || :)
  case "$active" in
    generation.????????)
      case "$active" in *[!a-zA-Z0-9.]* ) active=invalid;; esac ;;
    *) active=invalid ;;
  esac
  if [ "$active" != invalid ] && [ ! -L "$secrets_dir/tls/$active" ] &&
      [ "$(cat "$secrets_dir/tls/.managed" 2>/dev/null || :)" = inception-tls-v1 ] &&
      verify_pair "$secrets_dir/tls/$active/certificate.pem" "$secrets_dir/tls/$active/private-key.pem"; then
    publish_links
  else
  generation=$(mktemp -d "$secrets_dir/tls/generation.XXXXXXXX")
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -sha256 -nodes -days 365 -keyout "$generation/private-key.pem" \
    -out "$generation/certificate.pem" -subj "/CN=$domain_name" \
    -addext "subjectAltName=DNS:$domain_name,DNS:localhost,IP:127.0.0.1" \
    -addext 'keyUsage=critical,digitalSignature,keyAgreement' \
    -addext 'extendedKeyUsage=serverAuth' >/dev/null 2>&1
  verify_pair "$generation/certificate.pem" "$generation/private-key.pem" || exit 1
  chmod 0600 "$generation/private-key.pem"
  chmod 0644 "$generation/certificate.pem"
  printf '%s\n' inception-tls-v1 > "$secrets_dir/tls/.managed"
  ln -s "$(basename "$generation")" "$secrets_dir/tls/.active.$$"
  mv -Tf "$secrets_dir/tls/.active.$$" "$secrets_dir/tls/active"
  publish_links
  fi
fi
chmod 0600 "$private_key"

ftps_certificate="$secrets_dir/ftps_certificate.pem"
ftps_private_key="$secrets_dir/ftps_private_key.pem"
if ! verify_pair "$ftps_certificate" "$ftps_private_key"; then
  [ ! -e "$ftps_certificate" ] && [ ! -L "$ftps_certificate" ] &&
    [ ! -e "$ftps_private_key" ] && [ ! -L "$ftps_private_key" ] || {
      echo 'Existing FTPS certificate/key is invalid; refusing replacement' >&2; exit 1;
    }
  temporary_ftps=$(mktemp -d "$secrets_dir/.ftps.XXXXXXXX")
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -sha256 -nodes -days 365 -keyout "$temporary_ftps/private-key.pem" \
    -out "$temporary_ftps/certificate.pem" -subj "/CN=$domain_name" \
    -addext "subjectAltName=DNS:$domain_name,DNS:localhost,IP:127.0.0.1" \
    -addext 'keyUsage=critical,digitalSignature,keyAgreement' \
    -addext 'extendedKeyUsage=serverAuth' >/dev/null 2>&1
  verify_pair "$temporary_ftps/certificate.pem" "$temporary_ftps/private-key.pem" || exit 1
  mv -T "$temporary_ftps/certificate.pem" "$ftps_certificate"
  mv -T "$temporary_ftps/private-key.pem" "$ftps_private_key"
  rmdir "$temporary_ftps"
fi
chmod 0644 "$ftps_certificate"
chmod 0600 "$ftps_private_key"
printf 'Setup complete for https://%s\n' "$domain_name"
