#!/bin/sh
set -eu

fail() { printf 'Preflight: %s\n' "$*" >&2; exit 1; }
for tool in docker jq realpath stat; do command -v "$tool" >/dev/null 2>&1 || fail "Missing $tool"; done
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
info=$(docker_local info --format '{{json .}}') || fail 'Cannot access local Docker; run make host-setup LOGIN=... in the dedicated VM'
printf '%s' "$info" | jq -e '.SecurityOptions | all(.[]; contains("rootless") | not)' >/dev/null || fail 'Rootless Docker is outside the supported host contract'
[ "$(printf '%s' "$info" | jq -r .DockerRootDir)" = "$data_path/docker" ] || fail "Docker data-root must be $data_path/docker; run make host-setup LOGIN=$login"
engine_version=$(docker_local version --format '{{.Server.Version}}')
compose_version=$(docker_local compose version --short)
[ "$(printf '%s\n' 27.0.3 "$engine_version" | sort -V | head -n 1)" = 27.0.3 ] || fail 'Docker Engine >=27.0.3 is required'
[ "$(printf '%s\n' 2.38.2 "${compose_version#v}" | sort -V | head -n 1)" = 2.38.2 ] || fail 'Docker Compose >=2.38.2 is required'
existing_volumes=$(docker_local volume ls --format '{{.Name}}') || fail 'Docker volume query failed'
for logical in mariadb_data wordpress_data backup_data; do
  name=inception_$logical
  if printf '%s\n' "$existing_volumes" | grep -Fx "$name" >/dev/null; then
    volume=$(docker_local volume inspect "$name") || fail "Cannot inspect existing volume $name"
    printf '%s' "$volume" | jq -e --arg name "$name" --arg logical "$logical" --arg path "$data_path/docker/volumes/$name/_data" \
      'length == 1 and .[0].Name == $name and .[0].Driver == "local" and ((.[0].Options // {}) == {}) and .[0].Mountpoint == $path and .[0].Labels["com.docker.compose.project"] == "inception" and .[0].Labels["com.docker.compose.volume"] == $logical' >/dev/null || fail "Volume $name has unexpected ownership, driver, options or location"
  fi
done
getent ahostsv4 "$domain" | awk '$1 == "127.0.0.1" {ok=1} END {exit !ok}' || fail "$domain must resolve locally; run make host-setup LOGIN=$login"
printf 'Preflight passed for %s\n' "$domain"
