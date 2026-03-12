#!/usr/bin/env bash
set -euo pipefail

############################################################
# opencode-worktree-guard.sh
#
# Creates a git worktree per OpenCode session and launches
# OpenCode with either a session name or a markdown prompt.
#
# Usage:
#
#   ./opencode-worktree-guard.sh --prompt prompt.md
#   ./opencode-worktree-guard.sh --session my-session
#   ./opencode-worktree-guard.sh --session my-session --prompt prompt.md
#   ./opencode-worktree-guard.sh --prompt prompt.md --allowed-directory tests/
#   ./opencode-worktree-guard.sh --session my-session --allowed-directory tests/
#
# Positional shorthands:
#   ./opencode-worktree-guard.sh prompt.md
#   ./opencode-worktree-guard.sh my-session
#   ./opencode-worktree-guard.sh my-session prompt.md
#
# Optional environment variables:
#
#   BRANCH_PREFIX         prefix for new branches
#   WORKTREE_BASE         directory where worktrees are created
#   OPENCODE_CMD          command used to start opencode
#   OPENCODE_SESSION_FLAG flag used to set session name
#
############################################################


MARKDOWN_PATH=""
SESSION_NAME=""
ALLOWED_DIR=""
POSITIONAL=()

usage() {
  echo "Usage: $0 [--prompt <prompt.md>] [--session <name>] [--allowed-directory <path>]"
  echo "       $0 <prompt.md>"
  echo "       $0 <session-name>"
  echo "       $0 <session-name> <prompt.md>"
  echo
  echo "Options:"
  echo "  -p, --prompt <path>     Markdown file used as initial prompt"
  echo "  -s, --session <name>    Session name to create or resume"
  echo "  -a, --allowed-directory <path>"
  echo "                          Directory allowed to be committed"
  echo "  -h, --help              Show this help text"
  echo
  echo "Behavior:"
  echo "  - Markdown only: creates a new session named after the file"
  echo "  - Session only: resumes the existing session worktree"
  echo "  - Both: creates a new session with the given name"
  echo "  - If both are provided and session exists, errors"
  echo "  - If allowed-directory is provided, install a pre-commit guard"
  echo "    and restrict OpenCode edits to that directory"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--prompt)
      MARKDOWN_PATH="${2:-}"
      shift 2
      ;;
    -s|--session)
      SESSION_NAME="${2:-}"
      shift 2
      ;;
    -a|--allowed-directory)
      ALLOWED_DIR="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      POSITIONAL+=("$@")
      break
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

