# Pullbar (MVP)

Native macOS menu bar app (macOS 14+) for monitoring GitHub pull requests.

## Project Structure

- `Sources/Pullbar/App` — app lifecycle and popover host
- `Sources/Pullbar/Domain` — shared models and enums
- `Sources/Pullbar/Features` — UI and feature-specific stores
- `Sources/Pullbar/Infrastructure` — API clients, keychain, cache, CLI integration
- `scripts` — local run/install automation
- `docs` — architecture and operational documentation

## Features

- GitHub.com and GitHub Enterprise host support (configurable host URL and optional explicit GraphQL API URL)
- Personal Access Token authentication (stored only in Keychain)
- Optional one-click import from authenticated GitHub CLI (`gh`) session
- View active `gh` profile and switch to a different authenticated `gh` profile from Settings
- Three PR views:
  - Assigned to me
  - Review requested
  - Created by me
- Tabs are configurable: disable default tabs and add custom query tabs (up to 5 total)
- Per-view saved search/filter query (GitHub search syntax)
- Custom tabs support rule-based post-filters with match-all/any logic (comments, review status, checks status)
- PR row data: repository, title, author, last update, review summary, checks summary
- Configurable PR ordering: sort by updated date or creation date
- PR actions: open PR, open checks, manual refresh
- Auto-refresh in background with configurable interval
- Basic settings window for token, host URL, optional API URL, refresh interval, and saved queries
- Error states for auth failures, network issues, rate limiting, and empty views

## Run

1. Open this package in Xcode (`File > Open...` and select the folder).
2. Build and run the `Pullbar` executable target.
3. A menu bar icon appears; open **Settings** to add your PAT.

### Run from terminal with stable signing

To improve Keychain trust consistency when launching from terminal, run:

`./scripts/run-signed.sh`

This builds the app, applies an ad-hoc signature to the binary, and launches it.
For a dry run that signs without launching:

`./scripts/run-signed.sh --no-run`

## Install

To install Pullbar as an app in `/Applications`:

`./scripts/install.sh`

To install and immediately launch:

`./scripts/install.sh --run`

This creates a signed `Pullbar.app`, installs it to `/Applications`, and keeps it as a menu bar app.

Optional app icon: place `Pullbar.icns` at either `Assets/AppIcon/Pullbar.icns` or project root (`Pullbar.icns`), and the installer will bundle it automatically.

After install, open Pullbar and enable **Launch at login** in Settings.

## Security

- Token is stored in macOS Keychain using `SecItemAdd` / `SecItemUpdate`.
- Token is never persisted to `UserDefaults` or logs.

## Notes

- Uses GitHub GraphQL search to fetch pull requests and status summaries.
- Cached data is loaded first for fast popover rendering and then refreshed.

## Engineering Docs

- `CONTRIBUTING.md`
- `docs/ARCHITECTURE.md`
- `docs/OPERATIONS.md`
- `docs/BRANCH_PROTECTION.md`
- `SECURITY.md`
- `SUPPORT.md`
- `LICENSE`

## GitHub Repo Standards

- Issue templates: `.github/ISSUE_TEMPLATE/`
- PR template: `.github/pull_request_template.md`
- Code owners: `.github/CODEOWNERS`
- Dependabot updates: `.github/dependabot.yml`
- CI workflows: `.github/workflows/`
- Repo hygiene: `.gitignore`, `.editorconfig`, `.gitattributes`

## CI

- GitHub Actions workflow: `.github/workflows/ci.yml`
- Validates debug/release builds and install/run helper scripts on macOS.
- Release artifact workflow: `.github/workflows/release-artifact.yml`
- On tag push (`v*`) or manual dispatch, builds and uploads `Pullbar.app.zip`.
- On tag push, it also creates/updates a GitHub Release and attaches the zip.