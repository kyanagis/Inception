#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'inception-host-update: %s\n' "$*" >&2
  exit 1
}

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

Without --ensure, update the running x86_64 NixOS guest to the current main
runtime configuration. With --ensure, do nothing when the installed host ABI
is already new enough; otherwise update and verify the requested ABI.
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

if [[ -n "$required_abi" && "$current_abi" -ge "$required_abi" ]]; then
  printf 'Host ABI %s already satisfies required ABI %s.\n' "$current_abi" "$required_abi"
  exit 0
fi

remote=${INCEPTION_HOST_REPO_URL:-https://github.com/kyanagis/Inception.git}
ref=${INCEPTION_HOST_REPO_REF:-main}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM

printf 'Fetching host runtime %s from %s...\n' "$ref" "$remote"
git clone --filter=blob:none --depth 1 --branch "$ref" --single-branch "$remote" "$work/source" >/dev/null
sha=$(git -C "$work/source" rev-parse HEAD)
printf 'Host source commit: %s\n' "$sha"

nix --extra-experimental-features 'nix-command flakes'   build --no-link "path:$work/source#nixosConfigurations.inception-runtime.config.system.build.toplevel"

sudo -v
old_system=$(readlink -f /run/current-system)
if ! sudo /run/current-system/sw/bin/nixos-rebuild switch     --flake "path:$work/source#inception-runtime"; then
  printf 'Host activation failed; attempting rollback to %s\n' "$old_system" >&2
  sudo "$old_system/bin/switch-to-configuration" switch || true
  exit 1
fi

new_abi=0
if [[ -r /etc/inception-host-abi ]]; then
  new_abi=$(tr -d '[:space:]' < /etc/inception-host-abi)
fi
[[ "$new_abi" =~ ^[0-9]+$ ]] || fail 'updated host has an invalid ABI marker'
if [[ -n "$required_abi" && "$new_abi" -lt "$required_abi" ]]; then
  printf 'Updated main provides host ABI %s, but submit requires %s. Rolling back.\n' "$new_abi" "$required_abi" >&2
  sudo "$old_system/bin/switch-to-configuration" switch || true
  exit 1
fi

printf '%s\n' "$sha" | sudo tee /var/lib/inception/host-version >/dev/null
sudo chmod 0644 /var/lib/inception/host-version
printf 'Host update complete: ABI %s, commit %s\n' "$new_abi" "$sha"
