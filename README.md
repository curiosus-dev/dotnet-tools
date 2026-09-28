# dotnet-tools

[![Lint](https://github.com/curiosus-dev/dotnet-tools/actions/workflows/lint.yml/badge.svg?branch=main)](https://github.com/curiosus-dev/dotnet-tools/actions/workflows/lint.yml)
[![Sync](https://github.com/curiosus-dev/dotnet-tools/actions/workflows/sync.yml/badge.svg?branch=main)](https://github.com/curiosus-dev/dotnet-tools/actions/workflows/sync.yml)
[![Settings drift](https://github.com/curiosus-dev/dotnet-tools/actions/workflows/settings-drift.yml/badge.svg?branch=main)](https://github.com/curiosus-dev/dotnet-tools/actions/workflows/settings-drift.yml)

Shared build, CI, release and editor setup for the Curiosus .NET libraries:
[Curiosus.Migrations](https://github.com/curiosus-dev/Curiosus.Migrations),
[Curiosus.Utils](https://github.com/curiosus-dev/Curiosus.Utils),
[Curiosus.TelegramBot](https://github.com/curiosus-dev/Curiosus.TelegramBot).

Files in [`sync/`](sync) are copied into the root of every repository by pull requests,
so local builds, AI agents and CI use exactly the same scripts and settings.

## Status

| Repository | Default branch | Pull requests | Coverage | NuGet |
|---|---|---|---|---|
| [Curiosus.Migrations](https://github.com/curiosus-dev/Curiosus.Migrations) | [![Release](https://github.com/curiosus-dev/Curiosus.Migrations/actions/workflows/release-packages.yml/badge.svg?branch=master)](https://github.com/curiosus-dev/Curiosus.Migrations/actions/workflows/release-packages.yml) | [![Build](https://github.com/curiosus-dev/Curiosus.Migrations/actions/workflows/build.yml/badge.svg?event=pull_request)](https://github.com/curiosus-dev/Curiosus.Migrations/actions/workflows/build.yml) | [![Coverage](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/curiosus-dev/Curiosus.Migrations/badges/coverage.json)](https://github.com/curiosus-dev/Curiosus.Migrations/actions/workflows/release-packages.yml) | [![NuGet](https://img.shields.io/nuget/v/Curiosus.Migrations)](https://www.nuget.org/packages/Curiosus.Migrations) |
| [Curiosus.Utils](https://github.com/curiosus-dev/Curiosus.Utils) | [![Release](https://github.com/curiosus-dev/Curiosus.Utils/actions/workflows/release-packages.yml/badge.svg?branch=master)](https://github.com/curiosus-dev/Curiosus.Utils/actions/workflows/release-packages.yml) | [![Build](https://github.com/curiosus-dev/Curiosus.Utils/actions/workflows/build.yml/badge.svg?event=pull_request)](https://github.com/curiosus-dev/Curiosus.Utils/actions/workflows/build.yml) | [![Coverage](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/curiosus-dev/Curiosus.Utils/badges/coverage.json)](https://github.com/curiosus-dev/Curiosus.Utils/actions/workflows/release-packages.yml) | [![NuGet](https://img.shields.io/nuget/v/Curiosus.Tools?label=nuget%20Curiosus.Tools)](https://www.nuget.org/profiles/curiosus-dev) |
| [Curiosus.TelegramBot](https://github.com/curiosus-dev/Curiosus.TelegramBot) | [![Release](https://github.com/curiosus-dev/Curiosus.TelegramBot/actions/workflows/release-packages.yml/badge.svg?branch=main)](https://github.com/curiosus-dev/Curiosus.TelegramBot/actions/workflows/release-packages.yml) | [![Build](https://github.com/curiosus-dev/Curiosus.TelegramBot/actions/workflows/build.yml/badge.svg?event=pull_request)](https://github.com/curiosus-dev/Curiosus.TelegramBot/actions/workflows/build.yml) | [![Coverage](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/curiosus-dev/Curiosus.TelegramBot/badges/coverage.json)](https://github.com/curiosus-dev/Curiosus.TelegramBot/actions/workflows/release-packages.yml) | [![NuGet](https://img.shields.io/nuget/v/Curiosus.TelegramBot)](https://www.nuget.org/packages/Curiosus.TelegramBot) |

*Default branch* is the last push: build, tests, publishing. *Pull requests* is the last pull request build.

| File | Purpose |
|---|---|
| `build/curiosus.cake` | Cake tasks: build, tests, coverage report, pack, nuget.org push, GitHub releases |
| `build/Curiosus.props` | Common MSBuild settings (deterministic CI builds, Source Link, symbol packages) |
| `.config/dotnet-tools.json` | Cake and ReportGenerator versions |
| `.github/workflows/build.yml` | Pull request build, tests and coverage summary |
| `.github/workflows/release-packages.yml` | Publishing via NuGet Trusted Publishing + GitHub releases, coverage badge |
| `.github/dependabot.yml` | Security updates for all NuGet packages, monthly version updates for test-only packages |
| `nuget.config` | Restore from nuget.org only |
| `.editorconfig` | Code style |
| `.claude/curiosus.md` | Shared instructions for Claude Code, imported from the repository `CLAUDE.md` |

## How a repository uses it

`build.cake`:

```csharp
#load "build/curiosus.cake"

minLineCoverage = 70; // CoverageReport fails below it, %

// repository-specific tasks

RunTarget(target);
```

`Directory.Build.props`:

```xml
<Project>
    <Import Project="build/Curiosus.props" />
    <!-- repository-specific settings -->
</Project>
```

`CLAUDE.md` starts with `@.claude/curiosus.md`.

Coverage badges for `README.md`, for the repository and for a package:

```markdown
[![Coverage](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/curiosus-dev/<repository>/badges/coverage.json)](https://github.com/curiosus-dev/<repository>/actions/workflows/release-packages.yml)
[![Coverage](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/curiosus-dev/<repository>/badges/<PackageId>.json)](https://github.com/curiosus-dev/<repository>/actions/workflows/release-packages.yml)
```

A package whose assembly is never loaded by tests shows "no tests".

Conventions the scripts rely on are described in [`.claude/curiosus.md`](sync/.claude/curiosus.md).

## Changing shared files

1. Change files in `sync/` and merge to `main`.
2. [Sync workflow](.github/workflows/sync.yml) opens a pull request in every repository
   (older sync pull requests are closed), CI of each repository validates the change.
3. Review and merge the pull requests.

Files removed from `sync/` are not removed from repositories, delete them there manually.

Preview locally from a repository root: `SYNC_DRY_RUN=1 ../dotnet-tools/scripts/sync.sh`.

## Repository settings

Security and repository settings are described in [`settings/`](settings) and are the same for every repository
listed in [`settings/repositories.json`](settings/repositories.json):

| File | What |
|---|---|
| `repository.json` | Merge options, wiki/projects, branch cleanup, secret scanning, push protection, Dependabot security updates |
| `actions.json` | Allowed actions (GitHub-owned + `NuGet/login`), SHA pinning required, read-only `GITHUB_TOKEN`, fork PR approval |
| `rulesets/protect-default-branch.json` | No force pushes or deletion of the default branch, no bypass |
| `rulesets/default-branch-pull-requests.json` | Changes via pull requests with green required checks; repository admins can bypass |
| `rulesets/protect-release-tags.json` | Tags can be created but never moved or deleted |

Dependabot alerts, Dependabot security updates, private vulnerability reporting and CodeQL default setup are enabled
by the same script. Community health files (`SECURITY.md`, `CONTRIBUTING.md`, issue and pull request templates)
come from [curiosus-dev/.github](https://github.com/curiosus-dev/.github).

```bash
scripts/repo-settings.py check            # what differs from ./settings
scripts/repo-settings.py apply            # make repositories match, needs repository admin rights
scripts/repo-settings.py apply dotnet-tools
```

[Settings drift](.github/workflows/settings-drift.yml) runs `check` weekly with the sync app token (read-only) and
fails when someone changed a setting by hand: either apply `./settings` again or change `./settings`.
Ruleset bypass actors are visible only to repository admins, so they are checked by a local `check` alone.

## Pinned actions

Actions are pinned to commit SHAs (`sha_pinning_required` is on). Dependabot updates the workflows of this repository;
synced workflows in `sync/` are updated with:

```bash
scripts/pin-actions.sh   # latest release within the same major version for every `uses:`
```

Run it when Dependabot bumps an action here, then merge: the sync pull requests deliver the new pins.

## Setup

### Sync GitHub App

1. Create a GitHub App in the `curiosus-dev` organization (Settings → Developer settings → GitHub Apps),
   without a webhook, with repository permissions:
   - Contents: read and write
   - Pull requests: read and write
   - Workflows: read and write (synced files include workflows)
   - Administration: read (settings drift check)
   - Code scanning alerts: read (settings drift check)
   - Metadata: read
2. Install the app on the Curiosus repositories, this one and `.github` (the settings drift check reads all of them).
3. In this repository add the variable `SYNC_APP_CLIENT_ID` (app Client ID)
   and the secret `SYNC_APP_PRIVATE_KEY` (generated private key).

### NuGet Trusted Publishing, per repository

1. On nuget.org: profile → Trusted Publishing → add a policy owned by the packages owner:
   repository owner `curiosus-dev`, repository `<name>`, workflow file `release-packages.yml`, no environment.
2. In the repository add the secret `NUGET_USER` — nuget.org profile name, not an email.
3. After the first successful release remove old API key secrets and revoke the keys on nuget.org.

## Adding a repository

Add it to the matrix in [`.github/workflows/sync.yml`](.github/workflows/sync.yml), install the sync app on it,
run the workflow manually and set up NuGet Trusted Publishing as above.
