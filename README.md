# dotnet-tools

Shared build, CI, release and editor setup for the Curiosus .NET libraries:
[Curiosus.Migrations](https://github.com/curiosus-dev/Curiosus.Migrations),
[Curiosus.Utils](https://github.com/curiosus-dev/Curiosus.Utils),
[Curiosus.TelegramBot](https://github.com/curiosus-dev/Curiosus.TelegramBot).

Files in [`sync/`](sync) are copied into the root of every repository by pull requests,
so local builds, AI agents and CI use exactly the same scripts and settings.

| File | Purpose |
|---|---|
| `build/curiosus.cake` | Cake tasks: build, tests, coverage, pack, nuget.org push, GitHub releases |
| `build/Curiosus.props` | Common MSBuild settings (deterministic CI builds, Source Link, symbol packages) |
| `.config/dotnet-tools.json` | Cake and ReportGenerator versions |
| `.github/workflows/build.yml` | Pull request build and tests |
| `.github/workflows/release-packages.yml` | Publishing via NuGet Trusted Publishing + GitHub releases |
| `nuget.config` | Restore from nuget.org only |
| `.editorconfig` | Code style |
| `.claude/curiosus.md` | Shared instructions for Claude Code, imported from the repository `CLAUDE.md` |

## How a repository uses it

`build.cake`:

```csharp
#load "build/curiosus.cake"

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

Conventions the scripts rely on are described in [`.claude/curiosus.md`](sync/.claude/curiosus.md).

## Changing shared files

1. Change files in `sync/` and merge to `main`.
2. [Sync workflow](.github/workflows/sync.yml) opens a pull request in every repository
   (older sync pull requests are closed), CI of each repository validates the change.
3. Review and merge the pull requests.

Files removed from `sync/` are not removed from repositories, delete them there manually.

Preview locally from a repository root: `SYNC_DRY_RUN=1 ../dotnet-tools/scripts/sync.sh`.

## Setup

### Sync GitHub App

1. Create a GitHub App in the `curiosus-dev` organization (Settings → Developer settings → GitHub Apps),
   without a webhook, with repository permissions:
   - Contents: read and write
   - Pull requests: read and write
   - Workflows: read and write (synced files include workflows)
   - Metadata: read
2. Install the app on the Curiosus repositories (not on this one).
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
