#!/bin/sh
set -eu

fail() { printf 'Host setup: %s\n' "$*" >&2; exit 1; }
login=${1:-}
case "$login" in ''|[!a-z]*|*[!a-z0-9-]*|*-|root|inception) fail 'Usage: host-setup.sh LOGIN (lowercase 42 login)' ;; esac
[ "$#" -eq 1 ] && [ "${#login}" -le 32 ] || fail 'Invalid login length or arguments'
[ -z "${DOCKER_HOST+x}${DOCKER_CONTEXT+x}" ] || fail 'Unset DOCKER_HOST and DOCKER_CONTEXT'
command -v docker >/dev/null 2>&1 || fail 'Docker must already be installed'
[ "$(docker context show)" = default ] || fail 'Select the default Docker context'
if [ "$(id -u)" -ne 0 ]; then
  command -v sudo >/dev/null 2>&1 || fail 'Run this command with root privileges'
  exec sudo -- "$0" "$login"
fi
for tool in jq flock systemctl systemd-detect-virt dockerd realpath stat mktemp awk timeout; do command -v "$tool" >/dev/null 2>&1 || fail "Missing $tool"; done
systemd-detect-virt --vm >/dev/null 2>&1 || fail 'host-setup only operates inside a dedicated virtual machine'
[ ! -L /etc/docker ] && [ ! -L /etc/docker/daemon.json ] && [ ! -L /etc/hosts ] || fail 'Symlinked host configuration is unsupported'
target=/home/$login/data/docker
[ -d "/home/$login" ] || fail "Create the learner home /home/$login first"
[ "$(realpath -m -- "$target")" = "$target" ] || fail 'Docker data path must not contain symlinks'
domain=$login.42.fr
record=/var/lib/inception-host-setup
[ ! -L "$record" ] || fail 'Symlinked host management directory'
exec 9>/run/inception-host-setup.lock
flock -x 9
docker_local() { docker --host unix:///var/run/docker.sock "$@"; }
restart_root() {
  timeout --signal=KILL 60 sh -eu -c '
    systemctl restart docker.service
    attempt=0
    while [ "$attempt" -lt 60 ]; do
      if systemctl is-active --quiet docker.service &&
          current=$(docker --host unix:///var/run/docker.sock info --format "{{.DockerRootDir}}" 2>/dev/null) &&
          [ "$current" = "$1" ]; then exit 0; fi
      sleep 1
      attempt=$((attempt + 1))
    done
    exit 1
  ' inception-docker-restart "$1"
}
restore_config() {
  if [ -f "$record/daemon.existed" ]; then
    restore_tmp=$(mktemp /etc/docker/daemon.json.restore.XXXXXX) || return 1
    cp -p "$record/daemon.original" "$restore_tmp" || return 1
    mv -f "$restore_tmp" /etc/docker/daemon.json || return 1
  else
    rm -f /etc/docker/daemon.json || return 1
  fi
  if [ -f "$record/hosts.original" ]; then
    restore_tmp=$(mktemp /etc/hosts.restore.XXXXXX) || return 1
    cp -p "$record/hosts.original" "$restore_tmp" || return 1
    mv -f "$restore_tmp" /etc/hosts || return 1
  fi
  restart_root "$(cat "$record/original-root")" || return 1
  rm -f "$record/complete"
}
if [ -d "$record" ]; then
  [ "$(stat -c '%u:%a' "$record")" = 0:700 ] || fail 'Invalid host management directory ownership or permissions'
  if [ -f "$record/pending" ]; then
    restore_config || fail 'Interrupted setup rollback failed; saved originals remain in /var/lib/inception-host-setup'
    rm -f "$record/pending"
    fail 'Recovered interrupted host setup; inspect the saved state and run again'
  fi
fi
systemctl is-active --quiet docker.service || fail 'docker.service must already be running'
daemon_pid=$(systemctl show --property MainPID --value docker.service)
case "$daemon_pid" in ''|0|*[!0-9]*) fail 'Cannot identify docker.service process' ;; esac
[ "$(basename "$(readlink "/proc/$daemon_pid/exe")")" = dockerd ] || fail 'docker.service MainPID is not dockerd'
socket_inodes=$(awk '$8 == "/var/run/docker.sock" || $8 == "/run/docker.sock" {print $7}' /proc/net/unix)
socket_match=0
for descriptor in "/proc/$daemon_pid/fd/"*; do
  descriptor_target=$(readlink "$descriptor" 2>/dev/null || true)
  for inode in $socket_inodes; do [ "$descriptor_target" != "socket:[$inode]" ] || socket_match=1; done
done
[ "$socket_match" -eq 1 ] || fail 'The local Docker socket does not belong to docker.service MainPID'
if tr '\000' '\n' < "/proc/$daemon_pid/cmdline" | awk '/^--(config-file|data-root)(=|$)/ {bad=1} END {exit !bad}'; then
  fail 'Custom config-file or command-line data-root requires explicit external configuration'
fi
info=$(docker_local info --format '{{json .}}')
printf '%s' "$info" | jq -e '.SecurityOptions | all(.[]; contains("rootless") | not)' >/dev/null || fail 'Rootless Docker is unsupported'
old_root=$(printf '%s' "$info" | jq -r .DockerRootDir)
hosts_count=$(awk -v domain="$domain" '{for(i=2;i<=NF;i++) {if($i ~ /^#/) break; if($i==domain) count++}} END {print count+0}' /etc/hosts)
if [ "$hosts_count" -gt 0 ]; then
  [ "$hosts_count" -eq 1 ] && awk -v domain="$domain" '$1=="127.0.0.1" {for(i=2;i<=NF;i++) {if($i ~ /^#/) break; if($i==domain) ok=1}} END {exit !ok}' /etc/hosts || fail "Existing conflicting hosts entry for $domain"
fi
if [ -f "$record/complete" ]; then
  [ "$(cat "$record/target")" = "$target" ] && [ "$old_root" = "$target" ] && [ "$hosts_count" -eq 1 ] || fail 'Existing management record does not match current configuration'
  [ "$(jq -r '."data-root"' /etc/docker/daemon.json)" = "$target" ] || fail 'Managed Docker configuration was changed'
  printf 'Host already configured for %s\n' "$domain"
  exit 0
fi
existing=$(docker_local ps -aq) || fail 'Container query failed'
[ -z "$existing" ] || fail 'Existing containers: automatic data migration is not supported'
existing=$(docker_local volume ls -q) || fail 'Volume query failed'
[ -z "$existing" ] || fail 'Existing volumes: automatic data migration is not supported'
existing=$(docker_local image ls -aq) || fail 'Image query failed'
[ -z "$existing" ] || fail 'Existing images: use an empty dedicated Docker daemon'
existing=$(docker_local network ls --format '{{.Name}}') || fail 'Network query failed'
printf '%s\n' "$existing" | awk '$0!="bridge" && $0!="host" && $0!="none" {bad=1} END {exit bad}' || fail 'Existing custom networks prevent host setup'
[ ! -e "$target" ] || [ -d "$target" ] || fail 'Docker data target is not a directory'
if [ -d "$target" ] && [ -n "$(find "$target" -mindepth 1 -maxdepth 1 -print -quit)" ]; then fail 'Docker data target must be empty'; fi
install -d -m 0700 "$record"
install -d -m 0755 /etc/docker
if [ -f /etc/docker/daemon.json ]; then
  jq -e 'type == "object"' /etc/docker/daemon.json >/dev/null || fail 'Invalid Docker configuration JSON'
  cp -p /etc/docker/daemon.json "$record/daemon.original"
  : > "$record/daemon.existed"
else
  printf '{}\n' > "$record/daemon.original"
  rm -f "$record/daemon.existed"
fi
cp -p /etc/hosts "$record/hosts.original"
printf '%s\n' "$old_root" > "$record/original-root"
printf '%s\n' "$target" > "$record/target"
transaction=0
config_tmp=
hosts_tmp=
cleanup() {
  result=$?
  trap - EXIT INT TERM HUP
  [ -z "$config_tmp" ] || rm -f "$config_tmp"
  [ -z "$hosts_tmp" ] || rm -f "$hosts_tmp"
  if [ "$transaction" -eq 1 ]; then
    if restore_config; then
      rm -f "$record/pending"
      printf '%s\n' 'Host setup rolled back to original configuration.' >&2
    else
      printf '%s\n' 'Host rollback failed; saved originals remain in /var/lib/inception-host-setup.' >&2
    fi
    [ "$result" -ne 0 ] || result=1
  fi
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
config_tmp=$(mktemp /etc/docker/daemon.json.new.XXXXXX)
jq --arg target "$target" '. + {"data-root": $target}' "$record/daemon.original" > "$config_tmp"
if [ -f "$record/daemon.existed" ]; then
  chmod --reference="$record/daemon.original" "$config_tmp"
  chown --reference="$record/daemon.original" "$config_tmp"
else
  chmod 0600 "$config_tmp"
  chown root:root "$config_tmp"
fi
jq -Rse 'split("\u0000") | .[1:-1] | all(.[]; contains("\n") | not)' < "/proc/$daemon_pid/cmdline" >/dev/null || fail 'Daemon arguments containing newlines are unsupported'
jq -Rsr 'split("\u0000") | .[1:-1][]' < "/proc/$daemon_pid/cmdline" > "$record/daemon.arguments"
set --
while IFS= read -r argument; do set -- "$@" "$argument"; done < "$record/daemon.arguments"
dockerd --validate --config-file "$config_tmp" "$@"
hosts_tmp=$(mktemp /etc/hosts.new.XXXXXX)
cp -p /etc/hosts "$hosts_tmp"
if [ "$hosts_count" -eq 0 ]; then printf '\n127.0.0.1 %s\n' "$domain" >> "$hosts_tmp"; fi
install -d -m 0750 "/home/$login/data"
install -d -m 0710 "$target"
: > "$record/pending"
transaction=1
mv -f "$config_tmp" /etc/docker/daemon.json
config_tmp=
mv -f "$hosts_tmp" /etc/hosts
hosts_tmp=
restart_root "$target" || fail 'Docker restart and data-root readiness did not complete within 60 seconds'
getent ahostsv4 "$domain" | awk '$1=="127.0.0.1" {ok=1} END {exit !ok}' || fail 'Configured domain does not resolve locally'
: > "$record/complete"
rm -f "$record/pending"
transaction=0
printf 'Configured rootful Docker storage at %s and domain %s\n' "$target" "$domain"
