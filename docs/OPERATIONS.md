# Operations

## Development

- Build: `swift build`
- Run signed binary: `./scripts/run-signed.sh`

## Install Local App

- Install: `./scripts/install.sh`
- Install + run: `./scripts/install.sh --run`

## App Icon

Installer auto-picks `Pullbar.icns` from:

1. `Assets/AppIcon/Pullbar.icns`
2. `Pullbar.icns` (repo root)

## Troubleshooting

### Stuck Process

- List: `pgrep -fal Pullbar`
- Stop: `pkill -TERM -x Pullbar`
- Force: `pkill -KILL -x Pullbar`

If still present in uninterruptible state, reboot macOS.

### Login Item Not Applying

- Ensure app is launched from `/Applications/Pullbar.app`
- Toggle **Launch at login** off/on in settings.
