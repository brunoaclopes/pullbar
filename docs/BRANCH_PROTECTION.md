# Branch Protection Checklist

Apply these settings to `main` in GitHub repository settings.

## Required Status Checks

- Require status checks to pass before merging
- Require branches to be up to date before merging
- Required checks:
  - `build-and-validate` (from CI workflow)

## Pull Request Rules

- Require a pull request before merging
- Require approvals: at least 1
- Dismiss stale pull request approvals when new commits are pushed
- Require review from Code Owners
- Require conversation resolution before merging

## Additional Safety

- Include administrators (recommended)
- Restrict force pushes
- Restrict branch deletions
- Enable merge queue (optional, recommended if repo traffic increases)

## Recommended Repository Settings

- Default squash merges for clean history
- Enable auto-delete head branches after merge
- Use signed tags for release versions (`v*`)
