#!/bin/sh
set -eu

project_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$project_dir"

fail() { printf 'Dependency audit: %s\n' "$*" >&2; exit 1; }

for tool in curl jq sha256sum sed mktemp; do
  command -v "$tool" >/dev/null 2>&1 || fail "Missing $tool"
done

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT HUP INT TERM

compose_arg() {
  key=$1
  sed -n "s/^[[:space:]]*$key: \"\([^\"]*\)\"/\\1/p" srcs/docker-compose.yml | head -n 1
}
compose_hash() {
  key=$1
  sed -n "s/^[[:space:]]*$key: \([0-9a-fA-F][0-9a-fA-F]*\)$/\\1/p" srcs/docker-compose.yml | head -n 1
}
require_hash() {
  name=$1
  value=$2
  [ "${#value}" -eq 64 ] && printf '%s\n' "$value" | grep -Eq '^[0-9a-fA-F]{64}$' ||
    fail "$name has an invalid SHA-256 pin"
}
github_release() {
  repo=$1
  output=$2
  curl --fail --silent --show-error --location --retry 3 \
    -H 'Accept: application/vnd.github+json' \
    -H 'User-Agent: kyanagis-inception-dependency-audit' \
    "https://api.github.com/repos/$repo/releases/latest" -o "$output"
}

# WordPress Core: official version-check API + archive digest.
wordpress_version=$(compose_arg WORDPRESS_VERSION)
wordpress_sha=$(compose_hash WORDPRESS_SHA256)
[ -n "$wordpress_version" ] && [ -n "$wordpress_sha" ] ||
  fail 'Unable to read pinned WordPress version/SHA-256'
require_hash WordPress "$wordpress_sha"

curl --fail --silent --show-error --location --retry 3 \
  "https://api.wordpress.org/core/version-check/1.7/?version=$wordpress_version&php=8.2&locale=en_US&mysql=10.11" \
  -o "$tmpdir/wordpress-version.json"
jq -e --arg version "$wordpress_version" '
  (.offers | type == "array") and
  any(.offers[]; .response == "latest" and .current == $version)
' "$tmpdir/wordpress-version.json" >/dev/null ||
  fail "Pinned WordPress $wordpress_version is not reported as the latest supported release"

curl --fail --silent --show-error --location --retry 3 \
  "https://wordpress.org/wordpress-$wordpress_version.tar.gz" \
  -o "$tmpdir/wordpress.tar.gz"
printf '%s  %s\n' "$wordpress_sha" "$tmpdir/wordpress.tar.gz" |
  sha256sum --check --strict - >/dev/null ||
  fail 'Pinned WordPress archive SHA-256 does not match upstream'

# WP-CLI: GitHub latest release + GitHub asset digest.
wp_cli_version=$(compose_arg WP_CLI_VERSION)
wp_cli_sha=$(compose_hash WP_CLI_SHA256)
[ -n "$wp_cli_version" ] && [ -n "$wp_cli_sha" ] ||
  fail 'Unable to read pinned WP-CLI version/SHA-256'
require_hash WP-CLI "$wp_cli_sha"
github_release wp-cli/wp-cli "$tmpdir/wp-cli.json"
[ "$(jq -r '.tag_name // empty' "$tmpdir/wp-cli.json")" = "v$wp_cli_version" ] ||
  fail "Pinned WP-CLI $wp_cli_version is not the current official release"
wp_cli_digest=$(jq -r --arg asset "wp-cli-$wp_cli_version.phar" '
  [.assets[] | select(.name == $asset) | .digest][0] // empty
' "$tmpdir/wp-cli.json")
[ "$wp_cli_digest" = "sha256:$wp_cli_sha" ] ||
  fail 'Pinned WP-CLI SHA-256 does not match the official GitHub asset digest'

# Redis Object Cache: WordPress.org plugin API + exact archive digest.  If the
# pin becomes stale, calculate the new upstream archive hash in the failure
# message so updating the immutable pin remains a deliberate review step.
redis_version=$(compose_arg REDIS_PLUGIN_VERSION)
redis_sha=$(compose_hash REDIS_PLUGIN_SHA256)
[ -n "$redis_version" ] && [ -n "$redis_sha" ] ||
  fail 'Unable to read pinned Redis Object Cache version/SHA-256'
require_hash 'Redis Object Cache' "$redis_sha"
curl --fail --silent --show-error --location --retry 3 --get \
  'https://api.wordpress.org/plugins/info/1.2/' \
  --data-urlencode 'action=plugin_information' \
  --data-urlencode 'request[slug]=redis-cache' \
  --data-urlencode 'request[fields][versions]=0' \
  -o "$tmpdir/redis-plugin.json"
redis_latest=$(jq -r '.version // empty' "$tmpdir/redis-plugin.json")
redis_url=$(jq -r '.download_link // empty' "$tmpdir/redis-plugin.json")
[ -n "$redis_latest" ] && [ -n "$redis_url" ] ||
  fail 'WordPress.org did not return Redis Object Cache release metadata'
curl --fail --silent --show-error --location --retry 3 "$redis_url" -o "$tmpdir/redis-cache.zip"
redis_upstream_sha=$(sha256sum "$tmpdir/redis-cache.zip" | awk '{print $1}')
if [ "$redis_version" != "$redis_latest" ]; then
  fail "Pinned Redis Object Cache $redis_version is stale; current=$redis_latest current_sha256=$redis_upstream_sha"
fi
[ "$redis_upstream_sha" = "$redis_sha" ] ||
  fail 'Pinned Redis Object Cache SHA-256 does not match the current WordPress.org archive'

# Adminer: GitHub latest release + GitHub asset digest.
adminer_version=$(compose_arg ADMINER_VERSION)
adminer_sha=$(compose_hash ADMINER_SHA256)
[ -n "$adminer_version" ] && [ -n "$adminer_sha" ] ||
  fail 'Unable to read pinned Adminer version/SHA-256'
require_hash Adminer "$adminer_sha"
github_release vrana/adminer "$tmpdir/adminer.json"
[ "$(jq -r '.tag_name // empty' "$tmpdir/adminer.json")" = "v$adminer_version" ] ||
  fail "Pinned Adminer $adminer_version is not the current official release"
adminer_digest=$(jq -r --arg asset "adminer-$adminer_version-en.php" '
  [.assets[] | select(.name == $asset) | .digest][0] // empty
' "$tmpdir/adminer.json")
[ "$adminer_digest" = "sha256:$adminer_sha" ] ||
  fail 'Pinned Adminer SHA-256 does not match the official GitHub asset digest'

printf '%s\n' \
  "Dependency audit passed:" \
  "  WordPress=$wordpress_version" \
  "  WP-CLI=$wp_cli_version" \
  "  Redis Object Cache=$redis_version" \
  "  Adminer=$adminer_version"
