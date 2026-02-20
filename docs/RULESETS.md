# Repository Rulesets Checklist

This repository uses **GitHub Rulesets** (not legacy branch protection) for governance and merge controls.

## Active Rulesets

### 1) `main-protection-ruleset` (target: branch)

Applies to:

- `refs/heads/main`

Enforces:

- Required status checks (strict/up-to-date):
  - `build-and-validate`
- Pull request review requirements:
  - 1 required approving review
  - code owner review required
  - dismiss stale reviews on push
  - conversation resolution required
- Block branch deletion
- Block non-fast-forward updates (no history rewrites)

Bypass:

- Repository admins can bypass **pull request** requirements when needed.

### 2) `release-tag-protection` (target: tag)

Applies to:

- `refs/tags/v*`

Enforces:

- Block tag deletion
- Block non-fast-forward updates (release tags are immutable)

Bypass:

- Repository admins can bypass when necessary (`always`).

## Repository Defaults

- Default branch: `main`
- Auto-delete merged branches: enabled
- Merge strategy: squash merges
- Keep CI green before merge

## Why This Is Public

This document is safe to keep public. It describes repository governance and quality controls, not secrets or credentials.
