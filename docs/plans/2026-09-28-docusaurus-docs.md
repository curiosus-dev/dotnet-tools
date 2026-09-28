# Docusaurus documentation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace MkDocs/ReadTheDocs with Docusaurus sites on GitHub Pages for Curiosus.Migrations and Curiosus.Utils,
with the theme, content pipeline and workflow owned by dotnet-tools and distributed by sync.

**Architecture:** `dotnet-tools/sync-docs/` (a Docusaurus `website/` plus `.github/workflows/docs.yml`) is copied by
`scripts/sync.sh` into repositories flagged `"docs": true`. Before every build, `website/scripts/collect.mjs` assembles
`website/.generated/docs/` from the repository `docs/`, READMEs and extra pages listed in the repository's `docs.json`,
rewriting links; Docusaurus builds only that directory.

**Tech Stack:** Docusaurus 3.10 (classic preset, MDX), Node 24 (`node:test`, `fs.promises.glob`), bash + jq,
Python 3 (repo-settings), GitHub Actions (`actions/upload-pages-artifact`, `actions/deploy-pages`).

**Spec:** `docs/specs/2026-09-28-docusaurus-docs-design.md` (dotnet-tools worktree)

**Worktrees:** `Curiosus-Dev/.worktrees/docs/{dotnet-tools,Curiosus.Migrations,Curiosus.Utils}`, branch
`feat/docusaurus-docs` in each. Paths below are relative to the named worktree.

## Global Constraints

- Sites: `https://curiosus-dev.github.io/<repository>/`; `url`/`baseUrl` from `GITHUB_REPOSITORY`, locally from `git remote get-url origin`.
- `onBrokenLinks: 'throw'` and `markdown.hooks.onBrokenMarkdownLinks: 'throw'`.
- Brand colour `#c23926`; logo files come from `curiosus-dev/.github/branding`.
- Actions pinned by SHA via `scripts/pin-actions.sh`; only GitHub-owned actions are allowed (`settings/actions.json`).
- `docs.yml` is not a required check.
- Synced files start with the "Synced from https://github.com/curiosus-dev/dotnet-tools, do not edit in place." note.
- Shell: `shellcheck`-clean; lines ≤ 130 characters; LF endings.
- Commits: Conventional Commits, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Out of scope: versioning, search, custom domain, redirects from readthedocs, TelegramBot docs.

## Review Focus

1. `index` set in `docs.json` while `docs/index.md` exists → collect fails naming both files (not two pages on `/`).
2. Links inside fenced code blocks of a README stay unchanged (README examples contain `[..](..)`-like text).
3. Two sources mapping to the same generated path (`Curiosus.EMail` vs `Curiosus.Email.*` style case collisions) → collect fails.
4. `git@github.com:owner/repo.git` and `https://github.com/owner/repo` remotes both resolve to `owner/repo`.
5. A link to a published README with an anchor keeps the anchor; a relative image becomes a raw.githubusercontent URL.

Each has a test in Task 2.

---

### Task 1: sync.sh copies `sync-docs/` into documented repositories

**Files:**
- Modify: `scripts/sync.sh`, `.github/workflows/sync.yml`, `settings/repositories.json`
- Create: `sync-docs/.keep` (removed in Task 3), `tests/sync-test.sh`

**Interfaces:**
- Produces: `sync.sh` honours `SYNC_REPOSITORY` (repository name without owner); `repositories.json` field `docs: true`.

- [ ] **Step 1: Write the failing test** — `tests/sync-test.sh`:

```bash
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
[[ -e "$utils/.github/workflows/docs.yml" || -e "$utils/.keep" ]] || fail "Curiosus.Utils did not get sync-docs/"

bot="$(run_sync Curiosus.TelegramBot)"
[[ -f "$bot/build/curiosus.cake" ]] || fail "Curiosus.TelegramBot did not get sync/"
[[ ! -e "$bot/.github/workflows/docs.yml" && ! -e "$bot/.keep" ]] || fail "Curiosus.TelegramBot got sync-docs/"

override="$work/override"
git init --quiet "$override"
(cd "$override" && SYNC_REPOSITORY=Curiosus.Migrations SYNC_DRY_RUN=1 "$root/scripts/sync.sh" >/dev/null)
[[ -e "$override/.github/workflows/docs.yml" || -e "$override/.keep" ]] || fail "SYNC_REPOSITORY is ignored"

echo "sync tests passed"
```

- [ ] **Step 2: Run it, expect failure**

Run: `mkdir -p sync-docs && touch sync-docs/.keep && bash tests/sync-test.sh`
Expected: `FAIL: Curiosus.Utils did not get sync-docs/`

- [ ] **Step 3: Implement.** In `settings/repositories.json` add `"docs": true` to Curiosus.Migrations and
Curiosus.Utils (environments are added in Task 4). In `scripts/sync.sh` document `SYNC_REPOSITORY` in the header and
replace both `cp -R "$source_dir"/. .` lines with `copy_shared_files`, defined after `branch=...`:

```bash
tools_dir="$(dirname "$source_dir")"
repository="${SYNC_REPOSITORY:-$(basename -s .git "$(git remote get-url origin 2>/dev/null || echo unknown)")}"

# Documentation files go only to repositories with "docs": true in settings/repositories.json.
copy_shared_files() {
    cp -R "$source_dir"/. .
    if jq -e --arg name "$repository" '.repositories[$name].docs == true' \
        "$tools_dir/settings/repositories.json" >/dev/null; then
        cp -R "$tools_dir/sync-docs"/. .
    fi
}
```

