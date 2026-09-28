#!/usr/bin/env bash
# Dry-runs scripts/sync.sh in throwaway repositories and checks which shared files each one gets.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

run_sync() {
    local name="$1" dir="$work/$1"
    git init --quiet "$dir"
    git -C "$dir" remote add origin "git@github.com:curiosus-dev/$name.git"
    (cd "$dir" && SYNC_DRY_RUN=1 "$root/scripts/sync.sh" >/dev/null)
    echo "$dir"
}

fail() { echo "FAIL: $*"; exit 1; }

utils="$(run_sync Curiosus.Utils)"
[[ -f "$utils/build/curiosus.cake" ]] || fail "Curiosus.Utils did not get sync/"
[[ -e "$utils/.keep" ]] || fail "Curiosus.Utils did not get sync-docs/"

bot="$(run_sync Curiosus.TelegramBot)"
[[ -f "$bot/build/curiosus.cake" ]] || fail "Curiosus.TelegramBot did not get sync/"
[[ ! -e "$bot/.keep" ]] || fail "Curiosus.TelegramBot got sync-docs/"

override="$work/override"
git init --quiet "$override"
(cd "$override" && SYNC_REPOSITORY=Curiosus.Migrations SYNC_DRY_RUN=1 "$root/scripts/sync.sh" >/dev/null)
[[ -e "$override/.keep" ]] || fail "SYNC_REPOSITORY is ignored"

echo "sync tests passed"
