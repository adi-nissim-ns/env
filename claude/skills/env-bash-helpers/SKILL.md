---
name: env-bash-helpers
description: Use when writing or editing shell scripts that live alongside `~/env` (or sourced from a shell that loads it). Provides the color/log helpers (`echo_info`, `echo_success`, `echo_warning`, `echo_error`, `echo_debug`, `echo_running`), `run_command`/`check_command`, `env_create_alias`, `env_create_dir`, `create_softlink`, and the script conventions they enforce.
---

# Bash helpers from `~/env/.bashrc.basic_funcs`

Every script in `~/env` sources `.bashrc.basic_funcs` and uses its helpers
instead of raw `echo` / inline status checks. Match that style when
writing or editing scripts in this repo.

## Script preamble

```bash
#!/bin/bash
_ENV_PROJECT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
source "${_ENV_PROJECT_DIR}/.bashrc.basic_funcs"
```

`readlink -f` resolves symlinks → the script works whether invoked
directly or through a symlink in `~/.local/bin`, `~/.claude/skills`, etc.

## Echo helpers (color + emoji prefix)

| Helper             | Color   | Prefix | Use for                          |
| ------------------ | ------- | ------ | -------------------------------- |
| `echo_info`        | blue    | ℹ️     | neutral information              |
| `echo_warning`     | orange  | ⚠️     | recoverable issues               |
| `echo_error`       | red     | ❌     | failures                         |
| `echo_success`     | green   | ✅     | positive completion              |
| `echo_debug`       | magenta | 🔍     | debug-only output                |
| `echo_running`     | cyan    | 🔄     | "starting to run X"              |

All accept multiple args (`echo_info "foo" "bar"`) — they're joined with
spaces.

## Command runners

```bash
run_command <cmd...>        # echo_running, eval, then check_command (prints ✅/❌)
run_command_silent <cmd...> # eval, only prints on failure
check_command "<label>"     # checks $? after a manual call
```

Use `run_command` for any user-visible step in a menu/setup script.
Use `run_command_silent` for chatty/internal steps you don't want
to log unless they fail.

## Filesystem helpers

```bash
env_create_dir <path>       # mkdir -p, but no-op on host slurm-client01
create_softlink <target> <link>
                            # ln -s only if <link> doesn't already exist
env_create_alias <name> <command>
                            # alias if not already aliased (silent reassignment)
env_create_cd_alias <name> <dir>
                            # env_create_alias <name> "cd <dir>", but only if dir exists
```

These are all idempotent — re-running the setup is safe.

## Prompt styling

`fix-ps1` (defined in the same file) rewrites `PROMPT_COMMAND` to show:

```
(venv-name) user@host /cwd [git-branch]$
```

Call it once per shell; it sets `PROMPT_COMMAND` so the prompt updates
itself.

## Conventions worth keeping

- Always quote `${BASH_SOURCE[0]}` and `readlink -f` arguments — paths can
  contain spaces.
- Don't use `echo`/`printf` directly for user-facing output in env
  scripts — use the matching helper, so colors and emoji stay consistent.
- Set `set -u` at the top of new scripts. Avoid `set -e` here because
  many helpers intentionally check `$?` themselves.
- Prefer `cd "$_saved_pwd"` over `popd` — the run-menu helpers track the
  caller's `$PWD` manually to survive errors in subshell history menus.
