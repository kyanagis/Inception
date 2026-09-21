#!/bin/sh
set -eu
umask 077

[ "${1:-}" = redis-server ] || exec "$@"
[ "$(id -u)" -eq 0 ] || {
  echo 'Redis entrypoint must start as root so it can read the file-backed Compose secret, then it drops privileges' >&2
  exit 1
}
[ -f /run/secrets/redis_password ] && [ ! -L /run/secrets/redis_password ] || {
  echo 'Missing or unsafe Redis secret' >&2
  exit 1
}
password=$(tr -d '\r\n' < /run/secrets/redis_password)
[ "${#password}" -eq 64 ] && printf '%s\n' "$password" | LC_ALL=C grep -Eq '^[0-9a-fA-F]{64}$' || {
  echo 'Invalid Redis secret' >&2
  exit 2
}
[ -d /run/redis ] && [ ! -L /run/redis ] || {
  echo 'Unsafe Redis runtime directory' >&2
  exit 1
}

# Compose file-backed secrets retain the host file ownership/mode.  setup.sh
# deliberately stores credentials as 0600, so the entrypoint reads the secret
# while privileged, publishes only the derived Redis ACL into tmpfs, and then
# permanently drops to the redis account before starting the daemon.
chown redis:redis /run/redis
chmod 0700 /run/redis
printf '%s\n' \
  'user default off' \
  "user wordpress on >$password ~* +@read +@write +@connection +@scripting +ping -flushall -flushdb -config -acl -shutdown -module -replicaof -slaveof -save -bgsave" \
  > /run/redis/users.acl
chown redis:redis /run/redis/users.acl
chmod 0400 /run/redis/users.acl
unset password

exec gosu redis "$@"
