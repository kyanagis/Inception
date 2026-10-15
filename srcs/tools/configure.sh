#!/bin/sh
set -eu

fail() { printf '%s\n' "$*" >&2; exit 2; }
login=${1:-}
case "$login" in ''|[!a-z]*|*[!a-z0-9-]*|*-|root|inception) fail 'Invalid 42 login' ;; esac
[ "${#login}" -le 32 ] || fail '42 login exceeds 32 characters'
[ "$#" -eq 1 ] || fail 'Usage: configure.sh LOGIN'

project_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
template=$project_dir/srcs/.env.example
env_file=$project_dir/srcs/.env
[ -f "$template" ] && [ ! -L "$template" ] || fail 'Expected a regular srcs/.env.example'
[ ! -L "$env_file" ] || fail 'Refusing symlink srcs/.env'

old_domain=
if [ -f "$env_file" ]; then
  old_domain=$(sed -n 's/^DOMAIN_NAME=//p' "$env_file")
fi

if [ -n "$old_domain" ] && [ "$old_domain" != "$login.42.fr" ]; then
  if command -v docker >/dev/null 2>&1 && docker --host unix:///var/run/docker.sock info >/dev/null 2>&1; then
    for volume in inception_mariadb_data inception_wordpress_data inception_backup_data; do
      if docker --host unix:///var/run/docker.sock volume inspect "$volume" >/dev/null 2>&1; then
        fail 'Existing project volumes prevent changing login; preserve data and migrate explicitly'
      fi
    done
  elif [ -d "$project_dir/secrets" ] && find "$project_dir/secrets" -type f ! -name .gitkeep -print -quit | read -r _entry; then
    fail 'Cannot verify existing deployment while Docker is unavailable; restore daemon access before changing login'
  fi
fi

tmp_file=$(mktemp "$project_dir/srcs/.env.tmp.XXXXXX")
trap 'rm -f "$tmp_file"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
sed -e "s|LOGIN|$login|g" "$template" > "$tmp_file"
chmod 0600 "$tmp_file"
mv -f "$tmp_file" "$env_file"
trap - EXIT INT TERM HUP
printf 'Configured https://%s.42.fr and /home/%s/data\n' "$login" "$login"
