#!/bin/sh
set -eu

fail() { printf 'Preflight: %s\n' "$*" >&2; exit 1; }
for tool in docker jq realpath stat ip getent awk grep sort; do
  command -v "$tool" >/dev/null 2>&1 || fail "Missing $tool"
done
[ -z "${DOCKER_HOST+x}${DOCKER_CONTEXT+x}" ] || fail 'Unset DOCKER_HOST and DOCKER_CONTEXT; only the local rootful daemon is supported'
[ "$(docker context show)" = default ] || fail 'Select the default Docker context'
project_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
env_file=$project_dir/srcs/.env
[ -f "$env_file" ] && [ ! -L "$env_file" ] || fail 'Expected a regular srcs/.env'
domain=$(sed -n 's/^DOMAIN_NAME=//p' "$env_file")
data_path=$(sed -n 's/^DATA_PATH=//p' "$env_file")
case "$domain" in *.42.fr) login=${domain%.42.fr} ;; *) fail 'DOMAIN_NAME must be LOGIN.42.fr' ;; esac
case "$login" in ''|[!a-z]*|*[!a-z0-9-]*|*-|root|inception) fail 'Invalid 42 login' ;; esac
[ "${#login}" -le 32 ] || fail 'Invalid login length'
[ "$data_path" = "/home/$login/data" ] || fail 'DATA_PATH does not match DOMAIN_NAME'
[ "$(realpath -m -- "$data_path/docker")" = "$data_path/docker" ] || fail 'Docker data path must not contain symlinks'

docker_local() { docker --host unix:///var/run/docker.sock "$@"; }
info=$(docker_local info --format '{{json .}}') || fail 'Cannot access local Docker; run inception-setup in the published OVA, or make host-setup LOGIN=... in a dedicated Debian VM'
printf '%s' "$info" | jq -e '.SecurityOptions | all(.[]; contains("rootless") | not)' >/dev/null || fail 'Rootless Docker is outside the supported host contract'
docker_root=$(printf '%s' "$info" | jq -r .DockerRootDir)
[ "$(realpath -m -- "$docker_root")" = "$data_path/docker" ] || fail "Docker data-root must resolve to $data_path/docker; use inception-setup $login in the OVA or make host-setup LOGIN=$login in a dedicated Debian VM"
engine_version=$(docker_local version --format '{{.Server.Version}}')
compose_version=$(docker_local compose version --short)
[ "$(printf '%s\n' 27.0.3 "$engine_version" | sort -V | head -n 1)" = 27.0.3 ] || fail 'Docker Engine >=27.0.3 is required'
[ "$(printf '%s\n' 2.38.2 "${compose_version#v}" | sort -V | head -n 1)" = 2.38.2 ] || fail 'Docker Compose >=2.38.2 is required'

existing_volumes=$(docker_local volume ls --format '{{.Name}}') || fail 'Docker volume query failed'
for logical in mariadb_data wordpress_data backup_data; do
  name=inception_$logical
  if printf '%s\n' "$existing_volumes" | grep -Fx "$name" >/dev/null; then
    volume=$(docker_local volume inspect "$name") || fail "Cannot inspect existing volume $name"
    printf '%s' "$volume" | jq -e --arg name "$name" --arg logical "$logical" \
      'length == 1 and .[0].Name == $name and .[0].Driver == "local" and ((.[0].Options // {}) == {}) and .[0].Labels["com.docker.compose.project"] == "inception" and .[0].Labels["com.docker.compose.volume"] == $logical' >/dev/null || fail "Volume $name has unexpected ownership, driver, options or labels"
    mountpoint=$(printf '%s' "$volume" | jq -r '.[0].Mountpoint')
    [ "$(realpath -m -- "$mountpoint")" = "$data_path/docker/volumes/$name/_data" ] || fail "Volume $name is outside the configured data path"
  fi
done

# The subject requires <login>.42.fr to resolve to this machine's local IP.
# A classic Debian VM normally uses 127.0.0.1 from /etc/hosts.  The published
# NixOS OVA intentionally uses nss-myhostname, which can resolve the hostname
# to a VirtualBox/NAT address (for example 10.0.2.15) or another loopback
# address.  Validate locality instead of hard-coding one address.
resolved_ipv4=$(getent ahostsv4 "$domain" | awk '{print $1}' | sort -u)
[ -n "$resolved_ipv4" ] || fail "$domain does not resolve to an IPv4 address"
local_ipv4=$(
  {
    ip -4 -o addr show | awk '{sub(/\/.*/, "", $4); print $4}'
    printf '%s\n' 127.0.0.1 127.0.0.2
  } | sort -u
)
local_match=0
for candidate in $resolved_ipv4; do
  if printf '%s\n' "$local_ipv4" | grep -Fx "$candidate" >/dev/null; then
    local_match=1
    break
  fi
done
[ "$local_match" -eq 1 ] || {
  printf 'Resolved IPv4 for %s:\n%s\nLocal IPv4 addresses:\n%s\n' "$domain" "$resolved_ipv4" "$local_ipv4" >&2
  fail "$domain must resolve to an IPv4 address assigned to this VM"
}

printf 'Preflight passed for %s\n' "$domain"
