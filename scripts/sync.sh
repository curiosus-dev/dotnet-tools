#!/usr/bin/env bash
# Copies ./sync into the repository in the current directory and opens a pull request with the changes.
# Repositories with "docs": true in settings/repositories.json also get ./sync-docs.
# Every run creates a fresh branch from the default one and closes older sync pull requests, so nothing is force-pushed.
#
# Environment:
#   GH_TOKEN          token with contents, pull-requests and workflows write access to the target repository
#   SOURCE_REPOSITORY owner/name of dotnet-tools, SOURCE_SHA - synced commit (both set by the workflow)
#   APP_SLUG          GitHub App slug used as the commit author
#   SYNC_REPOSITORY   repository name without the owner, defaults to the name of the origin remote
#   SYNC_DRY_RUN=1    only copy the files and show the resulting changes
set -euo pipefail

source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../sync" && pwd)"
source_repository="${SOURCE_REPOSITORY:-curiosus-dev/dotnet-tools}"
source_sha="${SOURCE_SHA:-$(git -C "$source_dir" rev-parse HEAD 2>/dev/null || echo local)}"
branch_prefix="chore/sync-dotnet-tools-"
branch="${branch_prefix}${source_sha:0:7}"
tools_dir="$(dirname "$source_dir")"
repository="${SYNC_REPOSITORY:-$(basename -s .git "$(git remote get-url origin 2>/dev/null || echo unknown)")}"

copy_shared_files() {
    cp -R "$source_dir"/. .
    if jq -e --arg name "$repository" '.repositories[$name].docs == true' \
        "$tools_dir/settings/repositories.json" >/dev/null; then
        cp -R "$tools_dir/sync-docs"/. .
    fi
}

if [[ "${SYNC_DRY_RUN:-}" == "1" ]]; then
    copy_shared_files
    git status --short
    exit 0
fi

default_branch="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)"
git fetch --quiet origin "$default_branch"
git switch --quiet -c "$branch" "origin/$default_branch"

copy_shared_files
git add -A

list_sync_pull_requests() {
    gh pr list --state open --json number,headRefName \
        --jq ".[] | select(.headRefName | startswith(\"$branch_prefix\")) | select(.headRefName != \"$branch\") | .number"
}

if git diff --cached --quiet; then
    echo "Shared files are up to date."
    for number in $(list_sync_pull_requests); do
        gh pr close "$number" --delete-branch --comment "Shared files are already up to date."
    done
    exit 0
fi

git diff --cached --stat

bot_login="${APP_SLUG}[bot]"
bot_id="$(gh api "/users/${bot_login}" --jq .id)"
git config user.name "$bot_login"
git config user.email "${bot_id}+${bot_login}@users.noreply.github.com"

source_url="https://github.com/${source_repository}/commit/${source_sha}"
git commit --quiet -m "Sync shared files from ${source_repository}@${source_sha:0:7}" -m "$source_url"
git push --quiet origin "$branch"

pr_url="$(gh pr create --base "$default_branch" --head "$branch" \
    --title "Sync shared files from dotnet-tools" \
    --body "Shared build, CI and editor files from ${source_url}.

Review the diff: files listed in \`.claude/curiosus.md\` are owned by ${source_repository}, change them there.")"
echo "Created $pr_url"

for number in $(list_sync_pull_requests); do
    gh pr close "$number" --delete-branch --comment "Superseded by $pr_url"
done