In `.github/workflows/sync.yml` add `SYNC_REPOSITORY: ${{ matrix.repository }}` to the step `env`.

- [ ] **Step 4: Run the test and shellcheck**

Run: `bash tests/sync-test.sh && shellcheck scripts/*.sh tests/*.sh`
Expected: `sync tests passed`, no shellcheck output.

- [ ] **Step 5: Commit**

```bash
git add scripts/sync.sh .github/workflows/sync.yml settings/repositories.json sync-docs/.keep tests/sync-test.sh
git commit -m "feat(sync): copy sync-docs into repositories with docs enabled"
```

---

### Task 2: collect step

**Files:**
- Create: `sync-docs/website/scripts/collect.mjs`, `sync-docs/website/scripts/collect.test.mjs`

**Interfaces:**
- Produces (named exports of `collect.mjs`):
  - `parseRepository(remoteOrSlug: string): { owner: string, name: string }` — throws on anything else.
  - `resolveRepository(repoRoot: string): { owner, name }` — `GITHUB_REPOSITORY`, else `git remote get-url origin`.
  - `loadConfig(repoRoot: string): { title, tagline, index?: string, readmes: string[], pages: Record<string, {source, label?}> }` — throws `docs.json: ...`.
  - `pagePath(readme: string): string` — `src/DAL/Curiosus.DAL/README.md` → `packages/dal/curiosus-dal.md`.
  - `rewriteLinks(markdown: string, { source: string, target: string, repository: {owner,name}, published: Map<string,string> }): string` — `source`/`target` are repo-relative / docs-relative paths, `published` maps repo-relative source → docs-relative target.
  - `collect({ repoRoot, outDir, repository }): Promise<Map<string,string>>` — returns docs-relative target → repo-relative source (used for `editUrl`); also writes `outDir/../sources.json`.
- CLI: `node scripts/collect.mjs` collects `..` (repository root) into `.generated/docs`.

- [ ] **Step 1: Write the failing tests** — `collect.test.mjs`:

```js
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import { collect, loadConfig, pagePath, parseRepository, rewriteLinks } from './collect.mjs';

const repository = { owner: 'curiosus-dev', name: 'Curiosus.Utils' };

async function makeRepo(files) {
    const root = await mkdtemp(path.join(tmpdir(), 'collect-'));
    for (const [file, content] of Object.entries(files)) {
        await mkdir(path.dirname(path.join(root, file)), { recursive: true });
        await writeFile(path.join(root, file), content);
    }
    return root;
}

test('parseRepository accepts ssh, https and slug forms', () => {
    for (const input of ['git@github.com:curiosus-dev/Curiosus.Utils.git',
        'https://github.com/curiosus-dev/Curiosus.Utils', 'https://github.com/curiosus-dev/Curiosus.Utils.git',
        'curiosus-dev/Curiosus.Utils']) {
        assert.deepEqual(parseRepository(input), repository, input);
    }
    assert.throws(() => parseRepository('not a repo'), /repository/);
});

test('pagePath maps package READMEs under packages/', () => {
    assert.equal(pagePath('src/DAL/Curiosus.DAL/README.md'), 'packages/dal/curiosus-dal.md');
    assert.equal(pagePath('src/Curiosus.Migrations/README.md'), 'packages/curiosus-migrations.md');
});

test('loadConfig requires title and tagline', async () => {
    const missing = await makeRepo({});
    assert.throws(() => loadConfig(missing), /docs\.json/);
    const noTagline = await makeRepo({ 'docs.json': '{"title":"T"}' });
    assert.throws(() => loadConfig(noTagline), /tagline/);
    const ok = await makeRepo({ 'docs.json': '{"title":"T","tagline":"L"}' });
    assert.deepEqual(loadConfig(ok), { title: 'T', tagline: 'L', index: undefined, readmes: [], pages: {} });
});

test('rewriteLinks rewrites published, repository and image links, keeps code and absolute URLs', () => {
    const published = new Map([['src/DAL/Curiosus.DAL/README.md', 'packages/dal/curiosus-dal.md']]);
    const input = [
        '[dal](../../DAL/Curiosus.DAL/README.md#usage)',
        '[abs](https://github.com/curiosus-dev/Curiosus.Utils/blob/main/src/DAL/Curiosus.DAL/README.md)',
        '[file](../../../LICENSE)',
        '![logo](images/logo.png)',
        '[ext](https://example.com/x.md) [anchor](#top)',
        '```md',
        '[code](../../DAL/Curiosus.DAL/README.md)',
        '```',
    ].join('\n');
    const output = rewriteLinks(input, {
        source: 'src/Email/Curiosus.EMail/README.md', target: 'packages/email/curiosus-email.md',
        repository, published,
    });
    assert.equal(output, [
        '[dal](../dal/curiosus-dal.md#usage)',
        '[abs](../dal/curiosus-dal.md)',
        '[file](https://github.com/curiosus-dev/Curiosus.Utils/blob/main/LICENSE)',
        '![logo](https://raw.githubusercontent.com/curiosus-dev/Curiosus.Utils/main/src/Email/Curiosus.EMail/images/logo.png)',
        '[ext](https://example.com/x.md) [anchor](#top)',
        '```md',
        '[code](../../DAL/Curiosus.DAL/README.md)',
        '```',
    ].join('\n'));
});

