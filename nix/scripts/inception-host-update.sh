#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'inception-host-update: %s\n' "$*" >&2
  exit 1
}

# Nix store binaries cannot be setuid.  Do not rely on PATH here: the
# writeShellApplication runtime-input PATH contains a store copy of sudo
# before /run/wrappers/bin.  The NixOS wrapper is the privileged interface.
sudo_wrapper=/run/wrappers/bin/sudo
[[ -x "$sudo_wrapper" ]] || fail 'NixOS sudo wrapper is unavailable'

required_abi=
case "${1:-}" in
  --ensure)
    shift
    [[ $# -eq 1 && "$1" =~ ^[0-9]+$ ]] || fail 'usage: inception-host-update --ensure ABI'
    required_abi=$1
    ;;
  --help|-h)
    cat <<'EOF'
Usage:
  inception-host-update
  inception-host-update --ensure ABI

Without --ensure, update the running x86_64 NixOS guest to the immutable
commit named by INCEPTION_HOST_REPO_REF. With --ensure, do nothing when the
installed host ABI is already new enough; otherwise update and verify the
requested ABI. Privileged host updates intentionally reject mutable branch or
tag names.
EOF
    exit 0
    ;;
  '')
    ;;
  *)
    fail "unknown argument: $1"
    ;;
esac

[[ "$(uname -m)" == x86_64 ]] || fail 'this appliance runtime is x86_64 only'
current_abi=0
if [[ -r /etc/inception-host-abi ]]; then
  current_abi=$(tr -d '[:space:]' < /etc/inception-host-abi)
fi
[[ "$current_abi" =~ ^[0-9]+$ ]] || fail 'invalid installed host ABI marker'

installed_kernel=
if [[ -r /etc/inception-kernel-version ]]; then
  installed_kernel=$(tr -d '[:space:]' < /etc/inception-kernel-version)
fi
if [[ -n "$installed_kernel" && "$(uname -r)" != "$installed_kernel" ]]; then
  fail "host generation expects kernel $installed_kernel but running kernel is $(uname -r); reboot the appliance before continuing"
fi

if [[ -n "$required_abi" && "$current_abi" -ge "$required_abi" ]]; then
  printf 'Host ABI %s already satisfies required ABI %s.\n' "$current_abi" "$required_abi"
  exit 0
fi

remote=${INCEPTION_HOST_REPO_URL:-https://github.com/kyanagis/Inception.git}
ref=${INCEPTION_HOST_REPO_REF:-}
[[ "$ref" =~ ^[0-9a-f]{40}$ ]] ||
  fail 'refusing privileged update from a mutable ref; set INCEPTION_HOST_REPO_REF to a full 40-hex commit SHA'

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM

printf 'Fetching immutable host runtime %s from %s...\n' "$ref" "$remote"
git init -q "$work/source"
git -C "$work/source" remote add origin "$remote"
git -C "$work/source" fetch --quiet --depth 1 origin "$ref"
sha=$(git -C "$work/source" rev-parse FETCH_HEAD)
[[ "$sha" == "$ref" ]] || fail "fetched host commit $sha does not match requested $ref"
git -C "$work/source" checkout --quiet --detach "$sha"
printf 'Host source commit: %s\n' "$sha"

nix --extra-experimental-features 'nix-command flakes'   build --no-link "path:$work/source#nixosConfigurations.inception-runtime.config.system.build.toplevel"

"$sudo_wrapper" -v
old_system=$(readlink -f /run/current-system)
if ! "$sudo_wrapper" /run/current-system/sw/bin/nixos-rebuild switch     --flake "path:$work/source#inception-runtime"; then
  printf 'Host activation failed; attempting rollback to %s\n' "$old_system" >&2
  "$sudo_wrapper" "$old_system/bin/switch-to-configuration" switch || true
  exit 1
fi

new_abi=0
if [[ -r /etc/inception-host-abi ]]; then
  new_abi=$(tr -d '[:space:]' < /etc/inception-host-abi)
fi
[[ "$new_abi" =~ ^[0-9]+$ ]] || fail 'updated host has an invalid ABI marker'
if [[ -n "$required_abi" && "$new_abi" -lt "$required_abi" ]]; then
  printf 'Updated main provides host ABI %s, but submit requires %s. Rolling back.\n' "$new_abi" "$required_abi" >&2
  "$sudo_wrapper" "$old_system/bin/switch-to-configuration" switch || true
  exit 1
fi

printf '%s\n' "$sha" | "$sudo_wrapper" tee /var/lib/inception/host-version >/dev/null
"$sudo_wrapper" chmod 0644 /var/lib/inception/host-version

expected_kernel=
if [[ -r /etc/inception-kernel-version ]]; then
  expected_kernel=$(tr -d '[:space:]' < /etc/inception-kernel-version)
fi
if [[ -n "$expected_kernel" && "$(uname -r)" != "$expected_kernel" ]]; then
  printf 'Host runtime switched to ABI %s at %s, but kernel %s is still running; reboot once to activate kernel %s.\n' \
    "$new_abi" "$sha" "$(uname -r)" "$expected_kernel" >&2
  exit 75
fi

printf 'Host update complete: ABI %s, commit %s\n' "$new_abi" "$sha"
