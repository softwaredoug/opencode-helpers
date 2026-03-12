#!/usr/bin/env bash
set -euo pipefail

BINDIR="${BINDIR:-$HOME/.local/bin}"
TARGET_NAME="${TARGET_NAME:-opencode-worktree-guard}"
TARGET_PATH="$BINDIR/$TARGET_NAME"

if [[ -L "$TARGET_PATH" || -f "$TARGET_PATH" ]]; then
  rm -f "$TARGET_PATH"
  echo "Removed $TARGET_PATH"
else
  echo "Nothing to remove at $TARGET_PATH"
fi
