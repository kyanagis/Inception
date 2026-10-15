#!/bin/sh
set -eu
password=$(tr -d '\r\n' < /run/secrets/redis_password)
[ "${#password}" -eq 64 ] || exit 1
REDISCLI_AUTH=$password redis-cli --user wordpress ping 2>/dev/null | grep -Fx PONG >/dev/null
