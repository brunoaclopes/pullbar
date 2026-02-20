# Pullbar

Pullbar is a native macOS menu bar app (macOS 14+) for tracking GitHub pull requests without living in the browser.

## Why Pullbar

- **Focused PR dashboard** in your top bar
- **Fast triage** with tabbed views and status summaries
- **Custom workflows** with query + rule-based tab filters
- **Secure auth** with token storage in macOS Keychain

## Highlights

- GitHub.com and GitHub Enterprise support (host/API configurable)
- Optional one-click import from authenticated `gh` CLI sessions
- Built-in tabs: **Assigned**, **Review requested**, **Created by me**
- Custom tabs (up to 5 total), including rule filters:
  - comments (has/no unresolved)
  - review state
  - checks state
- Sort PRs by updated date or created date
- Open PR/checks directly from rows
- Auto-refresh with configurable interval
- Launch-at-login toggle

## Quick Start

### Run from Xcode

1. Open the package in Xcode.
2. Build and run the `Pullbar` executable target.
3. Open **Settings** and add your GitHub PAT.

### Run from terminal (signed)

```bash
./scripts/run-signed.sh
```

Dry run (sign only):

```bash
./scripts/run-signed.sh --no-run
```

## Install as an app

Install to `/Applications`:

```bash
./scripts/install.sh
```

Install and launch:

```bash
./scripts/install.sh --run
```

Optional app icon: place `Pullbar.icns` at `Assets/AppIcon/Pullbar.icns`.

## Security

- PAT tokens are stored only in macOS Keychain (`SecItemAdd` / `SecItemUpdate`).
- Tokens are never persisted to `UserDefaults` or logs.

## Project Layout

- `Sources/Pullbar/App` — app lifecycle and menu bar popover host
- `Sources/Pullbar/Domain` — shared models/enums
- `Sources/Pullbar/Features` — Pull Requests + Settings flows
- `Sources/Pullbar/Infrastructure` — GitHub client, cache, keychain, gh integration
- `scripts` — local build/run/install tooling
- `docs` — architecture and operations references

## Engineering Docs

- `CONTRIBUTING.md`
- `docs/ARCHITECTURE.md`
- `docs/OPERATIONS.md`
- `docs/BRANCH_PROTECTION.md`
- `SECURITY.md`
- `SUPPORT.md`
- `LICENSE`

## GitHub Standards

- Issue templates: `.github/ISSUE_TEMPLATE/`
- PR template: `.github/pull_request_template.md`
- Code owners: `.github/CODEOWNERS`
- Dependabot: `.github/dependabot.yml`
- Workflows: `.github/workflows/`

## CI / Release

- CI workflow: `.github/workflows/ci.yml`
  - validates debug/release builds and helper scripts on macOS
- Release workflow: `.github/workflows/release-artifact.yml`
  - on `v*` tags or manual dispatch, builds `Pullbar.app.zip`
  - publishes/updates GitHub Release on tag pushes