# Docusaurus documentation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace MkDocs/ReadTheDocs with Docusaurus sites on GitHub Pages for Curiosus.Migrations and Curiosus.Utils,
with the theme and workflow owned by dotnet-tools and distributed by sync.

**Architecture:** `dotnet-tools/sync-docs/` (a Docusaurus `website/` plus `.github/workflows/docs.yml`) is copied by
`scripts/sync.sh` into repositories flagged `"docs": true`. Docusaurus reads the repository `docs/` directly; READMEs
and CHANGELOGs are published through relative symlinks committed in `docs/`. `docs.json` holds the title and tagline.

**Tech Stack:** Docusaurus 3.10 (classic preset, MDX), Node 24, bash + jq, Python 3 (repo-settings), GitHub Actions.

**Spec:** `docs/specs/2026-09-28-docusaurus-docs-design.md`

**Worktrees:** `Curiosus-Dev/.worktrees/docs/{dotnet-tools,Curiosus.Migrations,Curiosus.Utils}`, branch
`feat/docusaurus-docs` in each. Paths are relative to the named worktree.

## Global Constraints

- Sites: `https://curiosus-dev.github.io/<repository>/`; owner/name from `GITHUB_REPOSITORY`, locally from the origin remote.
- `onBrokenLinks: 'throw'` and `markdown.hooks.onBrokenMarkdownLinks: 'throw'`.
- Brand colour `#c23926`; logo files from `curiosus-dev/.github/branding`.
- Actions pinned by SHA via `scripts/pin-actions.sh`; only GitHub-owned actions are allowed.
- `docs.yml` is not a required check.
- Symlinks are relative and committed; symlinked files get no front matter.
- Synced files start with the "Synced from https://github.com/curiosus-dev/dotnet-tools, do not edit in place." note.
- `shellcheck`-clean shell; lines ≤ 130 characters; Conventional Commits with the Claude co-author line.
- Out of scope: versioning, search, custom domain, readthedocs redirects, TelegramBot docs.

## Review Focus

1. Symlinks to files outside `docs/` (root README, `src/**`) build and are served under the docs routes.
2. A relative link inside a symlinked README fails the build instead of producing a dead link.
3. `editUrl` of a symlinked page points to the real file (`src/.../README.md`).
4. ssh and https origin remotes both resolve to `owner/repo`.
5. A missing `docs.json` or field fails with a message naming `docs.json`.

1, 3, 4, 5: `tests/docs-build.sh` (Task 3). 2: manual check in Task 3.

---

### Task 1: sync.sh copies `sync-docs/` — DONE (53a6757)

### Task 2: collect step — CANCELLED (reverted in 3b5f04c; content is published by symlinks)

---

### Task 3: Docusaurus website and fixture build (dotnet-tools)

**Files:**
- Create: `sync-docs/website/{package.json,package-lock.json,docusaurus.config.mjs,sidebars.mjs,.gitignore}`,
  `sync-docs/website/src/css/custom.css`, `sync-docs/website/static/img/{curiosus-logo.svg,curiosus-logo-128.png}`,
  `tests/docs-fixture/`, `tests/docs-build.sh`
- Modify: `tests/sync-test.sh` (check `website/docusaurus.config.mjs` instead of `.keep`)
- Delete: `sync-docs/.keep`

Fixture:

```
docs.json                              {"title":"Curiosus.Sample","tagline":"Fixture"}
README.md                              "# Curiosus.Sample" + absolute link https://curiosus-dev.github.io/Curiosus.Sample/guide
docs/index.md -> ../README.md
docs/guide.md                          "# Guide" + a csharp code block
docs/packages/area/_category_.json     {"label":"Area"}
docs/packages/area/curiosus-sample.md -> ../../../src/Area/Curiosus.Sample/README.md
src/Area/Curiosus.Sample/README.md     "# Curiosus.Sample package" + absolute link to the repository
```

