#!/bin/sh
set -eu

login=${1:-}
case "$login" in
  ''|[!a-z]*|*[!a-z0-9-]*|*-)
    echo "42 login must start with a lowercase letter and contain only lowercase letters, digits, and internal hyphens" >&2
    exit 2
    ;;
esac
if [ "${#login}" -gt 32 ]; then
  echo "42 login must not exceed 32 characters" >&2
  exit 2
fi
case "$login" in
  root|inception)
    echo "42 login '$login' is reserved" >&2
    exit 2
    ;;
esac

env_file=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)/srcs/.env
tmp_file="${env_file}.tmp.$$"
trap 'rm -f "$tmp_file"' EXIT HUP INT TERM

sed \
  -e "s|^DOMAIN_NAME=.*|DOMAIN_NAME=${login}.42.fr|" \
  -e "s|^DATA_PATH=.*|DATA_PATH=/home/${login}/data|" \
  -e "s|^WP_ADMIN_EMAIL=.*|WP_ADMIN_EMAIL=siteowner@${login}.42.fr|" \
  -e "s|^WP_USER_EMAIL=.*|WP_USER_EMAIL=author@${login}.42.fr|" \
  "$env_file" > "$tmp_file"
chmod 0644 "$tmp_file"
mv "$tmp_file" "$env_file"
trap - EXIT HUP INT TERM

printf 'Configured %s and /home/%s/data in %s\n' "${login}.42.fr" "$login" "$env_file"
