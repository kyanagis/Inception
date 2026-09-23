#!/bin/sh
set -eu

project_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$project_dir"

fail() { printf 'Dependency audit: %s\n' "$*" >&2; exit 1; }

for tool in curl jq sha256sum sed mktemp; do
  command -v "$tool" >/dev/null 2>&1 || fail "Missing $tool"
done

version=$(sed -n 's/^[[:space:]]*WORDPRESS_VERSION: "\([^"]*\)"/\1/p' srcs/docker-compose.yml | head -n 1)
sha256=$(sed -n 's/^[[:space:]]*WORDPRESS_SHA256: \([0-9a-fA-F][0-9a-fA-F]*\)$/\1/p' srcs/docker-compose.yml | head -n 1)
[ -n "$version" ] && [ -n "$sha256" ] || fail 'Unable to read pinned WordPress version/SHA-256'
[ "${#sha256}" -eq 64 ] || fail 'Invalid WordPress SHA-256 pin'

version_json=$(mktemp)
archive=$(mktemp)
trap 'rm -f "$version_json" "$archive"' EXIT HUP INT TERM

curl --fail --silent --show-error --location --retry 3   "https://api.wordpress.org/core/version-check/1.7/?version=$version&php=8.2&locale=en_US&mysql=10.11"   -o "$version_json"

jq -e --arg version "$version" '
  (.offers | type == "array") and
  any(.offers[]; .response == "latest" and .current == $version)
' "$version_json" >/dev/null ||
  fail "Pinned WordPress $version is not reported as the latest supported release"

curl --fail --silent --show-error --location --retry 3   "https://wordpress.org/wordpress-$version.tar.gz" -o "$archive"
printf '%s  %s\n' "$sha256" "$archive" | sha256sum --check --strict - >/dev/null ||
  fail 'Pinned WordPress archive SHA-256 does not match upstream'

printf 'Dependency audit passed: WordPress %s is current and its archive matches the pinned SHA-256.\n' "$version"