- [ ] **Step 1:** fixture + `tests/docs-build.sh`: copies fixture and `sync-docs/` into a temp dir, `npm ci`,
`GITHUB_REPOSITORY=curiosus-dev/Curiosus.Sample npm run build`, then asserts: `build/index.html` exists;
`build/packages/area/curiosus-sample.html` exists and contains `Curiosus.Sample package` and
`edit/main/src/Area/Curiosus.Sample/README.md`; with `git init` + ssh origin and empty `GITHUB_REPOSITORY`, a build
to `build-local` contains `/Curiosus.Sample/`; without `docs.json` the build fails and stderr names `docs.json`.
Run: `bash tests/docs-build.sh` — Expected: FAIL (no package.json).
- [ ] **Step 2:** `package.json` (scripts `start|build|serve|clear` → `docusaurus <cmd>`; deps `@docusaurus/core` and
`@docusaurus/preset-classic` 3.10.2, `@mdx-js/react ^3.1.0`, `clsx ^2.1.1`, `prism-react-renderer ^2.4.1`,
`react`/`react-dom ^19.0.0`; `"type": "module"`, `engines.node >=24`), `npm install` for the lockfile.
- [ ] **Step 3:** `docusaurus.config.mjs`: `loadSite()` reads `../docs.json` (throws `docs.json: ...`);
`resolveRepository()` parses `GITHUB_REPOSITORY` or `git remote get-url origin` with
`/^(?:(?:git@|https:\/\/)github\.com[:/])?([\w.-]+)\/([\w.-]+?)(?:\.git)?\/?$/`; `url`, `baseUrl: /<name>/`,
`trailingSlash: false`; docs `{ path: '../docs', routeBasePath: '/', sidebarPath: './sidebars.mjs', editUrl }` where
`editUrl` realpaths `docs/<docPath>` and makes it relative to the real repository root; `blog: false`; navbar logo,
NuGet and GitHub links; dark footer with GitHub/NuGet/dotnet-tools, "© <year> Curiosus contributors"; prism github /
dracula + `csharp sql bash powershell json`. `sidebars.mjs`: autogenerated. `.gitignore`: `node_modules/ build/
.docusaurus/`. `custom.css`: primary shades `#c23926 #af3322 #a53020 #88281b #d54130 #d74a3a #de6a5d`, dark
`#e0604f #dc4b38 #da412d #bd3322 #e47566 #e67f71 #ec9e94`. Images from `.github/branding`.
- [ ] **Step 4:** Run `bash tests/docs-build.sh` — Expected: `docs build passed`. **If Docusaurus rejects symlinks to
files outside `docs/`, stop and report to the maintainer.** Update and run `tests/sync-test.sh` — `sync tests passed`.
- [ ] **Step 5:** manual Review Focus 2: add `[x](../../../LICENSE)` to the fixture package README in a temp copy,
build — Expected: build fails on the broken link.
- [ ] **Step 6:** commit `feat(docs): shared Docusaurus website`.

### Task 4: docs workflow, Pages settings, lint, dependabot (dotnet-tools)

- [ ] **Step 1:** `sync-docs/.github/workflows/docs.yml`: synced header; triggers `push` (main) and `pull_request` with
paths `docs/** website/** docs.json **/README.md **/CHANGELOG.md .github/workflows/docs.yml`, `workflow_dispatch`;
`permissions: contents: read`; concurrency `docs-${{ github.ref }}`, cancel only for pull requests; job `build`
(working dir `website`): checkout, setup-node 24 with npm cache on `website/package-lock.json`, `npm ci`,
`npm run build`, on main `upload-pages-artifact` with `website/build`; job `deploy` (main only, needs build):
`pages: write`, `id-token: write`, environment `github-pages` with `url: ${{ steps.deployment.outputs.page_url }}`,
`deploy-pages` with `id: deployment`.
- [ ] **Step 2:** `scripts/pin-actions.sh`: add `sync-docs/.github/workflows/*.yml` to the defaults; pin `docs.yml`
(checkout on the same major as `sync/`).
- [ ] **Step 3:** `lint.yml`: actionlint also on `sync-docs/.github/workflows/*.yml`; `shellcheck tests/*.sh`;
`bash tests/sync-test.sh`; setup-node 24 (pinned) and `bash tests/docs-build.sh`. Run actionlint and shellcheck locally
— Expected: clean.
- [ ] **Step 4:** `.github/dependabot.yml`: npm for `/sync-docs/website`, weekly, one group for docusaurus/react/mdx/prism/clsx.
- [ ] **Step 5:** `settings/environments.json`: `github-pages` like `nuget` (custom branch policy `main`);
`settings/repositories.json`: environments `nuget`, `github-pages` for Migrations and Utils; `repo-settings.py`:
for `docs` repositories, before environments, `GET repos/.../pages` (404 → `pages: disabled`, apply `POST` with
`{"build_type": "workflow"}`), otherwise compare and `PUT`. Run `py_compile` and `repo-settings.py check
Curiosus.Migrations` — Expected: reports `pages` and `github-pages` drift. **Do not run apply.**
- [ ] **Step 6:** commit `feat(docs): docs workflow and GitHub Pages settings`.

### Task 5: dotnet-tools documentation

- [ ] **Step 1:** `README.md`: `sync-docs/` and the `docs` flag, `docs.json` (`title`, `tagline`), README/CHANGELOG
symlinks in `docs/` (no front matter, absolute links, `core.symlinks=true` on Windows), local preview
(`cd website && npm ci && npm start`), `tests/`, Pages settings from `repo-settings.py`.
- [ ] **Step 2:** `sync/.claude/curiosus.md`: Stack line → Docusaurus sites on GitHub Pages built from `docs/`; README
badges item → documentation link; shared files: `website/` and `.github/workflows/docs.yml` for repositories with a
docs site; a Documentation paragraph (edit `docs/` and READMEs, never `website/`; symlinks; `npm start`; MDX rules).
- [ ] **Step 3:** commit `docs: document the shared Docusaurus sites`.

### Task 6: Curiosus.Migrations content (Migrations worktree)

