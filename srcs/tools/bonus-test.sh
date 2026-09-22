#!/bin/sh
set -eu

project_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$project_dir"
compose='docker --host unix:///var/run/docker.sock compose --env-file srcs/.env -f srcs/docker-compose.yml --profile bonus'
fail() { printf 'Bonus test: %s\n' "$*" >&2; exit 1; }

config=$($compose config --format json)
domain=$(printf '%s' "$config" | jq -er '.services.wordpress.environment.DOMAIN_NAME')
ftp_user=$(printf '%s' "$config" | jq -er '.services.ftp.environment.FTP_USER')
ftp_port=$(printf '%s' "$config" | jq -er '.services.ftp.ports[0].published')

expected=$(printf '%s\n' adminer backup ftp mariadb nginx redis static-site wordpress | sort)
running=$($compose ps --status running --services | sort)
[ "$running" = "$expected" ] || {
  printf 'Expected bonus services:\n%s\nActual:\n%s\n' "$expected" "$running" >&2
  exit 1
}

for service in mariadb wordpress nginx redis static-site adminer; do
  id=$($compose ps --quiet "$service")
  [ -n "$id" ] || fail "$service has no container"
  health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$id")
  [ "$health" = healthy ] || fail "$service health=$health"
done

for service in ftp backup; do
  id=$($compose ps --quiet "$service")
  [ -n "$id" ] || fail "$service has no container"
  [ "$(docker inspect --format '{{.State.Status}}' "$id")" = running ] || fail "$service is not running"
done

# Redis must require the scoped wordpress ACL and WordPress must actually use it.
$compose exec -T redis /usr/local/bin/redis-healthcheck
$compose exec -T --user www-data wordpress wp redis status --path=/var/www/html >/dev/null

# Loopback-only services must be reachable locally but not wildcard-published.
curl --fail --silent --show-error http://127.0.0.1:8080/ >/dev/null
curl --fail --silent --show-error http://127.0.0.1:8081/ >/dev/null
published=$(docker ps --filter label=com.docker.compose.project=inception --format '{{.Names}} {{.Ports}}')
printf '%s\n' "$published" | awk '
  /inception-adminer-/ && /0\.0\.0\.0:8080|\[::\]:8080/ {exit 1}
  /inception-static-site-/ && /0\.0\.0\.0:8081|\[::\]:8081/ {exit 1}
' || fail 'Loopback-only bonus service exposed on a wildcard address'

# Explicit FTPS control channel: certificate and hostname must verify.
timeout 15 openssl s_client -quiet -connect "127.0.0.1:$ftp_port" -starttls ftp   -servername "$domain" -CAfile secrets/ftps_certificate.pem   -verify_hostname "$domain" -verify_return_error </dev/null >/dev/null 2>&1 ||
  fail 'FTPS TLS verification failed'

# Authenticate without printing the password and prove the user can list its jail.
ftp_password=$(tr -d '\r\n' < secrets/ftp_password.txt)
curl --fail --silent --show-error --ssl-reqd   --cacert secrets/ftps_certificate.pem   --user "$ftp_user:$ftp_password"   "ftp://$domain:$ftp_port/" >/dev/null
unset ftp_password

# Backup path must produce a verifiable backup from the running database/files.
$compose exec -T backup /usr/local/bin/backup-now
latest=$($compose exec -T backup /usr/local/bin/backup-manifest list /backups | tail -n 1)
[ -n "$latest" ] || fail 'No backup was listed after backup-now'
$compose exec -T backup /usr/local/bin/backup-manifest verify "/backups/$latest"

printf 'Bonus stack integration test passed at %s\n' "$domain"
