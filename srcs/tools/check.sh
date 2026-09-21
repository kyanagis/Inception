#!/bin/sh
set -eu
project_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$project_dir"
fail() { printf 'Static check: %s\n' "$*" >&2; exit 1; }
for tool in docker jq grep find python3; do command -v "$tool" >/dev/null 2>&1 || fail "Missing $tool"; done
for document in README.md USER_DOC.md DEV_DOC.md; do
  [ -s "$document" ] || fail "Missing or empty $document"
done
grep -Fqx 'This project has been created as part of the 42 curriculum by kyanagis.' README.md || fail 'README lacks the required 42 curriculum attribution'
grep -Eq '^# Inception
for heading in Description Instructions Resources; do grep -Eq "^##+ $heading$" README.md || fail "README lacks $heading"; done
config=$(docker compose --env-file srcs/.env -f srcs/docker-compose.yml --profile bonus config --format json)
printf '%s' "$config" | jq -e '
  (.services | length == 8) and
  all(.services | to_entries[];
    .value.image == (.key + ":inception") and
    .value.restart == "unless-stopped" and .value.stop_grace_period == "30s" and
    .value.init == true and .value.read_only == true and
    (.value.mem_limit > 0) and (.value.pids_limit > 0) and
    .value.build.dockerfile == "Dockerfile" and
    (.value.networks | length > 0) and
    (.value.network_mode == null) and (.value.links == null)) and
  all(.volumes[]; .driver == "local" and (.driver_opts == null)) and
  (.services.mariadb.ports == null) and (.services.wordpress.ports == null) and
  (.services.nginx.ports | length == 1) and
  (.services.nginx.ports[0].published == "443")
' >/dev/null
printf '%s' "$config" | jq -e '
  ([.services.backup.secrets[].source] == ["db_backup_password"]) and
  ([.services.redis.secrets[].source] == ["redis_password"]) and
  ([.services.ftp.secrets[].source] | sort == ["ftp_password", "ftps_certificate", "ftps_private_key"]) and
  (.services.ftp.networks | keys == ["edge"]) and
  (.services["static-site"].networks | keys == ["edge"]) and
  (.services.adminer.networks | keys == ["backend"]) and
  all(.services | to_entries[]; all(.value.tmpfs[]?; contains("size=") and contains("nosuid") and contains("nodev") and contains("noexec")))
' >/dev/null || fail 'Least-privilege service boundaries are incomplete'
for image in mariadb wordpress nginx redis ftp static-site adminer backup; do
  file=$(find srcs/requirements -path "*/$image/Dockerfile")
  [ "$(printf '%s\n' "$file" | wc -l)" -eq 1 ] && [ -f "$file" ]
  grep -Eq '^FROM debian:12\.[0-9]+-slim@sha256:[0-9a-f]{64}$' "$file"
done
if grep -REn 'tail[[:space:]]+-f|sleep[[:space:]]+infinity|while[[:space:]]+true|network_mode:[[:space:]]*host|links:' srcs/requirements srcs/docker-compose.yml; then
  echo 'Prohibited container pattern' >&2; exit 1
fi
if grep -REn '(PASSWORD|PASSWD|SECRET)[[:space:]]*=' srcs/requirements --include=Dockerfile; then
  echo 'Credential assignment in a Dockerfile' >&2; exit 1
fi
grep -Eq '^[[:space:]]*ssl_protocols TLSv1\.2 TLSv1\.3;' srcs/requirements/nginx/conf/nginx.conf.template
grep -Fq "location = /xmlrpc.php { return 403; }" srcs/requirements/nginx/conf/nginx.conf.template
grep -Fq 'location ~ /\. { deny all; }' srcs/requirements/nginx/conf/nginx.conf.template
grep -Fq "DISALLOW_FILE_MODS' => true" srcs/requirements/wordpress/tools/configure.php
grep -Fq 'user default off' srcs/requirements/bonus/redis/tools/entrypoint.sh
grep -Fq 'exec gosu redis "$@"' srcs/requirements/bonus/redis/tools/entrypoint.sh
grep -Fq -- '-flushall -flushdb -config -acl -shutdown' srcs/requirements/bonus/redis/tools/entrypoint.sh
shell_files=$(find srcs/tools srcs/requirements -name '*.sh')
for file in $shell_files; do sh -n "$file"; done
for file in srcs/requirements/bonus/backup/tools/manifest.py srcs/requirements/bonus/backup/tools/schedule.py; do
  python3 -c 'import ast, pathlib, sys; ast.parse(pathlib.Path(sys.argv[1]).read_text(), filename=sys.argv[1])' "$file"