- [ ] **Step 1:** `SYNC_REPOSITORY=Curiosus.Migrations SYNC_DRY_RUN=1 ../dotnet-tools/scripts/sync.sh` for local builds;
synced files are not committed here (drop them after the commit with `git clean -fd website` and `git checkout -- .`).
- [ ] **Step 2:** `docs.json`: title `Curiosus.Migrations`, tagline "Database migrations for .NET: SQL scripts and C#
code, downgrades, long-running migrations, policies".
- [ ] **Step 3:** `docs/changelog/`: remove the three broken `curiosity.*` symlinks; add
`curiosus-migrations{,-postgresql,-sqlserver,-utils}.md -> ../../src/<Package>/CHANGELOG.md`;
`_category_.json` `{"label":"Changelogs","position":7}`. If all CHANGELOG H1s are identical, make them
`# Changelog: <PackageId>` after checking `build/curiosus.cake` does not depend on the H1.
- [ ] **Step 4:** front matter `sidebar_position`/`sidebar_label` from the old `mkdocs.yml` nav (Intro 1, Quick Start 2,
Philosophy 3, Basics 4, Supported Databases 5; features/ 6 with script_migration 1 (What is it, Batches),
code_migration 2 (What is it, EntityFramework Integration, Dependency Injection), then migration_providers, variables,
transactions, pre_migrations, logging, journal, downgrade, dependencies 3–10); `_category_.json` for features,
script_migration, code_migration.
- [ ] **Step 5:** `docs/basics.md`: `!!! note` → `:::note`.
- [ ] **Step 6:** `cd website && npm ci && npm run build`; fix MDX errors in the sources (Markdown over HTML,
self-closed void tags, no string `style`, bare `{`/`<` in backticks) until `[SUCCESS]` with no broken links.
- [ ] **Step 7:** readthedocs URLs → `https://curiosus-dev.github.io/Curiosus.Migrations/<path>` in README, CLAUDE.md,
`src/*/README.md`, `src/*/*.csproj`; badge → shields "docs | GitHub Pages" linking the site; verify each URL path exists
in `website/build`.
- [ ] **Step 8:** remove `mkdocs.yml`, `.readthedocs.yaml`, `docs/requirements.txt`, `docs/stylesheets/`,
`docs/images/curiosus-logo-*`; build; `npm run serve` and look at `/`, `/features/downgrade`, `/changelog/curiosus-migrations`.
- [ ] **Step 9:** commit `docs: move documentation to Docusaurus on GitHub Pages` (content only), clean synced copies.

### Task 7: Curiosus.Utils content (Utils worktree)

- [ ] **Step 1:** dry-run sync with `SYNC_REPOSITORY=Curiosus.Utils`.
- [ ] **Step 2:** `docs.json`: title `Curiosus.Utils`, tagline "Building blocks for .NET services: hosting,
configuration, data access, e-mail and SMS, notifications".
- [ ] **Step 3:** merge what `docs/index.md` has beyond `README.md` into README; `docs/index.md -> ../README.md`.
- [ ] **Step 4:** for every `src/<Area>/<Package>/README.md`: `docs/packages/<area>/<package>.md ->
../../../src/<Area>/<Package>/README.md` (lowercase, dots → dashes) and `_category_.json` `{"label":"<Area>"}`;
`docs/packages/_category_.json` `{"label":"Packages","position":3}`. Expected: 37 symlinks, none dangling.
- [ ] **Step 5:** `docs/Notiifications` → `docs/notifications` (two `git mv` steps), `_category_.json`
`{"label":"Notifications guide","position":2}`.
- [ ] **Step 6:** build and fix MDX errors (same rules; READMEs stay valid for nuget.org); relative links in README →
absolute.
- [ ] **Step 7:** badge and "Full documentation" link → `https://curiosus-dev.github.io/Curiosus.Utils/`; notification
READMEs → `/notifications`, `/notifications/sms`, `/notifications/emails`; CLAUDE.md docs line; verify URLs in the build.
- [ ] **Step 8:** remove `mkdocs.yml`, `.readthedocs.yml`, `requirements.txt`; build; look at `/`,
`/packages/dal/curiosus-dal`, `/notifications/emails`.
- [ ] **Step 9:** commit `docs: move documentation to Docusaurus on GitHub Pages`, clean synced copies.

### Task 8: Pull requests

- [ ] **Step 1:** dotnet-tools: `bash tests/sync-test.sh && bash tests/docs-build.sh`; push, PR
`feat(docs): shared Docusaurus sites on GitHub Pages`.
- [ ] **Step 2:** Migrations and Utils: push, PR `docs: move documentation to Docusaurus on GitHub Pages`, noting the
site builds after the dotnet-tools sync PR is merged.
- [ ] **Step 3:** manual steps for the maintainer: merge dotnet-tools → merge sync PRs →
`scripts/repo-settings.py apply Curiosus.Migrations Curiosus.Utils` → merge content PRs → check the sites → disable
ReadTheDocs projects.
