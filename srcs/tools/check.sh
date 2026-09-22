#!/bin/sh
set -eu
project_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$project_dir"
fail() { printf 'Static check: %s\n' "$*" >&2; exit 1; }

for tool in docker jq grep find python3; do
  command -v "$tool" >/dev/null 2>&1 || fail "Missing $tool"
done

for document in README.md USER_DOC.md DEV_DOC.md; do
  [ -s "$document" ] || fail "Missing or empty $document"
done
grep -Fqx 'This project has been created as part of the 42 curriculum by kyanagis.' README.md ||
  fail 'README lacks the required 42 curriculum attribution'
grep -Eq '^# Inception$' README.md || fail 'README lacks the project title'
for heading in Description Instructions Resources; do
  grep -Eq "^##+ $heading$" README.md || fail "README lacks $heading"
done

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
' >/dev/null || fail 'Core Compose contract is incomplete'

printf '%s' "$config" | jq -e '
  ([.services.backup.secrets[].source] == ["db_backup_password"]) and
  ([.services.redis.secrets[].source] == ["redis_password"]) and
  ([.services.ftp.secrets[].source] | sort == ["ftp_password", "ftps_certificate", "ftps_private_key"]) and
  (.services.ftp.networks | keys == ["edge"]) and
  (.services["static-site"].networks | keys == ["edge"]) and
  (.services.adminer.networks | keys | sort == ["adminer_access", "backend"]) and
  all(.services | to_entries[];
    all(.value.tmpfs[]?; contains("size=") and contains("nosuid") and contains("nodev") and contains("noexec")))
' >/dev/null || fail 'Least-privilege service boundaries are incomplete'

grep -Fqx '!tools/healthcheck.sh' srcs/requirements/wordpress/.dockerignore ||
  fail 'WordPress .dockerignore excludes the healthcheck copied by its Dockerfile'

for required in '!tools/entrypoint.sh' '!tools/healthcheck.sh'; do
  grep -Fqx "$required" srcs/requirements/bonus/redis/.dockerignore ||
    fail "Redis .dockerignore excludes runtime scripts required by its Dockerfile"
done

for image in mariadb wordpress nginx redis ftp static-site adminer backup; do
  file=$(find srcs/requirements -path "*/$image/Dockerfile")
  [ "$(printf '%s\n' "$file" | wc -l)" -eq 1 ] && [ -f "$file" ] ||
    fail "Expected one Dockerfile for $image"
  grep -Eq '^FROM debian:12\.[0-9]+-slim@sha256:[0-9a-f]{64}$' "$file" ||
    fail "$image does not use the pinned Debian 12 slim base contract"
done

if grep -REn 'tail[[:space:]]+-f|sleep[[:space:]]+infinity|while[[:space:]]+true|network_mode:[[:space:]]*host|links:' srcs/requirements srcs/docker-compose.yml; then
  fail 'Prohibited container pattern'
fi
if grep -REn '(PASSWORD|PASSWD|SECRET)[[:space:]]*=' srcs/requirements --include=Dockerfile; then
  fail 'Credential assignment in a Dockerfile'
fi

grep -Eq '^[[:space:]]*ssl_protocols TLSv1\.2 TLSv1\.3;' srcs/requirements/nginx/conf/nginx.conf.template ||
  fail 'NGINX TLS protocol policy missing'
grep -Fq "location = /xmlrpc.php { return 403; }" srcs/requirements/nginx/conf/nginx.conf.template ||
  fail 'xmlrpc.php protection missing'
grep -Fq 'location ~ /\. { deny all; }' srcs/requirements/nginx/conf/nginx.conf.template ||
  fail 'hidden-file protection missing'
grep -Fq "DISALLOW_FILE_MODS' => true" srcs/requirements/wordpress/tools/configure.php ||
  fail 'WordPress file modification protection missing'
grep -Fq "define('WP_REDIS_PASSWORD', ['wordpress'," srcs/requirements/wordpress/tools/configure.php ||
  fail 'Redis ACL credential array missing from WordPress configuration'
grep -Fq 'user default off' srcs/requirements/bonus/redis/tools/entrypoint.sh ||
  fail 'Redis default ACL user must be disabled'
grep -Fq 'exec gosu redis "$@"' srcs/requirements/bonus/redis/tools/entrypoint.sh ||
  fail 'Redis must drop privileges before daemon start'
grep -Fq -- '+flushdb -flushall -config -acl -shutdown' srcs/requirements/bonus/redis/tools/entrypoint.sh ||
  fail 'Redis lifecycle permission or dangerous-command denylist missing'

shell_files=$(find srcs/tools srcs/requirements -name '*.sh')
for file in $shell_files; do
  sh -n "$file" || fail "Shell syntax error: $file"
done
for file in srcs/requirements/bonus/backup/tools/manifest.py srcs/requirements/bonus/backup/tools/schedule.py; do
  python3 -c 'import ast, pathlib, sys; ast.parse(pathlib.Path(sys.argv[1]).read_text(), filename=sys.argv[1])' "$file" ||
    fail "Python syntax error: $file"
done

if find . \( -path ./.git -o -path ./secrets \) -prune -o -type f \( -name '*.pem' -o -name '*.key' -o -name '*.crt' \) -print | grep -q .; then
  fail 'Certificate or private-key material exists outside the ignored secrets workflow'
fi
if grep -REn --exclude-dir='.git' --exclude-dir='secrets' --exclude='.env' --exclude='*.md' '(BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|AKIA[0-9A-Z]{16})' .; then
  fail 'Potential credential material detected'
fi

printf '%s\n' 'Static configuration checks passed.'

grep -Fq 'Redis did not become reachable' srcs/requirements/wordpress/tools/entrypoint.sh ||
  fail 'Redis object-cache readiness gate missing'
grep -Fq 'chown www-data:www-data "$html/wp-content"' srcs/requirements/wordpress/tools/entrypoint.sh ||
  fail 'Redis object-cache lifecycle lacks its scoped writable wp-content transition'
grep -Fq 'chown -R www-data:www-data "$redis_plugin"' srcs/requirements/wordpress/tools/entrypoint.sh ||
  fail 'Redis plugin lifecycle lacks its scoped writable transition'
if grep -Fq 'chmod 0755 /run/php' srcs/requirements/wordpress/tools/entrypoint.sh; then
  fail 'WordPress must rely on the declared tmpfs mode without CAP_FOWNER'
fi
grep -Fq 'find "$redis_plugin" -xdev -exec chown root:www-data {} +' srcs/requirements/wordpress/tools/entrypoint.sh ||
  fail 'Redis plugin ownership is not restored after its scoped writable transition'

grep -Fq 'runuser -u www-data -- chmod 0755' srcs/requirements/wordpress/tools/entrypoint.sh &&
grep -Fq 'runuser -u www-data -- chmod 0644' srcs/requirements/wordpress/tools/entrypoint.sh ||
  fail 'Redis plugin modes must be normalized before root ownership'
