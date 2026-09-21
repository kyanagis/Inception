#!/bin/sh
set -eu
nc -z 127.0.0.1 9000
runuser -u www-data -- wp --path=/var/www/html db check --quiet >/dev/null 2>&1