test('collect assembles docs, index, readmes and pages', async () => {
    const root = await makeRepo({
        'docs.json': JSON.stringify({ title: 'T', tagline: 'L', index: 'README.md',
            readmes: ['src/**/README.md'],
            pages: { 'changelog/dal.md': { source: 'src/DAL/Curiosus.DAL/CHANGELOG.md', label: 'Curiosus.DAL' } } }),
        'README.md': '# Root\n\n[dal](src/DAL/Curiosus.DAL/README.md)\n',
        'docs/guides/a.md': '# A\n',
        'src/DAL/Curiosus.DAL/README.md': '# Curiosus.DAL\n',
        'src/DAL/Curiosus.DAL/CHANGELOG.md': '# Changelog\n',
    });
    const outDir = path.join(root, 'website/.generated/docs');
    const sources = await collect({ repoRoot: root, outDir, repository });

    assert.equal(await readFile(path.join(outDir, 'index.md'), 'utf8'),
        '---\nslug: /\n---\n\n# Root\n\n[dal](packages/dal/curiosus-dal.md)\n');
    assert.equal(await readFile(path.join(outDir, 'guides/a.md'), 'utf8'), '# A\n');
    assert.equal(await readFile(path.join(outDir, 'packages/dal/curiosus-dal.md'), 'utf8'), '# Curiosus.DAL\n');
    assert.deepEqual(JSON.parse(await readFile(path.join(outDir, 'packages/dal/_category_.json'), 'utf8')),
        { label: 'DAL' });
    assert.equal(await readFile(path.join(outDir, 'changelog/dal.md'), 'utf8'),
        '---\nsidebar_label: "Curiosus.DAL"\n---\n\n# Changelog\n');
    assert.equal(sources.get('packages/dal/curiosus-dal.md'), 'src/DAL/Curiosus.DAL/README.md');
    assert.equal(sources.get('guides/a.md'), 'docs/guides/a.md');
    await rm(root, { recursive: true });
});

test('collect fails on a duplicate home page', async () => {
    const root = await makeRepo({
        'docs.json': '{"title":"T","tagline":"L","index":"README.md"}',
        'README.md': '# Root\n', 'docs/index.md': '# Index\n',
    });
    await assert.rejects(collect({ repoRoot: root, outDir: path.join(root, 'out'), repository }),
        /README\.md.*docs\/index\.md/);
});

