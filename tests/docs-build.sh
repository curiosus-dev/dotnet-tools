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

# Search: local index by default.
compgen -G 'build/search-index*.json' >/dev/null || fail "no local search index"
grep -q 'DocSearch' build/index.html && fail "Algolia DocSearch is on without algolia in docs.json"

# Footer: cross links to the other Curiosus libraries, never to the current one or to dotnet-tools.
footer="$(grep -oE '<footer.*</footer>' build/index.html)"
[[ "$footer" == *'Libraries'* ]] || fail "footer has no Libraries column"
[[ "$footer" == *'https://curiosus-dev.github.io/Curiosus.Migrations/'* ]] || fail "footer has no Curiosus.Migrations link"
[[ "$footer" == *'https://github.com/curiosus-dev/Curiosus.TelegramBot'* ]] || fail "footer has no Curiosus.TelegramBot link"
[[ "$footer" != *'dotnet-tools'* ]] || fail "footer links to dotnet-tools"
GITHUB_REPOSITORY=curiosus-dev/Curiosus.Utils npx docusaurus build --out-dir build-utils >/dev/null
utils_footer="$(grep -oE '<footer.*</footer>' build-utils/index.html)"
[[ "$utils_footer" != *'https://curiosus-dev.github.io/Curiosus.Utils/'* ]] || fail "footer links to the current library"

# Algolia site verification alone adds the meta tag and keeps the local search.
cp ../docs.json ../docs.json.local
cat > ../docs.json <<'JSON'
{ "title": "Curiosus.Sample", "tagline": "Fixture", "algolia": { "siteVerification": "0123456789ABCDEF" } }
JSON
GITHUB_REPOSITORY=curiosus-dev/Curiosus.Sample npx docusaurus build --out-dir build-verify >/dev/null
grep -qE '<meta[^>]*name="algolia-site-verification"[^>]*content="0123456789ABCDEF"' build-verify/index.html \
    || fail "no algolia-site-verification meta tag"
compgen -G 'build-verify/search-index*.json' >/dev/null || fail "site verification alone turned the local search off"

# Search: Algolia DocSearch when docs.json has the keys.
cat > ../docs.json <<'JSON'
{ "title": "Curiosus.Sample", "tagline": "Fixture",
  "algolia": { "appId": "APPID", "apiKey": "search-only-key", "indexName": "curiosus-sample" } }
JSON
GITHUB_REPOSITORY=curiosus-dev/Curiosus.Sample npx docusaurus build --out-dir build-algolia >/dev/null
grep -q 'DocSearch' build-algolia/index.html || fail "Algolia DocSearch is off with algolia in docs.json"
compgen -G 'build-algolia/search-index*.json' >/dev/null && fail "local search index is built with Algolia on"
mv ../docs.json.local ../docs.json

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
