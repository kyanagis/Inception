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
  --prepare      Fetch current submit and run configure/doctor/check (default)
  --mandatory    Prepare, build/start mandatory stack, run test and audit
  --bonus        Prepare, start full bonus stack, run bonus-test and audit
  --full         Run mandatory validation, then bonus validation
  --audit        Prepare and run the hypothesis-driven audit
  --update-only  Fetch/fast-forward current submit only

The appliance is not tied to a submit commit.  Missing ordinary host commands
declared in .inception/host-tools are supplied through an ephemeral Nix shell.
EOF
}

mode=prepare
repo_dir=${INCEPTION_REPO_DIR:-/home/inception/Inception-submit}
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
  mapfile -t changed < <(
    {
      git -C "$repo_dir" diff --name-only
      git -C "$repo_dir" diff --cached --name-only
    } | sort -u
  )
  if (("${#changed[@]}" > 0)); then
    if (("${#changed[@]}" == 1)) && [[ "${changed[0]}" == srcs/.env ]]; then
      # make configure materializes evaluator-specific state in the tracked
      # template. This checkout is disposable, so restore only that generated
      # file before pulling the next submit revision.
      git -C "$repo_dir" restore --staged --worktree -- srcs/.env
    else
      printf 'Tracked changes exist in evaluation checkout:\n' >&2
      printf '  %s\n' "${changed[@]}" >&2
      fail 'refusing to overwrite changes other than generated srcs/.env'
    fi
  fi
  git -C "$repo_dir" fetch --prune origin refs/heads/submit:refs/remotes/origin/submit
  if git -C "$repo_dir" show-ref --verify --quiet refs/heads/submit; then
    git -C "$repo_dir" switch submit >/dev/null
  else
    git -C "$repo_dir" switch --create submit --track origin/submit >/dev/null
  fi
  git -C "$repo_dir" merge-base --is-ancestor HEAD origin/submit ||
    fail 'local submit contains commits not present in origin/submit; refusing to rewrite it'
  git -C "$repo_dir" merge --ff-only origin/submit >/dev/null
fi

submit_sha=$(git -C "$repo_dir" rev-parse HEAD)
printf 'submit=%s\nrepo=%s\n' "$submit_sha" "$repo_dir"

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

run make -C "$repo_dir" configure LOGIN="$INCEPTION_LOGIN"
run make -C "$repo_dir" doctor
run make -C "$repo_dir" check

case "$mode" in
  prepare)
    ;;
  mandatory)
    run make -C "$repo_dir" up
    run make -C "$repo_dir" test
    run make -C "$repo_dir" audit
    ;;
  bonus)
    run make -C "$repo_dir" bonus
    run make -C "$repo_dir" bonus-test
    run make -C "$repo_dir" audit
    ;;
  full)
    run make -C "$repo_dir" up
    run make -C "$repo_dir" test
    run make -C "$repo_dir" audit
    run make -C "$repo_dir" bonus
    run make -C "$repo_dir" bonus-test
    run make -C "$repo_dir" audit
    ;;
  audit)
    run make -C "$repo_dir" audit
    ;;
esac

printf 'inception-evaluate completed mode=%s submit=%s\n' "$mode" "$submit_sha"
