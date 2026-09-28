#!/usr/bin/env bash
# Builds the synced Docusaurus website against tests/docs-fixture, as a documented repository would.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail() { echo "FAIL: $*"; exit 1; }

cp -R "$root/tests/docs-fixture"/. "$work"
cp -R "$root/sync-docs"/. "$work"
rm -rf "$work/website/node_modules" "$work/website/build" "$work/website/.docusaurus"
cd "$work/website"
npm ci --no-audit --no-fund
GITHUB_REPOSITORY=curiosus-dev/Curiosus.Sample npm run build

page=build/packages/area/curiosus-sample.html
[[ -f build/index.html ]] || fail "no home page"
grep -q 'Fixture of a documented repository' build/index.html || fail "home page is not the symlinked README"
[[ -f "$page" ]] || fail "symlinked package README is not published"
grep -q 'Curiosus.Sample package' "$page" || fail "package page has no README content"
grep -q 'edit/main/src/Area/Curiosus.Sample/README.md' "$page" || fail "editUrl does not follow the symlink"
# The home page is a symlinked README without sidebar_position, it still goes before the positioned guide.
first_link="$(grep -oE 'class="menu__link[^"]*"[^>]*href="[^"]*"' build/guide.html | head -1)"
[[ "$first_link" == *'href="/Curiosus.Sample/"' ]] || fail "home page is not the first sidebar item: $first_link"

git -C "$work" init --quiet
git -C "$work" remote add origin git@github.com:curiosus-dev/Curiosus.Sample.git
GITHUB_REPOSITORY='' npx docusaurus build --out-dir build-local >/dev/null
grep -q '/Curiosus.Sample/' build-local/index.html || fail "repository is not resolved from the origin remote"

mv ../docs.json ../docs.json.bak
if GITHUB_REPOSITORY=curiosus-dev/Curiosus.Sample npx docusaurus build --out-dir build-missing >/dev/null 2>err.log; then
    fail "builds without docs.json"
fi
grep -q 'docs.json' err.log || fail "missing docs.json error does not name the file"

echo "docs build passed"
