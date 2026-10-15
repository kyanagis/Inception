#!/bin/sh
set -eu

project_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$project_dir"
compose='docker --host unix:///var/run/docker.sock compose --env-file srcs/.env -f srcs/docker-compose.yml --profile bonus'
docker_cmd='docker --host unix:///var/run/docker.sock'
fail() { printf 'Restore test: %s\n' "$*" >&2; exit 1; }

DOMAIN_NAME=$(sed -n 's/^DOMAIN_NAME=//p' srcs/.env)
[ -n "$DOMAIN_NAME" ] || fail 'Missing DOMAIN_NAME'

latest=$($compose exec -T backup sh -ec "ls -1 /backups | grep -E '^[0-9]{8}T[0-9]{6}Z-' | sort | tail -n 1")
[ -n "$latest" ] || fail 'No committed backup directory found'
$compose exec -T backup /usr/local/bin/backup-manifest verify "/backups/$latest"

# A manifest/hash check proves archive integrity, not recoverability.  Restore
# into a disposable MariaDB instance with no network at all so this drill cannot
# accidentally depend on, mutate, or authenticate to the production database.
restore_container="inception-restore-probe-$$"
restore_db="inception_restore_probe"
cleanup() {
  $docker_cmd rm -f "$restore_container" >/dev/null 2>&1 || true
}
trap cleanup EXIT HUP INT TERM

$docker_cmd run --detach --name "$restore_container" \
  --network none \
  --read-only \
  --security-opt no-new-privileges:true \
  --cap-drop ALL \
  --cap-add CHOWN \
  --cap-add DAC_OVERRIDE \
  --cap-add SETGID \
  --cap-add SETUID \
  --tmpfs /var/lib/mysql:rw,nosuid,nodev,size=768m \
  --tmpfs /run/mysqld:rw,nosuid,nodev,noexec,size=32m \
  --tmpfs /tmp:rw,nosuid,nodev,noexec,size=128m \
  --entrypoint /bin/sh \
  mariadb:inception -ec '
    install -d -o mysql -g mysql -m 0750 /var/lib/mysql /run/mysqld
    gosu mysql mariadb-install-db \
      --auth-root-authentication-method=normal \
      --datadir=/var/lib/mysql \
      --skip-test-db >/dev/null
    exec gosu mysql mariadbd \
      --console \
      --datadir=/var/lib/mysql \
      --skip-networking \
      --socket=/run/mysqld/mysqld.sock \
      --pid-file=/run/mysqld/mysqld.pid
  ' >/dev/null

ready=0
for _ in $(seq 1 60); do
  if $docker_cmd exec "$restore_container" \
      mariadb --protocol=socket --socket=/run/mysqld/mysqld.sock -uroot \
      --batch --skip-column-names -e 'SELECT 1' >/dev/null 2>&1; then
    ready=1
    break
  fi
  if [ "$($docker_cmd inspect --format '{{.State.Running}}' "$restore_container" 2>/dev/null || true)" != true ]; then
    $docker_cmd logs "$restore_container" >&2 || true
    fail 'Isolated restore database exited during startup'
  fi
  sleep 1
done
[ "$ready" -eq 1 ] || {
  $docker_cmd logs "$restore_container" >&2 || true
  fail 'Isolated restore database did not become ready'
}

$docker_cmd inspect --format '{{.HostConfig.NetworkMode}}' "$restore_container" |
  grep -Fx none >/dev/null || fail 'Restore database is not network-isolated'

$docker_cmd exec "$restore_container" \
  mariadb --protocol=socket --socket=/run/mysqld/mysqld.sock -uroot \
  -e "CREATE DATABASE $restore_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"

$compose exec -T backup sh -ec 'gzip -dc "/backups/$1/database.sql.gz"' sh "$latest" |
  $docker_cmd exec -i "$restore_container" \
    mariadb --protocol=socket --socket=/run/mysqld/mysqld.sock -uroot "$restore_db"

restored_site=$($docker_cmd exec "$restore_container" \
  mariadb --protocol=socket --socket=/run/mysqld/mysqld.sock -uroot \
  -N -B "$restore_db" \
  -e "SELECT option_value FROM wp_options WHERE option_name = 0x7369746575726c LIMIT 1")
[ "$restored_site" = "https://$DOMAIN_NAME" ] ||
  fail "Restored database siteurl mismatch: $restored_site"

$docker_cmd exec "$restore_container" \
  mariadb --protocol=socket --socket=/run/mysqld/mysqld.sock -uroot \
  -N -B "$restore_db" \
  -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 0x77705f6f7074696f6e73" |
  grep -Fx 1 >/dev/null || fail 'Restored database is missing wp_options'

# Restore the filesystem independently into a fresh tmpfs directory.  The
# backup container intentionally lacks CAP_CHOWN, so do not apply archived
# ownership metadata while proving file recoverability.
$compose exec -T backup sh -ec '
  set -eu
  restore=$(mktemp -d /tmp/inception-restore.XXXXXXXX)
  trap "rm -rf \"$restore\"" EXIT HUP INT TERM
  tar --extract --gzip --no-same-owner \
    --file="/backups/$1/wordpress.tar.gz" --directory="$restore"
  test -f "$restore/wp-settings.php"
  test -f "$restore/wp-includes/version.php"
  test -d "$restore/wp-content"
' sh "$latest" || fail 'WordPress file restore drill failed'

cleanup
trap - EXIT HUP INT TERM
printf 'Backup restore drill passed in isolated environment: %s\n' "$latest"
