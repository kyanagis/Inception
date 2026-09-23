#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'inception-host-update: %s\n' "$*" >&2
  exit 1
}

sudo_wrapper=/run/wrappers/bin/sudo
[[ -x "$sudo_wrapper" ]] || fail 'NixOS sudo wrapper is unavailable'

remote=https://github.com/kyanagis/Inception.git
required_abi=
target_commit=

usage() {
  cat <<'EOF'
Usage:
  inception-host-update --ensure ABI [COMMIT]
  inception-host-update --commit COMMIT

--ensure exits immediately when the installed host ABI is already new enough.
When an update is required, COMMIT must be an immutable 40-hex Git commit.
--commit always converges the host runtime to the specified commit.

The privileged update path intentionally does not accept a repository URL,
branch name, tag, or environment override.
EOF
}

case "${1:-}" in
  --ensure)
    shift
    [[ $# -ge 1 && $# -le 2 && "$1" =~ ^[0-9]+$ ]] ||
      fail 'usage: inception-host-update --ensure ABI [COMMIT]'
    required_abi=$1
    shift
    if (($#)); then
      target_commit=$1
    fi
    ;;
  --commit)
    shift
    [[ $# -eq 1 ]] || fail 'usage: inception-host-update --commit COMMIT'
    target_commit=$1
    ;;
  --help|-h)
    usage
    exit 0
    ;;
  '')
    usage >&2
    exit 2
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

[[ "$target_commit" =~ ^[0-9a-f]{40}$ ]] ||
  fail 'an immutable 40-hex host source commit is required for host updates'

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM

printf 'Fetching immutable host runtime %s from %s...\n' "$target_commit" "$remote"
git -C "$work" init -q source
git -C "$work/source" remote add origin "$remote"
git -C "$work/source" fetch -q --depth 1 origin "$target_commit"
git -C "$work/source" checkout -q --detach FETCH_HEAD
sha=$(git -C "$work/source" rev-parse HEAD)
[[ "$sha" == "$target_commit" ]] || fail "fetched commit mismatch: expected $target_commit, got $sha"
printf 'Host source commit: %s\n' "$sha"

nix --extra-experimental-features 'nix-command flakes' \
  build --no-link "path:$work/source#nixosConfigurations.inception-runtime.config.system.build.toplevel"

"$sudo_wrapper" -v
old_system=$(readlink -f /run/current-system)
if ! "$sudo_wrapper" /run/current-system/sw/bin/nixos-rebuild switch \
    --flake "path:$work/source#inception-runtime"; then
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
  printf 'Pinned host commit provides ABI %s, but submit requires %s. Rolling back.\n' "$new_abi" "$required_abi" >&2
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