if [[ -z "$MARKDOWN_PATH" && -z "$SESSION_NAME" ]]; then
  if [[ ${#POSITIONAL[@]} -eq 1 ]]; then
    if [[ "${POSITIONAL[0]}" == *.md || "${POSITIONAL[0]}" == *.markdown ]]; then
      MARKDOWN_PATH="${POSITIONAL[0]}"
    else
      SESSION_NAME="${POSITIONAL[0]}"
    fi
  elif [[ ${#POSITIONAL[@]} -eq 2 ]]; then
    SESSION_NAME="${POSITIONAL[0]}"
    MARKDOWN_PATH="${POSITIONAL[1]}"
  elif [[ ${#POSITIONAL[@]} -gt 0 ]]; then
    usage
    exit 1
  fi
else
  if [[ ${#POSITIONAL[@]} -gt 0 ]]; then
    usage
    exit 1
  fi
fi

if [[ -z "$MARKDOWN_PATH" && -z "$SESSION_NAME" ]]; then
  usage
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
# Validate inputs
############################################################

if [[ -n "$MARKDOWN_PATH" ]]; then
  if [[ ! -f "$MARKDOWN_PATH" ]]; then
    echo "Markdown file not found: $MARKDOWN_PATH"
    exit 1
  fi

  case "$MARKDOWN_PATH" in
    *.md|*.markdown)
      ;;
    *)
      echo "Markdown file must end with .md or .markdown"
      exit 1
      ;;
  esac
fi

if [[ -z "$SESSION_NAME" && -n "$MARKDOWN_PATH" ]]; then
  MARKDOWN_BASENAME="${MARKDOWN_PATH##*/}"
  SESSION_NAME="${MARKDOWN_BASENAME%.*}"
fi

if [[ -z "$SESSION_NAME" ]]; then
  echo "Session name could not be determined"
  exit 1
fi

if [[ -n "$ALLOWED_DIR" ]]; then
  if [[ "$ALLOWED_DIR" == /* ]]; then
    if [[ "$ALLOWED_DIR" != "$REPO_ROOT/"* ]]; then
      echo "Allowed directory must be inside the repo: $ALLOWED_DIR"
      exit 1
    fi
    ALLOWED_DIR="${ALLOWED_DIR#"$REPO_ROOT"/}"
  fi

  ALLOWED_DIR="${ALLOWED_DIR#./}"
  ALLOWED_DIR="${ALLOWED_DIR%/}/"

  if [[ -z "$ALLOWED_DIR" ]]; then
    echo "Allowed directory cannot be empty"
    exit 1
  fi

  if [[ ! -d "$ALLOWED_DIR" ]]; then
    echo "Directory does not exist: $ALLOWED_DIR"
    exit 1
  fi
fi


############################################################
# Configuration
############################################################

BRANCH_PREFIX="${BRANCH_PREFIX:-session}"
WORKTREE_BASE="${WORKTREE_BASE:-$REPO_ROOT/.worktrees}"
OPENCODE_CMD="${OPENCODE_CMD:-opencode}"
OPENCODE_SESSION_FLAG="${OPENCODE_SESSION_FLAG:---session}"

SAFE_SESSION_NAME="$(echo "$SESSION_NAME" | tr '/ ' '--' | tr -cd '[:alnum:]_.-')"

if [[ -z "$SAFE_SESSION_NAME" ]]; then
  echo "Session name must include at least one alphanumeric character"
  exit 1
fi

SESSION_ROOT="${WORKTREE_BASE}/sessions"
WORKTREE_PATH="${SESSION_ROOT}/${SAFE_SESSION_NAME}"
BRANCH_NAME="${BRANCH_PREFIX}/${SAFE_SESSION_NAME}"

mkdir -p "$SESSION_ROOT"


############################################################
# Ensure session/worktree state
############################################################

worktree_exists() {
  local target="$1"
  while IFS= read -r line; do
    if [[ "$line" == worktree\ * ]]; then
      local path="${line#worktree }"
      if [[ "$path" == "$target" ]]; then
        return 0
      fi
    fi
  done < <(git worktree list --porcelain)
  return 1
}

session_exists=false
if worktree_exists "$WORKTREE_PATH"; then
  session_exists=true
elif [[ -e "$WORKTREE_PATH" ]]; then
  echo "Worktree path exists but is not registered with git: $WORKTREE_PATH"
  exit 1
fi

if [[ -n "$MARKDOWN_PATH" ]]; then
  if [[ "$session_exists" == true ]]; then
    echo "Session already exists: $SESSION_NAME"
    exit 1
  fi

  if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
    echo "Branch already exists for session: $BRANCH_NAME"
    exit 1
  fi

  echo "Creating git worktree for session..."
  git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH"
else
  if [[ "$session_exists" != true ]]; then
    echo "Session not found: $SESSION_NAME"
    exit 1
  fi
fi


############################################################
# Install pre-commit guard
############################################################

install_pre_commit_wrapper() {
  local hook_root
  hook_root="$(git -C "$WORKTREE_PATH" rev-parse --git-path hooks)"
  local hook_dir="$hook_root/pre-commit.d"
  local hook_path="$hook_root/pre-commit"
  local legacy_hook="$hook_dir/legacy-pre-commit"
  local wrapper_marker="opencode-worktree-guard wrapper"

  mkdir -p "$hook_dir"

  if [[ -f "$hook_path" && ! -L "$hook_path" ]]; then
    if ! grep -q "$wrapper_marker" "$hook_path"; then
      if [[ ! -f "$legacy_hook" ]]; then
        mv "$hook_path" "$legacy_hook"
        chmod +x "$legacy_hook"
      else
        local stamp
        stamp="$(date +%Y%m%d-%H%M%S)"
        mv "$hook_path" "$hook_dir/legacy-pre-commit-$stamp"
      fi
    fi
  fi

  cat > "$hook_path" <<'HOOK'
#!/usr/bin/env bash
# opencode-worktree-guard wrapper
set -euo pipefail

HOOK_DIR="__HOOK_DIR__"
LEGACY_HOOK="$HOOK_DIR/legacy-pre-commit"

if [[ -x "$LEGACY_HOOK" ]]; then
  "$LEGACY_HOOK"
fi

shopt -s nullglob
for hook in "$HOOK_DIR"/*; do
  if [[ "$hook" == "$LEGACY_HOOK" ]]; then
    continue
  fi
  if [[ -x "$hook" ]]; then
    "$hook"
  fi
done
HOOK

  sed -i.bak "s|__HOOK_DIR__|$hook_dir|" "$hook_path"
  rm "$hook_path.bak"
  chmod +x "$hook_path"
}

install_allowed_directory_guard() {
  local hook_root
  hook_root="$(git -C "$WORKTREE_PATH" rev-parse --git-path hooks)"
  local hook_dir="$hook_root/pre-commit.d"
  local guard_path="$hook_dir/guard-allowed-directory"

  mkdir -p "$hook_dir"

  cat > "$guard_path" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail

ALLOWED_DIR="__ALLOWED_DIR__"

STAGED_FILES="$(git diff --cached --name-only)"

if [[ -z "$STAGED_FILES" ]]; then
  exit 0
fi

VIOLATIONS=()

while IFS= read -r f; do
  f="${f#./}"

  case "$f" in
    "$ALLOWED_DIR"*)
      ;;
    *)
      VIOLATIONS+=("$f")
      ;;
  esac
done <<< "$STAGED_FILES"

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
HOOK

  sed -i.bak "s|__ALLOWED_DIR__|$ALLOWED_DIR|" "$guard_path"
  rm "$guard_path.bak"
  chmod +x "$guard_path"
}

if [[ -n "$ALLOWED_DIR" ]]; then
  install_pre_commit_wrapper
  install_allowed_directory_guard
fi


############################################################
# Configure OpenCode permissions
############################################################

install_opencode_permissions() {
  local config_path="$WORKTREE_PATH/opencode.json"

  python - "$config_path" "$ALLOWED_DIR" <<'PY'
import json
import os
import sys

config_path = sys.argv[1]
allowed_dir = sys.argv[2]
allowed_pattern = f"{allowed_dir}**"

data = {}
if os.path.exists(config_path):
    with open(config_path, "r", encoding="utf-8") as handle:
        try:
            data = json.load(handle)
        except json.JSONDecodeError as exc:
            print(f"Invalid JSON in {config_path}: {exc}")
            sys.exit(1)

permission = data.get("permission", {})
if isinstance(permission, str):
    permission = {"*": permission}
if not isinstance(permission, dict):
    permission = {}

permission["edit"] = {"*": "deny", allowed_pattern: "allow"}
data["permission"] = permission

with open(config_path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, ensure_ascii=True)
    handle.write("\n")
PY
}

if [[ -n "$ALLOWED_DIR" ]]; then
  install_opencode_permissions
fi


############################################################
# Launch OpenCode session
############################################################

PROMPT=""
if [[ -n "$MARKDOWN_PATH" ]]; then
  PROMPT="$(<"$MARKDOWN_PATH")"
fi

echo
echo "-----------------------------------------"
if [[ "$session_exists" == true && -z "$MARKDOWN_PATH" ]]; then
  echo "Session resumed"
else
  echo "Session created"
fi
echo "-----------------------------------------"
echo "Session:       $SESSION_NAME"
echo "Branch:        $BRANCH_NAME"
echo "Worktree:      $WORKTREE_PATH"
if [[ -n "$MARKDOWN_PATH" ]]; then
  echo "Markdown:      $MARKDOWN_PATH"
fi
if [[ -n "$ALLOWED_DIR" ]]; then
  echo "Allowed dir:   $ALLOWED_DIR"
fi
echo
echo "Starting OpenCode..."
echo "-----------------------------------------"
echo


cd "$WORKTREE_PATH"

OPENCODE_ARGS=()
if [[ -n "$SESSION_NAME" ]]; then
  OPENCODE_ARGS+=("$OPENCODE_SESSION_FLAG" "$SESSION_NAME")
fi

if [[ -n "$PROMPT" ]]; then
  if "$OPENCODE_CMD" "${OPENCODE_ARGS[@]}" "$PROMPT"; then
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
  exec "$OPENCODE_CMD" "${OPENCODE_ARGS[@]}"
else
  exec "$OPENCODE_CMD" "${OPENCODE_ARGS[@]}"
fi
