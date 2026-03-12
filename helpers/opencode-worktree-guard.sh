#!/usr/bin/env bash
set -euo pipefail

############################################################
# opencode-worktree-guard.sh
#
# Creates a controlled git worktree for an AI coding agent
# where commits are restricted to a specific directory.
#
# This is useful for:
#   - test-improving agents
#   - refactoring isolated modules
#   - preventing reward hacking
#
# Usage:
#
#   ./opencode-worktree-guard.sh tests/
#
# Optional environment variables:
#
#   BRANCH_PREFIX   prefix for new branches
#   WORKTREE_BASE   directory where worktrees are created
#   OPENCODE_CMD    command used to start opencode
#
############################################################


ALLOWED_DIR="${1:-}"

if [[ -z "$ALLOWED_DIR" ]]; then
  echo "Usage: $0 <allowed-directory>"
  exit 1
fi


############################################################
# Ensure required tools exist
############################################################

if ! command -v git >/dev/null 2>&1; then
  echo "git must be installed"
  exit 1
fi


############################################################
# Ensure we are inside a git repository
############################################################

if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "This script must be run inside a git repository"
  exit 1
fi


REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"


############################################################
# Normalize the allowed directory path
############################################################

ALLOWED_DIR="${ALLOWED_DIR#./}"
ALLOWED_DIR="${ALLOWED_DIR%/}/"

if [[ ! -d "$ALLOWED_DIR" ]]; then
  echo "Directory does not exist: $ALLOWED_DIR"
  exit 1
fi


############################################################
# Configuration
############################################################

BRANCH_PREFIX="${BRANCH_PREFIX:-agent}"
WORKTREE_BASE="${WORKTREE_BASE:-$REPO_ROOT/.worktrees}"
OPENCODE_CMD="${OPENCODE_CMD:-opencode}"

STAMP="$(date +%Y%m%d-%H%M%S)"

SAFE_NAME="$(echo "$ALLOWED_DIR" | tr '/ ' '--' | tr -cd '[:alnum:]_.-')"

BRANCH_NAME="${BRANCH_PREFIX}/${SAFE_NAME}-${STAMP}"

WORKTREE_PATH="${WORKTREE_BASE}/${SAFE_NAME}-${STAMP}"


mkdir -p "$WORKTREE_BASE"


############################################################
# Create worktree
############################################################

echo "Creating git worktree..."

git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH"


############################################################
# Install commit guard
############################################################

HOOK_PATH="$WORKTREE_PATH/.git/hooks/pre-commit"

cat > "$HOOK_PATH" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail

ALLOWED_DIR="__ALLOWED_DIR__"

# Collect staged files
mapfile -t STAGED_FILES < <(git diff --cached --name-only)

if [[ ${#STAGED_FILES[@]} -eq 0 ]]; then
  exit 0
fi

VIOLATIONS=()

for f in "${STAGED_FILES[@]}"; do
  f="${f#./}"

  case "$f" in
    "$ALLOWED_DIR"*)
      ;;
    *)
      VIOLATIONS+=("$f")
      ;;
  esac
done


if [[ ${#VIOLATIONS[@]} -gt 0 ]]; then
  echo
  echo "Commit rejected."
  echo "Only files under '$ALLOWED_DIR' may be modified."
  echo

  for v in "${VIOLATIONS[@]}"; do
    echo "  $v"
  done

  echo
  exit 1
fi

exit 0
HOOK


# Inject allowed directory into hook
sed -i.bak "s|__ALLOWED_DIR__|$ALLOWED_DIR|" "$HOOK_PATH"
rm "$HOOK_PATH.bak"

chmod +x "$HOOK_PATH"


############################################################
# Launch OpenCode session
############################################################

PROMPT="You will be working on improving $ALLOWED_DIR per user instructions. You are only allowed to modify this directory."

echo
echo "-----------------------------------------"
echo "Worktree created"
echo "-----------------------------------------"
echo "Branch:        $BRANCH_NAME"
echo "Worktree:      $WORKTREE_PATH"
echo "Allowed dir:   $ALLOWED_DIR"
echo
echo "Starting OpenCode..."
echo "-----------------------------------------"
echo


cd "$WORKTREE_PATH"

if "$OPENCODE_CMD" "$PROMPT"; then
  exit 0
fi


############################################################
# Fallback if opencode CLI does not support prompt argument
############################################################

echo
echo "OpenCode launched without initial prompt."
echo "Paste the following instruction:"
echo
echo "$PROMPT"
echo

exec "$OPENCODE_CMD"
