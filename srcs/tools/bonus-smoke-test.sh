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

# Exercise the Redis ACL as an attacker would.  The application account must
# work for the object-cache commands it needs, but administrative commands and
# script-based attempts to reach them must fail at runtime.
$compose exec -T redis sh -ec '
  set -eu
  password=$(tr -d "\r\n" < /run/secrets/redis_password)

  unauth=$(redis-cli --raw PING 2>&1 || true)
  printf "%s\n" "$unauth" | grep -Eq "NOAUTH|Authentication required" || {
    echo "Redis unexpectedly accepted an unauthenticated command" >&2
    exit 1
  }

  expect_noperm() {
    output=$(REDISCLI_AUTH="$password" redis-cli --user wordpress --raw "$@" 2>&1 || true)
    printf "%s\n" "$output" | grep -F NOPERM >/dev/null || {
      printf "Redis ACL unexpectedly allowed:" >&2
      printf " %s" "$@" >&2
      printf "\nresponse: %s\n" "$output" >&2
      exit 1
    }
  }

  expect_noperm CONFIG GET dir
  expect_noperm ACL WHOAMI
  expect_noperm MODULE LIST

  scripted=$(REDISCLI_AUTH="$password" redis-cli --user wordpress --raw \
    EVAL "return redis.call(\"CONFIG\",\"GET\",\"dir\")" 0 2>&1 || true)
  printf "%s\n" "$scripted" | grep -Eiq "NOPERM|permission|not allowed|ACL|can.t run" || {
    printf "Redis EVAL unexpectedly bypassed the ACL command boundary: %s\n" "$scripted" >&2
    exit 1
  }
'
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

# Prove the FTPS authorization boundary with authenticated operations, not
# only with configuration inspection or a TLS handshake.
DOMAIN_NAME="$DOMAIN_NAME" FTP_PORT="$FTP_PORT" FTP_USER="$(sed -n 's/^FTP_USER=//p' srcs/.env)" python3 - <<'PY'
import ftplib
import io
import os
import ssl
import time
import urllib.error
import urllib.request

domain = os.environ["DOMAIN_NAME"]
port = int(os.environ["FTP_PORT"])
user = os.environ["FTP_USER"]
password = open("secrets/ftp_password.txt", "r", encoding="ascii").read().strip()
cafile = "secrets/ftps_certificate.pem"
ctx = ssl.create_default_context(cafile=cafile)
probe = f"inception-ftps-{os.getpid()}-{int(time.time())}"
payload = b"inception-ftps-write-boundary\n"

def connect():
    ftp = ftplib.FTP_TLS(context=ctx, timeout=10)
    ftp.connect(domain, port)
    ftp.login(user, password)
    ftp.prot_p()
    return ftp

def expect_denied(path):
    ftp = connect()
    try:
        try:
            ftp.storbinary(f"STOR {path}", io.BytesIO(payload))
        except ftplib.error_perm:
            return
        try:
            ftp.delete(path)
        except ftplib.all_errors:
            pass
        raise SystemExit(f"FTPS unexpectedly wrote protected path: {path}")
    finally:
        try:
            ftp.quit()
        except ftplib.all_errors:
            ftp.close()

upload = f"wp-content/uploads/{probe}.txt"
ftp = connect()
ftp.storbinary(f"STOR {upload}", io.BytesIO(payload))
buf = io.BytesIO()
ftp.retrbinary(f"RETR {upload}", buf.write)
if buf.getvalue() != payload:
    raise SystemExit("FTPS upload/readback mismatch")
ftp.delete(upload)
ftp.quit()

for protected in (
    f"{probe}.txt",
    f"wp-content/plugins/{probe}.txt",
    f"wp-content/themes/{probe}.txt",
    f"wp-content/uploads/../../{probe}.txt",
):
    expect_denied(protected)

source = f"wp-content/uploads/{probe}-rename.txt"
target = f"wp-content/plugins/{probe}-rename.txt"
ftp = connect()
ftp.storbinary(f"STOR {source}", io.BytesIO(payload))
try:
    try:
        ftp.rename(source, target)
    except ftplib.error_perm:
        pass
    else:
        try:
            ftp.rename(target, source)
        except ftplib.all_errors:
            try:
                ftp.delete(target)
            except ftplib.all_errors:
                pass
        raise SystemExit("FTPS unexpectedly renamed an upload into a protected directory")
finally:
    try:
        ftp.delete(source)
    except ftplib.all_errors:
        pass
    try:
        ftp.quit()
    except ftplib.all_errors:
        ftp.close()

php_name = f"{probe}.php"
php_path = f"wp-content/uploads/{php_name}"
php_marker = f"<?php echo 'EXECUTED-{probe}'; ?>\n".encode()
ftp = connect()
ftp.storbinary(f"STOR {php_path}", io.BytesIO(php_marker))
ftp.quit()

url = f"https://{domain}/wp-content/uploads/{php_name}"
https_ctx = ssl.create_default_context(cafile="secrets/tls_certificate.pem")
try:
    with urllib.request.urlopen(url, context=https_ctx, timeout=10) as response:
        body = response.read()
        status = response.status
except urllib.error.HTTPError as exc:
    body = exc.read()
    status = exc.code
if status != 403:
    raise SystemExit(f"Uploaded PHP was not blocked by NGINX: HTTP {status}")
if f"EXECUTED-{probe}".encode() in body:
    raise SystemExit("Uploaded PHP executed unexpectedly")

ftp = connect()
ftp.delete(php_path)
ftp.quit()
PY

# Create a real backup and verify its newest committed directory.
$compose exec -T backup /usr/local/bin/backup-now
latest=$($compose exec -T backup sh -ec "ls -1 /backups | grep -E '^[0-9]{8}T[0-9]{6}Z-' | sort | tail -n 1")
[ -n "$latest" ] || fail 'No committed backup directory found'
$compose exec -T backup /usr/local/bin/backup-manifest verify "/backups/$latest"

sh ./srcs/tools/backup-restore-test.sh

printf 'Bonus stack smoke test passed at https://%s\n' "$DOMAIN_NAME"
