#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'inception-evaluate: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: inception-evaluate [MODE] [--repo DIR] [--no-update]

Modes:
  --prepare      Sync current submit and run its prepare contract (default)
  --mandatory    Run submit mandatory evaluation
  --bonus        Run submit bonus evaluation
  --full         Run mandatory then bonus evaluation
  --audit        Run submit audit contract
  --update-only  Sync current submit only

The appliance owns only the bootstrap contract. Project-specific evaluation
lives in submit/.inception/evaluate so future Makefile/internal changes do not
require rebuilding the OVA.
EOF
}

mode=prepare
repo_dir=${INCEPTION_REPO_DIR:-/home/inception/Inception-eval}
remote=${INCEPTION_REPO_URL:-https://github.com/kyanagis/Inception.git}
update=1

while (($#)); do
  case "$1" in
    --prepare) mode=prepare ;;
    --mandatory) mode=mandatory ;;
    --bonus) mode=bonus ;;
    --full) mode=full ;;
    --audit) mode=audit ;;
    --update-only) mode='update-only' ;;
    --no-update) update=0 ;;
    --repo)
      shift
      (($#)) || fail '--repo requires a directory'
      repo_dir=$1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
  shift
done

state=/var/lib/inception/environment
[[ -r "$state" ]] || fail '42 login is not configured; run inception-setup YOUR_LOGIN first'
set -a
# shellcheck disable=SC1090
. "$state"
set +a

[[ ${INCEPTION_LOGIN:-} =~ ^[a-z][a-z0-9-]{0,30}[a-z0-9]$|^[a-z]$ ]] ||
  fail 'invalid INCEPTION_LOGIN state'
[[ ${DOMAIN_NAME:-} == "$INCEPTION_LOGIN.42.fr" ]] ||
  fail 'DOMAIN_NAME does not match INCEPTION_LOGIN'
[[ ${INCEPTION_DATA_DIR:-} == "/home/$INCEPTION_LOGIN/data" ]] ||
  fail 'INCEPTION_DATA_DIR does not match INCEPTION_LOGIN'

if [[ -e "$repo_dir" && ! -d "$repo_dir/.git" ]]; then
  fail "$repo_dir exists but is not a Git worktree"
fi

if [[ ! -d "$repo_dir/.git" ]]; then
  mkdir -p "$(dirname "$repo_dir")"
  git clone --branch submit --single-branch "$remote" "$repo_dir"
elif ((update)); then
  git -C "$repo_dir" remote set-url origin "$remote"
  git -C "$repo_dir" fetch --prune origin refs/heads/submit:refs/remotes/origin/submit
  git -C "$repo_dir" checkout -B submit origin/submit >/dev/null
  git -C "$repo_dir" reset --hard origin/submit >/dev/null
  # The evaluator checkout is disposable, but generated credentials/state must
  # survive source updates. Remove other untracked files that could shadow a
  # newly tracked path while preserving runtime state.
  git -C "$repo_dir" clean -fdx -e secrets/ -e srcs/.env >/dev/null
fi

submit_sha=$(git -C "$repo_dir" rev-parse HEAD)
printf 'submit=%s\nrepo=%s\n' "$submit_sha" "$repo_dir"

host_abi_file="$repo_dir/.inception/host-abi"
host_contract="$repo_dir/.inception/host-contract.json"
if [[ -f "$host_abi_file" ]]; then
  required_abi=$(tr -d '[:space:]' < "$host_abi_file")
  [[ "$required_abi" =~ ^[0-9]+$ ]] || fail 'invalid submit host ABI declaration'

  host_commit=
  if [[ -f "$host_contract" ]]; then
    contract_abi=$(jq -er '.host_abi' "$host_contract") ||
      fail 'invalid submit host contract'
    [[ "$contract_abi" == "$required_abi" ]] ||
      fail 'submit host ABI differs from host contract'
    host_commit=$(jq -r '.host_source.commit // empty' "$host_contract")
    host_repository=$(jq -r '.host_source.repository // empty' "$host_contract")
    if [[ -n "$host_commit" || -n "$host_repository" ]]; then
      [[ "$host_repository" == https://github.com/kyanagis/Inception.git ]] ||
        fail 'submit host contract names an untrusted host source repository'
      [[ "$host_commit" =~ ^[0-9a-f]{40}$ ]] ||
        fail 'submit host contract does not pin an immutable host source commit'
    fi
  fi

  if [[ -n "$host_commit" ]]; then
    inception-host-update --ensure "$required_abi" "$host_commit"
  else
    # Legacy schema is accepted only when no update is necessary. The hardened
    # updater refuses an unpinned source if the installed ABI is too old.
    inception-host-update --ensure "$required_abi"
  fi
fi

declare -a missing=()
contract="$repo_dir/.inception/host-tools"
if [[ -f "$contract" ]]; then
  while IFS= read -r raw || [[ -n "$raw" ]]; do
    line=${raw%%#*}
    read -r command_name package_name extra <<<"$line"
    [[ -n ${command_name:-} ]] || continue
    [[ -n ${package_name:-} && -z ${extra:-} ]] ||
      fail "invalid host-tools row: $raw"
    [[ "$command_name" =~ ^[A-Za-z0-9._+-]+$ ]] ||
      fail "unsafe command identifier in host-tools: $command_name"
    [[ "$package_name" =~ ^[A-Za-z0-9._+-]+$ ]] ||
      fail "unsafe nixpkgs identifier in host-tools: $package_name"
    if ! command -v "$command_name" >/dev/null 2>&1; then
      missing+=("nixpkgs#$package_name")
    fi
  done < "$contract"
fi

run() {
  if (("${#missing[@]}" > 0)); then
    nix shell "${missing[@]}" --command "$@"
  else
    "$@"
  fi
}

if (("${#missing[@]}" > 0)); then
  printf 'Ephemeral host tools:'
  printf ' %s' "${missing[@]}"
  printf '\n'
fi

[[ "$mode" != update-only ]] || exit 0
[[ -f "$repo_dir/.inception/evaluate" ]] ||
  fail 'submit does not provide .inception/evaluate stable ABI'

cd "$repo_dir"
run sh ./.inception/evaluate "$mode"
printf 'inception-evaluate completed mode=%s submit=%s\n' "$mode" "$submit_sha"
