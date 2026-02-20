# Contributing

## Workflow

- Create focused changes by concern (UI, data, scripts, docs).
- Keep changes small and buildable at every step.
- Prefer incremental pull requests with clear scope.

## Code Standards

- Preserve existing public behavior unless explicitly changing UX/requirements.
- Keep Swift code readable and avoid unnecessary abstractions.
- Place code in the module folders under `Sources/Pullbar`:
  - `App/`
  - `Domain/`
  - `Features/`
  - `Infrastructure/`

## Validation

Before opening a PR:

- Run `swift build`
- Run `./scripts/install.sh --help` when changing installer scripts
- Manually verify critical flows:
  - Settings save/load
  - Tab refresh and sorting
  - Menu bar status updates

## Security

- Never log or persist PAT tokens outside Keychain.
- Keep host/API changes explicit and validated.
- Avoid adding shell commands that expose credentials in output.

## Commit / PR Style

- Use concise, imperative messages.
- Keep title format consistent: `<area>: <change>`
  - Example: `settings: add launch-at-login toggle`
