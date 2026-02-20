#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_PATH="$ROOT_DIR/.build/debug/Pullbar"

swift build --package-path "$ROOT_DIR"

if [[ ! -f "$BIN_PATH" ]]; then
  echo "Binary not found at $BIN_PATH"
  exit 1
fi

codesign --force --sign - --timestamp=none "$BIN_PATH"
codesign --verify --verbose "$BIN_PATH"

echo "Signed binary: $BIN_PATH"

if [[ "${1:-}" != "--no-run" ]]; then
  exec "$BIN_PATH"
fi
