#!/bin/sh
set -eu

project_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$project_dir"
compose='docker --host unix:///var/run/docker.sock compose --env-file srcs/.env -f srcs/docker-compose.yml'
bonus_compose='docker --host unix:///var/run/docker.sock compose --env-file srcs/.env -f srcs/docker-compose.yml --profile bonus'
fail() { printf 'Fault injection: %s\n' "$*" >&2; exit 1; }

wait_healthy() {
  service=$1
  attempts=0
  while [ "$attempts" -lt 60 ]; do
    id=$($compose ps --quiet "$service" 2>/dev/null || true)
    if [ -n "$id" ]; then
      status=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$id" 2>/dev/null || true)
      [ "$status" = healthy ] && return 0
    fi
    attempts=$((attempts + 1))
    sleep 2
  done
  fail "$service did not recover to healthy state"
}

# Converge to the mandatory topology first so the final smoke test has a
# deterministic service set even when the caller previously exercised bonus.
WP_REDIS_DISABLED=1 $compose up --detach --no-build --remove-orphans --wait --wait-timeout 180 mariadb wordpress nginx >/dev/null
$bonus_compose stop redis ftp static-site adminer backup >/dev/null 2>&1 || true

# Abrupt application-process death must actually restart the container and
# converge through the normal restart policy.  Assert RestartCount so a signal
# that was ignored by namespace PID 1 cannot produce a false positive.
for service in wordpress mariadb; do
  id=$($compose ps --quiet "$service")
  [ -n "$id" ] || fail "$service container missing before crash injection"
  before=$(docker inspect --format '{{.RestartCount}}' "$id")
  case "$service" in
    wordpress)
      docker exec "$id" sh -ec 'pid=$(cat /run/php/php-fpm.pid); kill -KILL "$pid"'
      ;;
    mariadb)
      docker exec "$id" sh -ec 'pid=$(cat /run/mysqld/mysqld.pid); kill -KILL "$pid"'
      ;;
  esac
  attempts=0
  while [ "$attempts" -lt 60 ]; do
    after=$(docker inspect --format '{{.RestartCount}}' "$id" 2>/dev/null || printf 0)
    if [ "$after" -gt "$before" ]; then
      break
    fi
    attempts=$((attempts + 1))
    sleep 1
  done
  [ "$after" -gt "$before" ] || fail "$service crash did not increment RestartCount"
  wait_healthy "$service"
done

# Simulate a crash after WordPress metadata publication but before the HTML
# tree commit. The disposable CI deployment must reconstruct the tree from the
# authenticated image while preserving database identity.
$compose stop nginx wordpress >/dev/null
$compose run --rm --no-deps --entrypoint sh wordpress -ec '
  set -eu
  test -d /var/www/.inception-state
  rm -rf /var/www/html /var/www/.inception-wordpress
  mkdir /var/www/.inception-wordpress
  printf partial > /var/www/.inception-wordpress/crash-marker
  rm -f /var/www/.inception-state/complete
' >/dev/null

WP_REDIS_DISABLED=1 $compose up --detach --no-build --remove-orphans --wait --wait-timeout 180 mariadb wordpress nginx >/dev/null
./srcs/tools/smoke-test.sh
$compose exec -T wordpress test -f /var/www/.inception-state/complete
$compose exec -T wordpress test ! -e /var/www/.inception-wordpress || fail 'stale WordPress staging directory survived recovery'

# Exercise MariaDB's bootstrap state machine on a disposable volume.  This
# represents a crash after metadata publication but before database bootstrap
# completion, without risking the real project database.
MYSQL_DATABASE=$(sed -n 's/^MYSQL_DATABASE=//p' srcs/.env)
MYSQL_USER=$(sed -n 's/^MYSQL_USER=//p' srcs/.env)
MYSQL_BACKUP_USER=$(sed -n 's/^MYSQL_BACKUP_USER=//p' srcs/.env)
[ -n "$MYSQL_DATABASE" ] && [ -n "$MYSQL_USER" ] && [ -n "$MYSQL_BACKUP_USER" ] ||
  fail 'database identifiers missing for isolated bootstrap fault test'

fault_volume="inception-fault-mariadb-$"
fault_container="inception-fault-mariadb-$"
docker volume create "$fault_volume" >/dev/null
cleanup_fault_db() {
  docker rm -f "$fault_container" >/dev/null 2>&1 || true
  docker volume rm -f "$fault_volume" >/dev/null 2>&1 || true
}
trap cleanup_fault_db EXIT HUP INT TERM

docker run --rm \
  --volume "$fault_volume:/var/lib/mysql" \
  --entrypoint /bin/sh \
  mariadb:inception -ec '
    mkdir -p /var/lib/mysql/.inception-bootstrap
    printf "%s\n" inception-bootstrap-v1 > /var/lib/mysql/.inception-bootstrap/.inception-owned
    printf "%s\n%s\n%s\n" "$MYSQL_DATABASE" "$MYSQL_USER" "$MYSQL_BACKUP_USER" \
      > /var/lib/mysql/.inception-bootstrap/.inception-identity
  ' \
  --env "MYSQL_DATABASE=$MYSQL_DATABASE" \
  --env "MYSQL_USER=$MYSQL_USER" \
  --env "MYSQL_BACKUP_USER=$MYSQL_BACKUP_USER" >/dev/null 2>&1 ||
  fail 'unable to construct partial MariaDB bootstrap state'

docker run --detach --name "$fault_container" \
  --network none \
  --read-only \
  --security-opt no-new-privileges:true \
  --cap-drop ALL \
  --cap-add CHOWN --cap-add DAC_OVERRIDE --cap-add KILL --cap-add SETGID --cap-add SETUID \
  --tmpfs /run/mysqld:rw,nosuid,nodev,noexec,size=16m \
  --tmpfs /tmp:rw,nosuid,nodev,noexec,size=128m \
  --volume "$fault_volume:/var/lib/mysql" \
  --mount "type=bind,src=$project_dir/secrets/db_password.txt,dst=/run/secrets/db_password,readonly" \
  --mount "type=bind,src=$project_dir/secrets/db_root_password.txt,dst=/run/secrets/db_root_password,readonly" \
  --mount "type=bind,src=$project_dir/secrets/db_backup_password.txt,dst=/run/secrets/db_backup_password,readonly" \
  --env "MYSQL_DATABASE=$MYSQL_DATABASE" \
  --env "MYSQL_USER=$MYSQL_USER" \
  --env "MYSQL_BACKUP_USER=$MYSQL_BACKUP_USER" \
  mariadb:inception >/dev/null

fault_ready=0
for _ in $(seq 1 90); do
  if docker exec "$fault_container" /usr/local/bin/mariadb-healthcheck >/dev/null 2>&1; then
    fault_ready=1
    break
  fi
  [ "$(docker inspect --format '{{.State.Running}}' "$fault_container" 2>/dev/null || true)" = true ] || {
    docker logs "$fault_container" >&2 || true
    fail 'isolated MariaDB bootstrap recovery container exited'
  }
  sleep 1
done
[ "$fault_ready" -eq 1 ] || {
  docker logs "$fault_container" >&2 || true
  fail 'isolated MariaDB bootstrap recovery timed out'
}
docker exec "$fault_container" test -f /var/lib/mysql/data/.inception-complete ||
  fail 'MariaDB recovery did not publish completion marker'
docker exec "$fault_container" test ! -e /var/lib/mysql/.inception-bootstrap ||
  fail 'MariaDB recovery left stale bootstrap staging state'

cleanup_fault_db
trap - EXIT HUP INT TERM

printf '%s\n' 'Crash and partial-state recovery tests passed.'
