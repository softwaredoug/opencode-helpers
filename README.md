# opencode-worktree-guard

Create a git worktree per OpenCode session and launch OpenCode with a named session or a markdown prompt. Each session maps to a dedicated worktree under `.worktrees/sessions/`.

## Usage

```bash
./helpers/opencode-worktree-guard.sh --prompt prompt.md
./helpers/opencode-worktree-guard.sh --session my-session
./helpers/opencode-worktree-guard.sh --session my-session --prompt prompt.md
./helpers/opencode-worktree-guard.sh --prompt prompt.md --allowed-directory tests/
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
- If allowed-directory is provided, a pre-commit guard blocks commits outside it.
- If allowed-directory is provided, OpenCode edits are restricted to that directory.

## Options

- `-p, --prompt <path>`: markdown file used as the initial prompt (must end with `.md` or `.markdown`).
- `-s, --session <name>`: session name to create or resume.
- `-a, --allowed-directory <path>`: only allow commits inside this directory and subdirectories.
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

Create a session with an allowed directory guard:

```bash
./helpers/opencode-worktree-guard.sh --prompt docs/todo.md --allowed-directory docs/
```

Note: when `--allowed-directory` is set, the script writes `opencode.json` in the worktree and sets `permission.edit` to deny all paths except the allowed directory.
