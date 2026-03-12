#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

BINDIR="${BINDIR:-$HOME/.local/bin}"
TARGET_NAME="${TARGET_NAME:-opencode-worktree-guard}"
SOURCE_PATH="$REPO_ROOT/helpers/owg"
TARGET_PATH="$BINDIR/$TARGET_NAME"

mkdir -p "$BINDIR"

if [[ ! -f "$SOURCE_PATH" ]]; then
  echo "Source script not found: $SOURCE_PATH"
  exit 1
fi

ln -sfn "$SOURCE_PATH" "$TARGET_PATH"

echo "Installed $TARGET_NAME -> $TARGET_PATH"

if ! command -v "$TARGET_NAME" >/dev/null 2>&1; then
  echo
  echo "Note: $BINDIR is not on your PATH."
  echo "Add this to your shell profile:"
  echo "  export PATH=\"$BINDIR:\$PATH\""
fi
