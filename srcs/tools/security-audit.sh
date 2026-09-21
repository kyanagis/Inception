#!/bin/sh
set -eu

project_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$project_dir"
fail() { printf 'Audit: %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }

./srcs/tools/check.sh
pass 'H01 repository/static policy checks'

config=$(docker compose --env-file srcs/.env -f srcs/docker-compose.yml --profile bonus config --format json)

printf '%s' "$config" | jq -e '
  all(.services[];
    (.privileged != true) and
    (.network_mode == null) and
    (.pid == null) and
    (.ipc == null) and
    (.read_only == true) and
    ((.security_opt // []) | index("no-new-privileges:true") != null)
  )
' >/dev/null || fail 'H02 a service can escape the intended container boundary'
pass 'H02 no privileged/host namespace service; root filesystems are read-only'

printf '%s' "$config" | jq -e '
  (.services.mariadb.ports == null) and
  (.services.wordpress.ports == null) and
  (.services.redis.ports == null)
' >/dev/null || fail 'H03 backend service is host-published'
pass 'H03 database, WordPress and Redis have no host-published ports'

if git ls-files secrets | grep -v '^secrets/.gitkeep$' | grep -q .; then
  fail 'H04 tracked secret exists'
fi
if git ls-files | grep -E '\.(pem|key|crt)$' | grep -q .; then
  fail 'H04 tracked certificate/private-key material exists'
fi
pass 'H04 no credential/private-key material is tracked'

if printf '%s' "$config" | jq -r '.services[]?.environment // {} | to_entries[]? | "\(.key)=\(.value)"' |
  grep -Ei '(password|passwd|secret|private[_-]?key)=' >/dev/null; then
  fail 'H05 credential-like environment variable is present'
fi
pass 'H05 credentials are not passed as environment values'

# Runtime evidence is collected when the project is already running.  This
# keeps audit useful before build while turning it into a stronger verifier
# after make up / make bonus.
ids=$(docker --host unix:///var/run/docker.sock ps -q --filter label=com.docker.compose.project=inception 2>/dev/null || true)
if [ -n "$ids" ]; then
  for id in $ids; do
    name=$(docker inspect --format '{{.Name}}' "$id")
    [ "$(docker inspect --format '{{.HostConfig.Privileged}}' "$id")" = false ] || fail "H06 $name is privileged"
    [ "$(docker inspect --format '{{.HostConfig.ReadonlyRootfs}}' "$id")" = true ] || fail "H06 $name rootfs is writable"
    docker inspect --format '{{json .HostConfig.SecurityOpt}}' "$id" | grep -F 'no-new-privileges' >/dev/null ||
      fail "H06 $name lacks no-new-privileges"
  done
  pass 'H06 runtime container security options match the declared boundary'

  published=$(docker --host unix:///var/run/docker.sock ps     --filter label=com.docker.compose.project=inception --format '{{.Names}} {{.Ports}}')
  printf '%s\n' "$published" | grep -E '3306->|9000->|6379->' >/dev/null &&
    fail 'H07 backend port unexpectedly published'
  pass 'H07 runtime backend ports remain private'
else
  printf '[SKIP] H06/H07 no Inception containers are running\n'
fi

printf '%s\n' 'Hypothesis-driven security audit completed.'
