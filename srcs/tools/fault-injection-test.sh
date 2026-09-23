#!/bin/sh
set -eu

project_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$project_dir"
compose='docker --host unix:///var/run/docker.sock compose --env-file srcs/.env -f srcs/docker-compose.yml'
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

# Abrupt process death must converge through the normal restart policy.
for service in wordpress mariadb; do
  id=$($compose ps --quiet "$service")
  [ -n "$id" ] || fail "$service container missing before crash injection"
  docker exec "$id" sh -ec 'kill -KILL 1' >/dev/null 2>&1 || true
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

$compose up --detach --no-build --remove-orphans --wait --wait-timeout 180 mariadb wordpress nginx >/dev/null
./srcs/tools/smoke-test.sh
$compose exec -T wordpress test -f /var/www/.inception-state/complete
$compose exec -T wordpress test ! -e /var/www/.inception-wordpress || fail 'stale WordPress staging directory survived recovery'

printf '%s\n' 'Crash and partial-state recovery tests passed.'
