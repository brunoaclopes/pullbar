# Architecture

## High-Level

Pullbar is a macOS menu bar app built with SwiftUI + AppKit host integration.

- **App layer**: lifecycle, menu bar item, popover host.
- **Domain layer**: models/enums shared across features.
- **Feature layer**: pull request experience and settings flows.
- **Infrastructure layer**: GitHub API, Keychain, cache, CLI integration.

## Folder Layout

- `Sources/Pullbar/App`
  - `PullbarApp.swift` — entry point, `AppDelegate`, `AppContext` singleton
- `Sources/Pullbar/Domain`
  - `Models.swift` — PR, tab, review/check enums (with `sortIndex` and `CaseIterable`)
  - `ErrorHelpers.swift` — `Error.userFacingMessage` extension
  - `DetailLoadTracker.swift` — per-PR detail load-state tracking
- `Sources/Pullbar/Features/PullRequests`
  - `ContentView.swift` — main popover view with tab bar and keyboard shortcuts
  - `PullRequestStore.swift` — data store (fetch, cache, sort, notification hints)
  - `PullRequestGroupCard.swift` — section/card/subgroup views
  - `PullRequestRow.swift` — individual PR row
  - `PullRequestReviewPopover.swift` — review detail popover
  - `PullRequestCommentsPopover.swift` — comments detail popover
  - `PullRequestChecksPopover.swift` — checks detail popover
- `Sources/Pullbar/Features/Settings`
  - `SettingsStore.swift` — `UserDefaults`-backed preferences
  - `SettingsView.swift` — settings form with refresh interval picker
- `Sources/Pullbar/Infrastructure/Cache`
  - `CacheService.swift` — JSON file cache with `os.Logger` diagnostics
  - `CachedAsyncImage.swift` — `NSCache`-backed async avatar loader
- `Sources/Pullbar/Infrastructure/GitHub`
  - `GitHubClient.swift` — GraphQL client (namespaced under `GraphQLResponse` enum)
  - `GHCLIImporter.swift` — `gh` CLI token import (async process execution)
- `Sources/Pullbar/Infrastructure/Security`
  - `KeychainService.swift` — Keychain read/write for PAT tokens

## Runtime Data Flow

1. `AppDelegate` initializes the shared `AppContext` (creates `SettingsStore` and `PullRequestStore`).
2. `PullRequestStore.configure(settings:)` is called **synchronously** to inject the settings reference before any Combine bindings fire.
3. Combine sinks (with `.dropFirst()`) bind settings changes to store actions (refresh, sort, notification hints).
4. Store loads JSON cache, then kicks off the first GraphQL refresh inside a `Task`.
5. UI (`ContentView`) renders tabs and current data via `@EnvironmentObject`.
6. Concurrent refreshes are prevented via cancel-and-replace (`activeRefreshTask`).
7. Detail data (reviews, comments, checks) is loaded on-demand and tracked by `DetailLoadTracker`.
8. `GitHubClient` executes GraphQL queries; responses are namespaced under a caseless `GraphQLResponse` enum.
9. `GHCLIImporter` runs `gh` CLI commands via async `Process` wrappers (off the cooperative thread pool).

## Configuration Boundaries

- **Secure**: PAT token in Keychain only.
- **Local settings**: `UserDefaults` for non-sensitive preferences.
- **Network**: GitHub GraphQL endpoint from settings defaults.

## Key Patterns

- **Settings injection**: `PullRequestStore` receives `SettingsStore` via `configure(settings:)` rather than passing it through every method call.
- **Cancel-and-replace**: overlapping refresh requests cancel the in-flight task before starting a new one.
- **Guard-let safety**: store methods that access the injected settings use `guard let settings else { return }` as a safety net.
- **`os.Logger` diagnostics**: cache read/write errors are logged instead of silently swallowed.
- **Enum `sortIndex`**: review and check summary enums define their own sort order via a `sortIndex` property, removing hard-coded dictionaries.

## Operational Notes

- Installer script: `scripts/install.sh`
- Signed run helper: `scripts/run-signed.sh`
- Launch-at-login managed through `ServiceManagement` API.
