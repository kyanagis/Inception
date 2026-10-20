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

# Existing configuration is user-owned. Automatic setup never resets it.
if [ -e "$env_file" ]; then
  [ -f "$env_file" ] || fail 'Expected a regular srcs/.env'
  definitions=$(grep -Ec '^[[:space:]]*(export[[:space:]]+)?DOMAIN_NAME([[:space:]]*(=|$))' "$env_file" || :)
  [ "$definitions" = 1 ] || fail 'Expected exactly one canonical DOMAIN_NAME definition'
  old_domain=$(sed -n 's/^DOMAIN_NAME=//p' "$env_file")
  [ "$old_domain" = "$login.42.fr" ] || fail 'Existing configuration has another or invalid DOMAIN_NAME; migrate explicitly'
  printf 'Preserved existing configuration for %s\n' "$old_domain"
  exit 0
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