done
if find . \( -path ./.git -o -path ./secrets \) -prune -o -type f \( -name '*.pem' -o -name '*.key' -o -name '*.crt' \) -print | grep -q .; then
  fail 'Certificate or private-key material exists outside the ignored secrets workflow'
fi
if grep -REn --exclude-dir='.git' --exclude-dir='secrets' --exclude='.env' --exclude='*.md' '(BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|AKIA[0-9A-Z]{16})' .; then
  fail 'Potential credential material detected'
fi
printf '%s\n' 'Static configuration checks passed.'
 README.md || fail 'README lacks the project title'
for heading in Description Instructions Resources; do grep -Eq "^##+ $heading$" README.md || fail "README lacks $heading"; done
config=$(docker compose --env-file srcs/.env -f srcs/docker-compose.yml --profile bonus config --format json)
printf '%s' "$config" | jq -e '
  (.services | length == 8) and
  all(.services | to_entries[];
    .value.image == (.key + ":inception") and
    .value.restart == "unless-stopped" and .value.stop_grace_period == "30s" and
    .value.init == true and .value.read_only == true and
    (.value.mem_limit > 0) and (.value.pids_limit > 0) and
    .value.build.dockerfile == "Dockerfile" and
    (.value.networks | length > 0) and
    (.value.network_mode == null) and (.value.links == null)) and
  all(.volumes[]; .driver == "local" and (.driver_opts == null)) and
  (.services.mariadb.ports == null) and (.services.wordpress.ports == null) and
  (.services.nginx.ports | length == 1) and
  (.services.nginx.ports[0].published == "443")
' >/dev/null
printf '%s' "$config" | jq -e '
  ([.services.backup.secrets[].source] == ["db_backup_password"]) and
  ([.services.redis.secrets[].source] == ["redis_password"]) and
  ([.services.ftp.secrets[].source] | sort == ["ftp_password", "ftps_certificate", "ftps_private_key"]) and
  (.services.ftp.networks | keys == ["edge"]) and
  (.services["static-site"].networks | keys == ["edge"]) and
  (.services.adminer.networks | keys == ["backend"]) and
  all(.services | to_entries[]; all(.value.tmpfs[]?; contains("size=") and contains("nosuid") and contains("nodev") and contains("noexec")))
' >/dev/null || fail 'Least-privilege service boundaries are incomplete'
for image in mariadb wordpress nginx redis ftp static-site adminer backup; do
  file=$(find srcs/requirements -path "*/$image/Dockerfile")
  [ "$(printf '%s\n' "$file" | wc -l)" -eq 1 ] && [ -f "$file" ]
  grep -Eq '^FROM debian:12\.[0-9]+-slim@sha256:[0-9a-f]{64}$' "$file"
done
if grep -REn 'tail[[:space:]]+-f|sleep[[:space:]]+infinity|while[[:space:]]+true|network_mode:[[:space:]]*host|links:' srcs/requirements srcs/docker-compose.yml; then
  echo 'Prohibited container pattern' >&2; exit 1
fi
if grep -REn '(PASSWORD|PASSWD|SECRET)[[:space:]]*=' srcs/requirements --include=Dockerfile; then
  echo 'Credential assignment in a Dockerfile' >&2; exit 1
fi
grep -Eq '^[[:space:]]*ssl_protocols TLSv1\.2 TLSv1\.3;' srcs/requirements/nginx/conf/nginx.conf.template
grep -Fq "location = /xmlrpc.php { return 403; }" srcs/requirements/nginx/conf/nginx.conf.template
grep -Fq "DISALLOW_FILE_MODS' => true" srcs/requirements/wordpress/tools/configure.php
grep -Fq 'user default off' srcs/requirements/bonus/redis/tools/entrypoint.sh
shell_files=$(find srcs/tools srcs/requirements -name '*.sh')
for file in $shell_files; do sh -n "$file"; done
for file in srcs/requirements/bonus/backup/tools/manifest.py srcs/requirements/bonus/backup/tools/schedule.py; do
  python3 -c 'import ast, pathlib, sys; ast.parse(pathlib.Path(sys.argv[1]).read_text(), filename=sys.argv[1])' "$file"
done
if find . \( -path ./.git -o -path ./secrets \) -prune -o -type f \( -name '*.pem' -o -name '*.key' -o -name '*.crt' \) -print | grep -q .; then
  fail 'Certificate or private-key material exists outside the ignored secrets workflow'
fi
if grep -REn --exclude-dir='.git' --exclude-dir='secrets' --exclude='.env' --exclude='*.md' '(BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|AKIA[0-9A-Z]{16})' .; then
  fail 'Potential credential material detected'
fi
printf '%s\n' 'Static configuration checks passed.'