test('collect fails when two sources map to one page', async () => {
    const root = await makeRepo({
        'docs.json': '{"title":"T","tagline":"L","readmes":["src/**/README.md"]}',
        'src/Email/Curiosus.E.Mail/README.md': '# A\n', 'src/Email/Curiosus.E-Mail/README.md': '# B\n',
    });
    await assert.rejects(collect({ repoRoot: root, outDir: path.join(root, 'out'), repository }),
        /packages\/email\/curiosus-e-mail\.md/);
});
```

- [ ] **Step 2: Run, expect failure**

Run: `cd sync-docs/website && node --test scripts/`
Expected: FAIL, `Cannot find module .../collect.mjs`.

- [ ] **Step 3: Implement `collect.mjs`**

```js
// Synced from https://github.com/curiosus-dev/dotnet-tools, do not edit in place.
// Assembles .generated/docs from the repository docs/, the README files and the pages listed in docs.json.
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { cp, glob, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const posix = path.posix;

export function parseRepository(value) {
    const match = /^(?:(?:git@|https:\/\/)github\.com[:/])?([\w.-]+)\/([\w.-]+?)(?:\.git)?\/?$/.exec(value.trim());
    if (!match) throw new Error(`Cannot parse a GitHub repository from "${value}"`);
    return { owner: match[1], name: match[2] };
}

export function resolveRepository(repoRoot) {
    if (process.env.GITHUB_REPOSITORY) return parseRepository(process.env.GITHUB_REPOSITORY);
    const remote = execFileSync('git', ['-C', repoRoot, 'remote', 'get-url', 'origin'], { encoding: 'utf8' });
    return parseRepository(remote);
}

export function loadConfig(repoRoot) {
    const file = path.join(repoRoot, 'docs.json');
    if (!existsSync(file)) throw new Error(`docs.json: not found in ${repoRoot}`);
    const config = JSON.parse(readFileSync(file, 'utf8'));
    for (const key of ['title', 'tagline']) {
        if (typeof config[key] !== 'string' || !config[key]) throw new Error(`docs.json: "${key}" is required`);
    }
    return {
        title: config.title, tagline: config.tagline, index: config.index,
        readmes: config.readmes ?? [], pages: config.pages ?? {},
    };
}

const slug = (segment) => segment.toLowerCase().replace(/\./g, '-');

export function pagePath(readme) {
    const dirs = posix.dirname(readme).split('/').slice(1); // drop "src"
    return posix.join('packages', ...dirs.map(slug)) + '.md';
}

const LINK = /(!?)\[([^\]]*)\]\(([^)\s]+)((?:\s+"[^"]*")?)\)/g;

export function rewriteLinks(markdown, { source, target, repository, published }) {
    const { owner, name } = repository;
    const blob = new RegExp(`^https://github\\.com/${owner}/${name}/(?:blob|tree)/[^/]+/(.+)$`);
    const relativeTo = (file) => posix.relative(posix.dirname(target), file);
    const rewrite = (whole, bang, text, href, title) => {
        const [url, anchor] = href.split('#');
        const hash = anchor === undefined ? '' : `#${anchor}`;
        let repoPath;
        if (blob.test(url)) repoPath = blob.exec(url)[1];
        else if (url && !/^[a-z]+:/i.test(url) && !url.startsWith('/')) {
            repoPath = posix.normalize(posix.join(posix.dirname(source), url));
        } else return whole;
        if (published.has(repoPath)) return `${bang}[${text}](${relativeTo(published.get(repoPath))}${hash}${title})`;
        if (blob.test(url)) return whole;
        const base = bang ? `https://raw.githubusercontent.com/${owner}/${name}/main/`
            : `https://github.com/${owner}/${name}/blob/main/`;
        return `${bang}[${text}](${base}${repoPath}${hash}${title})`;
    };
    let fenced = false;
    return markdown.split('\n').map((line) => {
        if (/^\s*(```|~~~)/.test(line)) { fenced = !fenced; return line; }
        return fenced ? line : line.replace(LINK, rewrite);
    }).join('\n');
}

async function expand(repoRoot, patterns) {
    const files = new Set();
    for (const pattern of patterns) {
        for await (const file of glob(pattern, { cwd: repoRoot, exclude: (f) => f.includes('node_modules') })) {
            files.add(file.split(path.sep).join('/'));
        }
    }
    return [...files].sort();
}

const frontMatter = (fields) =>
    `---\n${Object.entries(fields).map(([k, v]) => `${k}: ${v}`).join('\n')}\n---\n\n`;

export async function collect({ repoRoot, outDir, repository }) {
    const config = loadConfig(repoRoot);
    const docsDir = path.join(repoRoot, 'docs');
    if (config.index && existsSync(path.join(docsDir, 'index.md'))) {
        throw new Error(`docs.json: "index" is ${config.index}, but docs/index.md exists too; keep one home page`);
    }

    const sources = new Map();
    const plan = []; // [source, target, front matter, is package README]
    const claim = (target, source) => {
        if (sources.has(target)) throw new Error(`${source} and ${sources.get(target)} both map to ${target}`);
        sources.set(target, source);
    };

    if (existsSync(docsDir)) {
        for (const file of await expand(docsDir, ['**/*'])) claim(file, `docs/${file}`);
    }
    if (config.index) plan.push([config.index, 'index.md', { slug: '/' }, false]);
    for (const readme of await expand(repoRoot, config.readmes)) plan.push([readme, pagePath(readme), null, true]);
    for (const [target, page] of Object.entries(config.pages)) {
        plan.push([page.source, target, page.label ? { sidebar_label: JSON.stringify(page.label) } : null, false]);
    }
    for (const [source, target] of plan) claim(target, source);
    const published = new Map(plan.map(([source, target]) => [source, target]));

    await rm(outDir, { recursive: true, force: true });
    await mkdir(outDir, { recursive: true });
    if (existsSync(docsDir)) await cp(docsDir, outDir, { recursive: true, dereference: true });

    const categories = new Map();
    for (const [source, target, fields, isPackage] of plan) {
        const text = await readFile(path.join(repoRoot, source), 'utf8');
        const body = rewriteLinks(text, { source, target, repository, published });
        await mkdir(path.dirname(path.join(outDir, target)), { recursive: true });
        await writeFile(path.join(outDir, target), (fields ? frontMatter(fields) : '') + body);
        if (isPackage && posix.dirname(target) !== 'packages') {
            categories.set(posix.dirname(target), posix.dirname(source).split('/').at(-2));
        }
    }
    for (const [dir, label] of categories) {
        await writeFile(path.join(outDir, dir, '_category_.json'), JSON.stringify({ label }, null, 2) + '\n');
    }
    await writeFile(path.join(outDir, '..', 'sources.json'), JSON.stringify(Object.fromEntries(sources), null, 2));
    return sources;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
    const website = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
    const repoRoot = path.dirname(website);
    await collect({ repoRoot, outDir: path.join(website, '.generated/docs'), repository: resolveRepository(repoRoot) });
}
```

- [ ] **Step 4: Run the tests**

Run: `cd sync-docs/website && node --test scripts/`
Expected: all 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add sync-docs/website/scripts
git commit -m "feat(docs): collect step for Docusaurus sites"
```

---

### Task 3: Docusaurus website and fixture build

**Files:**
- Create: `sync-docs/website/{package.json,package-lock.json,docusaurus.config.mjs,sidebars.mjs,.gitignore}`,
  `sync-docs/website/src/css/custom.css`, `sync-docs/website/static/img/{curiosus-logo.svg,curiosus-logo-128.png}`,
  `tests/docs-fixture/{docs.json,README.md,docs/guide.md,src/Area/Curiosus.Sample/README.md}`, `tests/docs-build.sh`
- Delete: `sync-docs/.keep`

**Interfaces:**
- Consumes: `loadConfig`, `resolveRepository` from Task 2; `.generated/docs` and `.generated/sources.json`.
- Produces: npm scripts `build`, `start`, `serve`, `test`, `collect`.

- [ ] **Step 1: Write the failing fixture build** — `tests/docs-build.sh`:

```bash
#!/usr/bin/env bash
# Builds the synced Docusaurus website against tests/docs-fixture, as a documented repository would.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cp -R "$root/tests/docs-fixture"/. "$work"
cp -R "$root/sync-docs"/. "$work"
rm -rf "$work/website/node_modules"
cd "$work/website"
npm ci --no-audit --no-fund
npm test
GITHUB_REPOSITORY=curiosus-dev/Curiosus.Sample npm run build
test -f build/index.html
test -f build/packages/area/curiosus-sample/index.html
grep -q 'href="/Curiosus.Sample/guide"' build/index.html
echo "docs build passed"
```

Fixture content: `docs.json` = `{"title":"Curiosus.Sample","tagline":"Fixture","index":"README.md","readmes":["src/**/README.md"]}`;
`README.md` = `# Curiosus.Sample` + links `[Guide](docs/guide.md)` and `[Package](src/Area/Curiosus.Sample/README.md)`;
`docs/guide.md` = `# Guide` + a ```csharp block; package README = `# Curiosus.Sample package` +
`[Back](../../../README.md)`.

Run: `bash tests/docs-build.sh` — Expected: FAIL (`npm ci` without package.json).

- [ ] **Step 2: Create `package.json`**, then run `npm install` in `sync-docs/website` to create the lockfile:

```json
{
  "name": "curiosus-docs",
  "private": true,
  "type": "module",
  "engines": { "node": ">=24" },
  "scripts": {
    "collect": "node scripts/collect.mjs",
    "start": "node scripts/collect.mjs && docusaurus start",
    "build": "node scripts/collect.mjs && docusaurus build",
    "serve": "docusaurus serve",
    "clear": "docusaurus clear",
    "test": "node --test scripts/"
  },
  "dependencies": {
    "@docusaurus/core": "3.10.2",
    "@docusaurus/preset-classic": "3.10.2",
    "@mdx-js/react": "^3.1.0",
    "clsx": "^2.1.1",
    "prism-react-renderer": "^2.4.1",
    "react": "^19.0.0",
    "react-dom": "^19.0.0"
  }
}
```

- [ ] **Step 3: `docusaurus.config.mjs`**

```js
// Synced from https://github.com/curiosus-dev/dotnet-tools, do not edit in place.
// Repository specifics come from docs.json in the repository root.
import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { themes as prismThemes } from 'prism-react-renderer';
import { loadConfig, resolveRepository } from './scripts/collect.mjs';

const website = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.dirname(website);
const site = loadConfig(repoRoot);
const { owner, name } = resolveRepository(repoRoot);
const repositoryUrl = `https://github.com/${owner}/${name}`;
const sourcesFile = path.join(website, '.generated/sources.json');
const sources = () => (existsSync(sourcesFile) ? JSON.parse(readFileSync(sourcesFile, 'utf8')) : {});

export default {
    title: site.title,
    tagline: site.tagline,
    favicon: 'img/curiosus-logo-128.png',
    url: `https://${owner}.github.io`,
    baseUrl: `/${name}/`,
    organizationName: owner,
    projectName: name,
    trailingSlash: false,
    onBrokenLinks: 'throw',
    onBrokenAnchors: 'warn',
    markdown: { hooks: { onBrokenMarkdownLinks: 'throw' } },
    i18n: { defaultLocale: 'en', locales: ['en'] },
    presets: [[
        'classic',
        {
            docs: {
                path: '.generated/docs',
                routeBasePath: '/',
                sidebarPath: './sidebars.mjs',
                editUrl: ({ docPath }) => `${repositoryUrl}/edit/main/${sources()[docPath] ?? `docs/${docPath}`}`,
            },
            blog: false,
            theme: { customCss: './src/css/custom.css' },
        },
    ]],
    themeConfig: {
        colorMode: { respectPrefersColorScheme: true },
        navbar: {
            title: site.title,
            logo: { alt: 'Curiosus', src: 'img/curiosus-logo.svg' },
            items: [
                { href: 'https://www.nuget.org/profiles/curiosus-dev', label: 'NuGet', position: 'right' },
                { href: repositoryUrl, label: 'GitHub', position: 'right' },
            ],
        },
        footer: {
            style: 'dark',
            links: [{
                title: 'Curiosus',
                items: [
                    { label: 'GitHub', href: `https://github.com/${owner}` },
                    { label: 'NuGet', href: 'https://www.nuget.org/profiles/curiosus-dev' },
                    { label: 'dotnet-tools', href: `https://github.com/${owner}/dotnet-tools` },
                ],
            }],
            copyright: `© ${new Date().getFullYear()} Curiosus contributors`,
        },
        prism: {
            theme: prismThemes.github,
            darkTheme: prismThemes.dracula,
            additionalLanguages: ['csharp', 'sql', 'bash', 'powershell', 'json'],
        },
    },
};
```

`sidebars.mjs`: `export default { docs: [{ type: 'autogenerated', dirName: '.' }] };` with the synced note.

`.gitignore`: `node_modules/`, `build/`, `.generated/`, `.docusaurus/`.

`src/css/custom.css` (synced note as a `/* */` comment):

```css
:root {
    --ifm-color-primary: #c23926;
    --ifm-color-primary-dark: #af3322;
    --ifm-color-primary-darker: #a53020;
    --ifm-color-primary-darkest: #88281b;
    --ifm-color-primary-light: #d54130;
    --ifm-color-primary-lighter: #d74a3a;
    --ifm-color-primary-lightest: #de6a5d;
    --ifm-code-font-size: 95%;
    --docusaurus-highlighted-code-line-bg: rgba(0, 0, 0, 0.1);
}

[data-theme='dark'] {
    --ifm-color-primary: #e0604f;
    --ifm-color-primary-dark: #dc4b38;
    --ifm-color-primary-darker: #da412d;
    --ifm-color-primary-darkest: #bd3322;
    --ifm-color-primary-light: #e47566;
    --ifm-color-primary-lighter: #e67f71;
    --ifm-color-primary-lightest: #ec9e94;
    --docusaurus-highlighted-code-line-bg: rgba(0, 0, 0, 0.3);
}
```

Static images: copy `curiosus-logo.svg` and `curiosus-logo-128.png` from `Curiosus-Dev/.github/branding/`.

- [ ] **Step 4: Run the fixture build**

Run: `rm sync-docs/.keep && bash tests/docs-build.sh`
Expected: `docs build passed`. Then `bash tests/sync-test.sh` — update its `docs.yml || .keep` checks to
`$dir/website/docusaurus.config.mjs` and re-run; expected `sync tests passed`.

- [ ] **Step 5: Commit**

```bash
git add sync-docs tests
git commit -m "feat(docs): shared Docusaurus website"
```

---

### Task 4: docs workflow, Pages settings, lint and dependabot

**Files:**
- Create: `sync-docs/.github/workflows/docs.yml`
- Modify: `scripts/pin-actions.sh`, `.github/workflows/lint.yml`, `.github/dependabot.yml`,
  `settings/environments.json`, `settings/repositories.json`, `scripts/repo-settings.py`

**Interfaces:**
- Consumes: npm scripts `test`, `build` (Task 3).
- Produces: workflow `Docs` with jobs `build`, `deploy`.

- [ ] **Step 1: `docs.yml`**

```yaml
# Synced from https://github.com/curiosus-dev/dotnet-tools, do not edit in place.
#
# Builds the Docusaurus site from docs/, README files and docs.json; deploys it to GitHub Pages from main.

name: Docs

on:
  push:
    branches: [ main ]
    paths: [ 'docs/**', 'website/**', 'docs.json', '**/README.md', '**/CHANGELOG.md', '.github/workflows/docs.yml' ]
  pull_request:
    paths: [ 'docs/**', 'website/**', 'docs.json', '**/README.md', '**/CHANGELOG.md', '.github/workflows/docs.yml' ]
  workflow_dispatch:

concurrency:
  group: docs-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}

permissions:
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: website

    steps:
      - uses: actions/checkout@v6
      - uses: actions/setup-node@v6
        with:
          node-version: 24
          cache: npm
          cache-dependency-path: website/package-lock.json
      - run: npm ci --no-audit --no-fund
      - run: npm test
      - run: npm run build
      - if: github.event_name != 'pull_request' && github.ref_name == 'main'
        uses: actions/upload-pages-artifact@v4
        with:
          path: website/build

  deploy:
    needs: build
    if: github.event_name != 'pull_request' && github.ref_name == 'main'
    runs-on: ubuntu-latest
    permissions:
      pages: write
      id-token: write
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}

    steps:
      - id: deployment
        uses: actions/deploy-pages@v4
```

Note `CHANGELOG.md` in the paths: changelogs are published pages in Migrations.

- [ ] **Step 2: Pin actions.** Change the default file list in `scripts/pin-actions.sh` to
`.github/workflows/*.yml sync/.github/workflows/*.yml sync-docs/.github/workflows/*.yml`, then run
`scripts/pin-actions.sh sync-docs/.github/workflows/docs.yml`. Checkout must end up on the same SHA as in
`sync/.github/workflows/build.yml` (v7.0.1 there — use `@v7` if that is the current major). If a major has no release,
the script exits with `no releases for major version N`: check `gh release list -R actions/<name>` and fix the tag.

- [ ] **Step 3: Lint.** In `.github/workflows/lint.yml` add `sync-docs/.github/workflows/*.yml` to actionlint, extend
"Lint scripts" with `shellcheck tests/*.sh` and `bash tests/sync-test.sh`, and add a step after it:

```yaml
      - uses: actions/setup-node@v6
        with:
          node-version: 24
          cache: npm
          cache-dependency-path: sync-docs/website/package-lock.json
      - name: Build the docs fixture
        run: bash tests/docs-build.sh
```

Pin it with `scripts/pin-actions.sh .github/workflows/lint.yml`. Run locally:
`actionlint .github/workflows/*.yml sync/.github/workflows/*.yml sync-docs/.github/workflows/*.yml` (install with
`brew install actionlint` if missing). Expected: no output.

- [ ] **Step 4: Dependabot.** Append to `.github/dependabot.yml` and adjust its header comment:

```yaml
  - package-ecosystem: npm
    directory: /sync-docs/website
    schedule:
      interval: weekly
    groups:
      docusaurus:
        patterns: [ "@docusaurus/*", "react", "react-dom", "@mdx-js/*", "prism-react-renderer", "clsx" ]
```

- [ ] **Step 5: Pages settings.** `settings/environments.json`: add

```json
  "github-pages": {
    "deployment_branch_policy": { "protected_branches": false, "custom_branch_policies": true },
    "branch_policies": [ { "name": "main", "type": "branch" } ]
  }
```

`settings/repositories.json`: `"environments": [ "nuget", "github-pages" ]` for Curiosus.Migrations and Curiosus.Utils.
`scripts/repo-settings.py`, in `process()` before the environments loop (Pages creates `github-pages` itself, so it goes
first):

```python
    if config.get('docs'):
        pages = {'build_type': 'workflow'}
        actual_pages = gh('GET', f'{repo}/pages', allow_missing=True)
        if actual_pages is None:
            diffs.append('pages: disabled')
            if apply:
                gh('POST', f'{repo}/pages', pages)
        else:
            section('pages', pages, actual_pages, lambda: gh('PUT', f'{repo}/pages', pages))
```

Run: `python3 -m py_compile scripts/repo-settings.py && scripts/repo-settings.py check Curiosus.Migrations`
Expected: compiles; check reports `pages: disabled` and `environment github-pages: missing` (drift until applied).
**Do not run `apply`** — the maintainer applies settings after merge.

- [ ] **Step 6: Commit**

```bash
git add sync-docs/.github scripts .github settings
git commit -m "feat(docs): docs workflow and GitHub Pages settings"
```

---

### Task 5: dotnet-tools documentation

**Files:**
- Modify: `README.md`, `sync/.claude/curiosus.md`

- [ ] **Step 1:** `README.md`: describe `sync-docs/` (copied to repositories with `"docs": true`), `docs.json` fields
(table from the spec), local preview (`cd website && npm ci && npm start`), `tests/` scripts, and that Pages settings
come from `repo-settings.py`.
- [ ] **Step 2:** `sync/.claude/curiosus.md`: Stack line → "Documentation: `README.md` files; larger libraries also
have Docusaurus sites on GitHub Pages (`https://curiosus-dev.github.io/<repository>/`) built from `docs/`, READMEs and
`docs.json`". README section, badges item 2 → "documentation link when there is a docs site". Shared files list: add
"`website/` and `.github/workflows/docs.yml` (repositories with a docs site)". Add a short "Documentation" paragraph:
edit `docs/` and READMEs, never `website/`; preview with `npm start` in `website/`; sources must compile as MDX
(close HTML tags, no bare `{`/`<` in text).
- [ ] **Step 3: Commit** — `git commit -am "docs: document the shared Docusaurus sites"`

---

### Task 6: Curiosus.Migrations content (Migrations worktree)

**Files:**
- Create: `docs.json`, `docs/features/_category_.json`, `docs/features/script_migration/_category_.json`,
  `docs/features/code_migration/_category_.json`, `docs/changelog/_category_.json`
- Modify: every `docs/**/*.md` (front matter), `docs/basics.md` (admonition), `README.md`, `CLAUDE.md`,
  `src/*/README.md`, `src/*/*.csproj` (`PackageProjectUrl`)
- Delete: `mkdocs.yml`, `.readthedocs.yaml`, `docs/requirements.txt`, `docs/stylesheets/`,
  `docs/images/curiosus-logo-128.png`, `docs/images/curiosus-logo-512.png`, `docs/changelog/*.md` (broken symlinks)

- [ ] **Step 1: Copy the synced files for local builds:**
`SYNC_REPOSITORY=Curiosus.Migrations SYNC_DRY_RUN=1 ../dotnet-tools/scripts/sync.sh`.
They are not committed here (they arrive with the sync PR): stage only the paths listed in the commit step, and after
the commit drop the copies with `git clean -fd website .github/workflows/docs.yml && git checkout -- .`.

- [ ] **Step 2: `docs.json`**

```json
{
  "title": "Curiosus.Migrations",
  "tagline": "Database migrations for .NET: SQL scripts and C# code, downgrades, long-running migrations, policies",
  "pages": {
    "changelog/curiosus-migrations.md": { "source": "src/Curiosus.Migrations/CHANGELOG.md", "label": "Curiosus.Migrations" },
    "changelog/curiosus-migrations-postgresql.md": { "source": "src/Curiosus.Migrations.PostgreSQL/CHANGELOG.md", "label": "Curiosus.Migrations.PostgreSQL" },
    "changelog/curiosus-migrations-sqlserver.md": { "source": "src/Curiosus.Migrations.SqlServer/CHANGELOG.md", "label": "Curiosus.Migrations.SqlServer" },
    "changelog/curiosus-migrations-utils.md": { "source": "src/Curiosus.Migrations.Utils/CHANGELOG.md", "label": "Curiosus.Migrations.Utils" }
  }
}
```

- [ ] **Step 3: Order from the old `mkdocs.yml` nav.** Front matter `sidebar_position` (and `sidebar_label` where the
nav label differs from the H1):

| File | position | label |
|---|---|---|
| index.md | 1 | Intro |
| quickstart.md | 2 | Quick Start |
| philosophy.md | 3 | Philosophy |
| basics.md | 4 | Basics |
| supported_databases.md | 5 | Supported Databases |
| features/script_migration/index.md | 1 | What is it |
| features/script_migration/batches.md | 2 | Batches |
| features/code_migration/index.md | 1 | What is it |
| features/code_migration/ef_integration.md | 2 | EntityFramework Integration |
| features/code_migration/di.md | 3 | Dependency Injection |
| features/migration_providers.md … dependencies.md | 3–10 in nav order: migration_providers, variables, transactions, pre_migrations, logging, journal, downgrade, dependencies | nav labels |

`_category_.json`: features `{"label":"Features","position":6}`, script_migration `{"label":"Script Migration","position":1}`,
code_migration `{"label":"Code Migration","position":2}`, changelog `{"label":"Changelogs","position":7}`.

Add front matter as the first lines, e.g. `---\nsidebar_position: 2\nsidebar_label: Quick Start\n---\n\n`.

- [ ] **Step 4:** `docs/basics.md:216`: `!!! note` + indented body → `:::note` / body unindented / `:::`.
- [ ] **Step 5: Build and fix MDX errors.**

Run: `cd website && npm ci && npm run build`
Expected at first: MDX errors in `index.md` and `supported_databases.md` (HTML). Fix the sources, not the pipeline,
so they stay valid for both MDX and GitHub: prefer Markdown equivalents (a Markdown table instead of `<table>`,
`![PostgreSQL](images/postgresql.png)` instead of `<img src=...>`); where HTML has to stay, self-close void tags
(`<br />`, `<img ... />`) and drop `style="..."` attributes (MDX rejects string styles); put bare `{`/`<` in text into
backticks. Re-run until `[SUCCESS]` with no broken links.

- [ ] **Step 6: Links to the new site.** Replace `https://curiosity-migrations.readthedocs.io/en/latest/<path>/` with
`https://curiosus-dev.github.io/Curiosus.Migrations/<path>` (no trailing slash, `trailingSlash: false`) and the bare
root URL with `https://curiosus-dev.github.io/Curiosus.Migrations/` in `README.md`, `src/*/README.md`,
`src/*/*.csproj`, `CLAUDE.md`:

```bash
grep -rlI 'curiosity-migrations.readthedocs.io' README.md CLAUDE.md src | xargs sed -i '' -E \
  -e 's#https://curiosity-migrations\.readthedocs\.io/en/latest/([^)#" ]*[^/)#" ])/?#https://curiosus-dev.github.io/Curiosus.Migrations/\1#g' \
  -e 's#https://curiosity-migrations\.readthedocs\.io/?#https://curiosus-dev.github.io/Curiosus.Migrations/#g'
```

README badge line 9 → `[![Documentation](https://img.shields.io/badge/docs-GitHub%20Pages-c23926)](https://curiosus-dev.github.io/Curiosus.Migrations/)`.
`CLAUDE.md` line 11 → "Documentation (Docusaurus, GitHub Pages) lives in `docs/`, site settings in `docs.json`;
published at https://curiosus-dev.github.io/Curiosus.Migrations/. `website/` is synced from dotnet-tools."
Verify every rewritten URL path exists: after `npm run build`, for each URL in
`grep -rhoI 'curiosus-dev.github.io/Curiosus.Migrations/[^)#" ]*' README.md src` check `website/build/<path>/index.html`
(or `<path>.html`) exists. Expected: all exist.

- [ ] **Step 7: Remove MkDocs:** `git rm -r mkdocs.yml .readthedocs.yaml docs/requirements.txt docs/stylesheets docs/images/curiosus-logo-128.png docs/images/curiosus-logo-512.png docs/changelog/*.md`,
re-run `npm run build`, expected success. `npm run serve` and look at `/`, `/features/downgrade`, `/changelog/curiosus-migrations`.
- [ ] **Step 8: Commit** only content (not synced files):

```bash
git add docs.json docs README.md CLAUDE.md src
git commit -m "docs: move documentation to Docusaurus on GitHub Pages"
```

Then drop the synced copies (Step 1) and confirm `git status` is clean.

---

### Task 7: Curiosus.Utils content (Utils worktree)

**Files:**
- Create: `docs.json`, `docs/notifications/_category_.json`
- Move: `docs/Notiifications/*` → `docs/notifications/*`
- Modify: `README.md`, `CLAUDE.md`, `src/Notifications/*/README.md`
- Delete: `mkdocs.yml`, `.readthedocs.yml`, `requirements.txt`, `docs/index.md` (the home page is `README.md`)

- [ ] **Step 1:** dry-run sync as in Task 6 Step 1 with `SYNC_REPOSITORY=Curiosus.Utils`.
- [ ] **Step 2: `docs.json`**

```json
{
  "title": "Curiosus.Utils",
  "tagline": "Building blocks for .NET services: hosting, configuration, data access, e-mail and SMS, notifications",
  "index": "README.md",
  "readmes": [ "src/**/README.md" ]
}
```

- [ ] **Step 3:** `git mv docs/Notiifications docs/notifications-tmp && git mv docs/notifications-tmp docs/notifications`
(two steps for case-insensitive file systems); `docs/notifications/_category_.json` = `{"label":"Notifications guide","position":2}`.
Before deleting `docs/index.md`, move anything it has that `README.md` lacks into `README.md`; then `git rm docs/index.md`.
- [ ] **Step 4: Build and fix MDX errors** (`cd website && npm ci && npm run build`), same rules as Task 6 Step 5;
expected offenders: `src/Email/*/README.md`, `src/Notifications/Curiosus.Notifications.EMail/README.md`. These are
NuGet readmes: keep them valid Markdown/HTML for nuget.org (self-closed tags and Markdown tables are fine there).
- [ ] **Step 5: Links.** `README.md`: badge → `[![Documentation](https://img.shields.io/badge/docs-GitHub%20Pages-c23926)](https://curiosus-dev.github.io/Curiosus.Utils/)`,
line 90 → `Full documentation: [curiosus-dev.github.io/Curiosus.Utils](https://curiosus-dev.github.io/Curiosus.Utils/).`
Notification READMEs: `https://curiosityutils.readthedocs.io/en/latest/Notiifications/sms/` →
`https://curiosus-dev.github.io/Curiosus.Utils/notifications/sms`, `.../emails/` → `.../notifications/emails`,
`.../Notiifications/` → `.../notifications`. `CLAUDE.md` line 51 → Docusaurus on GitHub Pages, `docs.json`, synced `website/`.
Verify each URL against `website/build` as in Task 6 Step 6.
- [ ] **Step 6: Remove MkDocs:** `git rm mkdocs.yml .readthedocs.yml requirements.txt`; build again; `npm run serve`
and look at `/`, `/packages/dal/curiosus-dal`, `/notifications/emails`; check the sidebar groups packages by area.
- [ ] **Step 7: Commit** content only, then drop the synced copies (Task 6 Step 1) and confirm `git status` is clean:

```bash
git add docs.json docs README.md CLAUDE.md src
git commit -m "docs: move documentation to Docusaurus on GitHub Pages"
```

---

### Task 8: Pull requests

- [ ] **Step 1:** dotnet-tools: `bash tests/sync-test.sh && bash tests/docs-build.sh`, then
`git push -u origin feat/docusaurus-docs` and `gh pr create --base main --title "feat(docs): shared Docusaurus sites on GitHub Pages"`,
body: summary, the manual steps below, the Claude Code footer.
- [ ] **Step 2:** Migrations and Utils: push and open `docs: move documentation to Docusaurus on GitHub Pages`, body
noting that the site builds once the dotnet-tools sync PR is merged.
- [ ] **Step 3:** Report manual steps to the maintainer: merge dotnet-tools → merge the sync PRs → run
`scripts/repo-settings.py apply Curiosus.Migrations Curiosus.Utils` → merge content PRs → check the Pages sites →
disable the ReadTheDocs projects.
