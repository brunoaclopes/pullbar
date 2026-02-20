# Architecture

## High-Level

Pullbar is a macOS menu bar app built with SwiftUI + AppKit host integration.

- **App layer**: lifecycle, menu bar item, popover host.
- **Domain layer**: models/enums shared across features.
- **Feature layer**: pull request experience and settings flows.
- **Infrastructure layer**: GitHub API, Keychain, cache, CLI integration.

## Folder Layout

- `Sources/Pullbar/App`
- `Sources/Pullbar/Domain`
- `Sources/Pullbar/Features/PullRequests`
- `Sources/Pullbar/Features/Settings`
- `Sources/Pullbar/Infrastructure/Cache`
- `Sources/Pullbar/Infrastructure/GitHub`
- `Sources/Pullbar/Infrastructure/Security`

## Runtime Data Flow

1. `AppDelegate` initializes shared `AppContext`.
2. `PullRequestStore` configures and loads cache.
3. UI (`ContentView`) renders tabs and current data.
4. `SettingsStore` persists configuration via `UserDefaults`.
5. `GitHubClient` fetches PR data and maps into domain models.
6. Stores publish updates to SwiftUI views.

## Configuration Boundaries

- **Secure**: PAT token in Keychain only.
- **Local settings**: `UserDefaults` for non-sensitive preferences.
- **Network**: GitHub GraphQL endpoint from settings defaults.

## Operational Notes

- Installer script: `scripts/install.sh`
- Signed run helper: `scripts/run-signed.sh`
- Launch-at-login managed through `ServiceManagement` API.
