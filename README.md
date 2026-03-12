# opencode-worktree-guard

Create a git worktree per OpenCode session and launch OpenCode with a named session or a markdown prompt. Each session maps to a dedicated worktree under `.worktrees/sessions/`.

## Usage

```bash
./helpers/opencode-worktree-guard.sh --prompt prompt.md
./helpers/opencode-worktree-guard.sh --session my-session
./helpers/opencode-worktree-guard.sh --session my-session --prompt prompt.md
```

Positional shorthands:

```bash
./helpers/opencode-worktree-guard.sh prompt.md
./helpers/opencode-worktree-guard.sh my-session
./helpers/opencode-worktree-guard.sh my-session prompt.md
```

## Behavior

- Prompt only: creates a new session named after the markdown file.
- Session only: resumes the existing session worktree.
- Both: creates a new session with the given name and markdown prompt.
- If both are provided and the session already exists, the script exits with an error.

## Options

- `-p, --prompt <path>`: markdown file used as the initial prompt (must end with `.md` or `.markdown`).
- `-s, --session <name>`: session name to create or resume.
- `-h, --help`: show help text.

## Environment variables

- `BRANCH_PREFIX`: prefix for new branches (default: `session`).
- `WORKTREE_BASE`: directory where worktrees are created (default: `.worktrees` in repo root).
- `OPENCODE_CMD`: command used to start OpenCode (default: `opencode`).
- `OPENCODE_SESSION_FLAG`: flag passed to OpenCode to set the session name (default: `--session`).

## Examples

Create a session from a prompt file:

```bash
./helpers/opencode-worktree-guard.sh --prompt docs/todo.md
```

Resume a session:

```bash
./helpers/opencode-worktree-guard.sh --session docs-todo
```
