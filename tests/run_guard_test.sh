#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

REPO_DIR="$TMP_DIR/repo"
WORKTREE_BASE="$TMP_DIR/worktrees"

mkdir -p "$REPO_DIR/tests" "$WORKTREE_BASE"
cp "$REPO_ROOT/tests/fixtures/hello.py" "$REPO_DIR/hello.py"
cp "$REPO_ROOT/tests/fixtures/tests/test_hello.py" "$REPO_DIR/tests/test_hello.py"

cd "$REPO_DIR"
git init -q
git config user.email "guard-test@example.com"
git config user.name "Guard Test"
git add .
git commit -m "Initial fixture" -q

cat > "$TMP_DIR/prompt.md" <<'EOF'
Test prompt for guard
EOF

WORKTREE_BASE="$WORKTREE_BASE" OPENCODE_CMD=true "$REPO_ROOT/helpers/opencode-worktree-guard.sh" \
  --session guard-test \
  --prompt "$TMP_DIR/prompt.md" \
  --allowed-directory tests/

WORKTREE_PATH="$WORKTREE_BASE/sessions/guard-test"
cd "$WORKTREE_PATH"

echo "# change" >> hello.py
git add hello.py
if git commit -m "Disallowed change" -q; then
  echo "ERROR: commit outside allowed directory should fail"
  exit 1
else
  echo "Expected failure for disallowed commit"
  git reset -q hello.py
fi

echo "# change" >> tests/test_hello.py
git add tests/test_hello.py
git commit -m "Allowed change" -q

echo "Guard test passed"
