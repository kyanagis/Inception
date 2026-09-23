#!/usr/bin/env bash
set -euo pipefail

pass() { printf '[PASS] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }

printf '%s\n' '=== Inception OVA hypothesis-driven host audit ==='
printf 'host=%s\n' "$(hostname)"
printf 'kernel=%s\n' "$(uname -srmo)"
printf 'nixos=%s\n' "$(nixos-version)"
printf 'user=%s\n' "$(id -un)"

required=(docker jq python3 ip git make curl openssl realpath stat awk grep sed find shellcheck)
for command_name in "${required[@]}"; do
  command -v "$command_name" >/dev/null 2>&1 || fail "H01 missing baseline command: $command_name"
done
pass 'H01 baseline evaluator/tool contract is installed'

docker info >/dev/null
docker compose version
pass 'H02 local Docker daemon and Compose are reachable'

state=/var/lib/inception/environment
if [[ -r "$state" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "$state"
  set +a
  [[ ${INCEPTION_DATA_DIR:-} == "/home/${INCEPTION_LOGIN:-}/data" ]] ||
    fail 'H03 login/data state mismatch'
  docker_root=$(docker info --format '{{.DockerRootDir}}')
  [[ "$docker_root" == "$INCEPTION_DATA_DIR/docker" ]] ||
    fail "H03 DockerRootDir is not the required learner data path: $docker_root"
  pass 'H03 Docker data-root is exactly /home/<login>/data/docker'

  resolved=$(getent ahostsv4 "$DOMAIN_NAME" | awk '{print $1}' | sort -u)
  local_ips=$({ ip -4 -o addr show | awk '{sub(/\/.*/, "", $4); print $4}'; printf '%s\n' 127.0.0.1 127.0.0.2; } | sort -u)
  matched=0
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    if grep -Fx "$candidate" <<<"$local_ips" >/dev/null; then matched=1; break; fi
  done <<<"$resolved"
  ((matched == 1)) || fail "H04 $DOMAIN_NAME does not resolve to this VM"
  pass 'H04 configured 42 domain resolves to a local VM address'
else
  warn 'H03/H04 skipped: run inception-setup YOUR_LOGIN first'
fi

if ss -lnt | awk 'NR>1 {print $4}' | grep -Eq '(^|:)80$'; then
  fail 'H05 unexpected host listener on TCP 80'
fi
pass 'H05 no HTTP listener on host TCP 80'

printf '%s\n' '--- capacity ---'
df -h /
free -h
printf '%s\n' '--- interfaces ---'
ip -brief address

repo=${INCEPTION_REPO_DIR:-/home/inception/Inception-submit}
if [[ -d "$repo/.git" ]]; then
  printf 'submit=%s\n' "$(git -C "$repo" rev-parse HEAD)"
  make -C "$repo" audit
  pass 'H06 repository hypothesis audit completed'
else
  warn "H06 skipped: $repo is not cloned yet"
fi

printf '%s\n' 'OVA host audit completed.'
