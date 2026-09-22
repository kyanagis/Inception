#!/usr/bin/env bash
set -euo pipefail

out="${1:-$HOME/inception-diagnostics-$(date -u +%Y%m%dT%H%M%SZ).txt}"
umask 077

{
  echo 'Inception safe diagnostics'
  echo '=========================='
  date -u
  uname -a
  cat /etc/os-release
  echo
  printf 'Virtualization: '
  systemd-detect-virt || true
  echo
  echo 'Interfaces:'
  ip -brief address || true
  echo
  echo 'Listeners:'
  ss -lntup || true
  echo
  docker version 2>&1 || true
  docker compose version 2>&1 || true
  docker info --format 'Root={{.DockerRootDir}} Driver={{.Driver}} Cgroup={{.CgroupVersion}} Security={{json .SecurityOptions}}' 2>&1 || true
  echo
  docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>&1 || true
  echo
  if [[ -r /var/lib/inception/environment ]]; then
    grep -E '^(INCEPTION_LOGIN|DOMAIN_NAME|INCEPTION_DATA_DIR)=' /var/lib/inception/environment
  fi
  repo="${INCEPTION_REPO_DIR:-/home/inception/Inception-submit}"
  if [[ -d "$repo/.git" ]]; then
    echo
    echo 'Repository:'
    git -C "$repo" remote -v | sed -E 's#(https?://)[^/@]+@#\1<redacted>@#g'
    git -C "$repo" log -1 --oneline
    git -C "$repo" status --short
  fi
} > "$out"

chmod 0600 "$out"
printf 'Wrote redacted diagnostics to %s\n' "$out"
