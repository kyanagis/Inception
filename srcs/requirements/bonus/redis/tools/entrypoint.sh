#!/bin/sh
set -eu
umask 077

[ "${1:-}" = redis-server ] || exec "$@"
[ -f /run/secrets/redis_password ] && [ ! -L /run/secrets/redis_password ] || {
  echo 'Missing or unsafe Redis secret' >&2; exit 1;
}
password=$(tr -d '\r\n' < /run/secrets/redis_password)
[ "${#password}" -eq 64 ] && printf '%s\n' "$password" | LC_ALL=C grep -Eq '^[0-9a-fA-F]{64}$' || {
  echo 'Invalid Redis secret' >&2; exit 2;
}
[ -d /run/redis ] && [ ! -L /run/redis ] || { echo 'Unsafe Redis runtime directory' >&2; exit 1; }
printf 'user default off\nuser wordpress on >%s ~* +@all\n' "$password" > /run/redis/users.acl
chmod 0600 /run/redis/users.acl
unset password
exec "$@"
