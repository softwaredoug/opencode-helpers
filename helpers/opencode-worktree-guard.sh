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
#   ./opencode-worktree-guard.sh --markdown prompt.md
#   ./opencode-worktree-guard.sh --session my-session
#   ./opencode-worktree-guard.sh --session my-session --markdown prompt.md
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
POSITIONAL=()

usage() {
  echo "Usage: $0 [--prompt <prompt.md>] [--session <name>]"
  echo "       $0 <prompt.md>"
  echo "       $0 <session-name>"
  echo "       $0 <session-name> <prompt.md>"
  echo
  echo "Options:"
  echo "  -p, --prompt <path>     Markdown file used as initial prompt"
  echo "  -s, --session <name>    Session name to create or resume"
  echo "  -h, --help              Show this help text"
  echo
  echo "Behavior:"
  echo "  - Markdown only: creates a new session named after the file"
  echo "  - Session only: resumes the existing session worktree"
  echo "  - Both: creates a new session with the given name"
  echo "  - If both are provided and session exists, errors"
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
