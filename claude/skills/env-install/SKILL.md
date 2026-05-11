---
name: env-install
description: Use when the user wants to install, set up, or bootstrap the `~/env` shell environment on a new machine. Covers cloning the repo, running setup.sh, the per-user .bashrc symlink, tmux config, and the optional Claude Code install.
---

# Installing the `~/env` shell environment

The `~/env` repo is a personal shell environment: bash menus (`menu`,
`menu-env`, `menu-run`, `menu-slurm`, `menu-kokkos`), color/log helpers
(`echo_info`, `run_command`, …), tmux config, and convenience aliases
(`cdsw`, `cdnext`, `cdutils`).

## Bootstrap checklist

1. **Clone the repo into the user's home.** Always at `~/env` — many
   scripts use this path:
   ```bash
   git clone <env-repo-url> ~/env
   ```

2. **Run setup.sh.** It creates a `~/.bashrc.${USER}` symlink pointing at
   `~/env/.bashrc.user`, drops a default `~/.gitconfig` if none exists,
   and sources the tmux config:
   ```bash
   cd ~/env && ./setup.sh
   ```

3. **Source the user bashrc.** The user's main `~/.bashrc` must source
   `~/.bashrc.${USER}` — check it and add the line if missing:
   ```bash
   # in ~/.bashrc
   [ -f ~/.bashrc.${USER} ] && source ~/.bashrc.${USER}
   ```

4. **Open a fresh shell.** The main menu loads on shell start:
   ```bash
   exec bash -l
   menu       # should display the main menu
   ```

5. *(optional)* **Install Claude Code:**
   ```bash
   ~/env/claude-install.sh
   ```

6. *(optional)* **Install env-aware Claude skills:**
   ```bash
   ~/env/claude/skills/install-skills.sh
   ```

## Common gotchas

- `setup.sh` is idempotent — safe to re-run.
- It uses `create_softlink` from `.bashrc.basic_funcs`, which only creates
  a link if the target doesn't already exist. To replace a stale link,
  delete it first.
- `_ENV_PROJECT_DIR` is resolved via `readlink -f` of the script's own
  path, so you can run `setup.sh` from anywhere — never hardcode the path.
- If `~/.gitconfig` already exists, setup will not overwrite it.

## When the user just wants the install commands

Quote the four lines from steps 1–3 and stop. Don't recite the whole
checklist unless they ask.
