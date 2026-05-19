# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

`~/env` is a shell environment bootstrapper for NextSilicon development machines. It provides:
- A structured `~/.bashrc` extension (`.bashrc.user`) that sources all helpers and menus on login
- Interactive menus for every common workflow (run, build, profile, SLURM, Claude, kokkos)
- Shared Claude Code skills that teach Claude how to drive those menus

## Bootstrap / install

```bash
# First-time setup on a new machine
./setup.sh        # symlinks .bashrc.user → ~/.bashrc.${USER} and sets up tmux
```

Then add to `~/.bashrc`:
```bash
source ~/.bashrc.${USER}
```

## Key files

| File | Purpose |
|---|---|
| `.bashrc.user` | Entry point — sources all other files, creates aliases, prompts for dirs |
| `.bashrc.user_env_vars` | All env vars: `NEXT_HOME`, `SW_HOME`, `NEXTUTILS`, `SPACE_PATH`, venv paths |
| `.bashrc.basic_funcs` | Color helpers (`echo_info`, `echo_error`, …) and `run_command`/`create_softlink` |
| `.bashrc.funcs` | SSH agent, driver load/unload, Rust/Python env setup, `slalloc` |
| `.bashrc.menu.main` | Top-level `menu` dispatcher |
| `.bashrc.menu.run` | `menu-run` — nextsystemd/nextloader, driver management, batch runs, history |
| `.bashrc.menu.env` | `menu-env` — clone/setup/build nextutils |
| `.bashrc.menu.profiler` | `menu-profiler` — profile analysis, InfluxDB/SQLite auto-detection |
| `.bashrc.menu.slurm` | `menu-slurm` — `salloc`/`scontrol` hardware allocation |
| `.bashrc.menu.kokkos` | `menu-kokkos` — clone/build/clean kokkos |
| `.bashrc.menu.claude` | `menu-claude` — install Claude, install skills, activate connectors |
| `.bashrc.tmux` | Tmux config; sourced by setup and by `.bashrc.user` |

## Important env vars (set in `.bashrc.user_env_vars`)

```
SHARED_SPACE_NAME   shared NFS mount root (e.g. space3)
NEXT_HOME           NextSilicon SDK install dir
SW_HOME             personal sw/ tree (kokkos, nextblas, nextutils, …)
NEXTUTILS           $SW_HOME/nextutils
SPACE_PATH          /$SHARED_SPACE_NAME/users/$USER/
_PY_VENV            private Python venv path
```

## Shell helper conventions

All scripts in this repo use helpers from `.bashrc.basic_funcs`. When writing new functions or scripts here, always use these instead of bare `echo` or `eval`:

```bash
echo_info    "message"    # blue  ℹ️
echo_success "message"    # green ✅
echo_warning "message"    # orange ⚠️
echo_error   "message"    # red ❌
echo_running "message"    # cyan 🔄

run_command <cmd>          # prints + runs + checks exit code
run_command_silent <cmd>   # runs + checks, no print on success
create_softlink <target> <link>
env_create_alias <name> <cmd>
env_create_dir <path>
```

## Menu structure

`menu` (top-level) → sub-menus:
- `menu-run` — start/stop nextsystemd, run nextloader, manage drivers, batch runs
- `menu-env` — nextutils clone → setup → build pipeline
- `menu-slurm` — allocate/reserve hardware via SLURM
- `menu-kokkos` — kokkos clone/build/clean
- `menu-claude` — install Claude CLI, install skills, start session in tmux
- `menu-profiler` — analyze/compare profile captures

All menus are recursive (re-display after each action) and return to main via option 1.

## History and batch files (menu-run)

`.history_nextloader` and `.history_nextsystemd` store `cwd<TAB>cmd` entries (max 100). Paths are normalized to env-var tokens (`$NEXTUTILS/…`) so entries survive space/host changes. `.batches/` holds named multi-command sequences. `.nextsystemd.pid` and `.nextsystemd.log` track the background nextsystemd process.

## Claude skills

Skills live in `claude/skills/<name>/SKILL.md` and are symlinked into `~/.claude/skills/` by `claude/skills/install-skills.sh`. Each `SKILL.md` has a `description:` frontmatter field — Claude triggers on it automatically, no slash command required.

To add a new skill: create `claude/skills/<name>/SKILL.md` with the frontmatter, then re-run `install-skills.sh`.

```bash
~/env/claude/skills/install-skills.sh            # symlink (default — gets updates from git pulls)
~/env/claude/skills/install-skills.sh --copy     # copy instead
~/env/claude/skills/install-skills.sh --uninstall
```

## Development host detection

`.bashrc.user` detects known dev hosts (`dev-sw04`, `dev-sw05`, `dev-sw02.il.nextsilicon.com`, `dev-sw07`) and only sets up Rust/Python venv prompts on those. On `slurm-client01` it launches `menu-slurm` immediately on login.
