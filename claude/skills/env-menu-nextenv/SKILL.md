---
name: env-menu-nextenv
description: >
  Deep knowledge of .bashrc.menu.nextenv — the NextSilicon SDK environment
  switcher. Covers architecture, per-worktree cache isolation design, state
  management, startup apply, build flow, PS1 indicator, quick switcher, and
  known pitfalls. Trigger when the user asks about menu-nextenv, nextenv,
  switching NEXT_HOME/NEXTUTILS, worktree environments, or cache isolation.
---

# menu-nextenv — architecture and design notes

## What it does

`menu-nextenv` lets the user maintain multiple independent NextSilicon SDK
environments and switch between them in the live shell:

- **Main clone** — a single `sw/nextutils` repo per space (space2/3/4 or `$HOME`)
- **Standalone clone ("worktree")** — independent full clone under `sw/nextutils_wt/<branch>/`
- **sw-kit** — system-installed RPM under `/opt/nextsilicon`

Switching exports new `NEXT_HOME`/`NEXTUTILS`, patches `PATH`, updates all
derived vars (`NINJA`, `OBJDUMP`, etc.), redirects the four cache env vars to
the worktree's own directories, and updates `~/.cache` etc. symlinks.

## Key files

| File | Purpose |
|---|---|
| `.bashrc.menu.nextenv` | Entire menu implementation (sourced by `.bashrc.user`) |
| `.nextenv_state` | Persists active environment across shell restarts |
| `sw/nextutils_wt/<branch>/` | Root of each standalone clone |
| `sw/nextutils_wt/<branch>/next_home/` | NEXT_HOME for that clone |
| `swkit-install.sh` | Downloads and installs sw-kit RPMs from artifactory |

## Environment label format

Labels are always `<space>/<dir_name>` — e.g. `space4/master`, `home/feature_foo`.
This disambiguates when the same branch name exists on multiple spaces.

`_nextenv_startup_apply` auto-migrates old bare labels (e.g. `master`) by
comparing `NEXTENV_NEXTUTILS` against known bases and rewriting the state file.

## PS1 indicator

`get_nextenv_name` (defined in `.bashrc.menu.nextenv`) is called from
`PROMPT_COMMAND` via `fix-ps1` in `.bashrc.basic_funcs`. It returns
` [env:<label>]` when `NEXTENV_LABEL` is set, empty otherwise.

Prompt appearance:
```
adin@host ~/myproject [git-branch] [env:space4/master]$
adin@host ~/myproject [git-branch] [env:1.2.0]$    ← sw-kit active
adin@host ~/myproject [git-branch]$                ← no nextenv active
```

## Quick switcher — `nextenv-use`

```bash
nextenv-use                  # print current active env
nextenv-use space4/master    # switch by full label
nextenv-use master           # switch by bare name (first match)
nextenv-use swkit            # switch to installed sw-kit
```

Matches against full label, bare dir_name, or raw branch name. After switching,
`fix-ps1` picks up `NEXTENV_LABEL` automatically at the next prompt.

## Per-worktree cache isolation (critical design)

Each standalone clone owns **four real directories** (not symlinks to space):

```
sw/nextutils_wt/<branch>/
  .cache/       ← XDG_CACHE_HOME  (toolchain downloads etc.)
  .ccache/      ← CCACHE_DIR      (compiler cache)
  .conan2/      ← CONAN_HOME      (conan package cache)
  .uv_cache/    ← UV_CACHE_DIR    (uv/pip cache)
  next_home/    ← NEXT_HOME
```

**Why**: conan/ccache are tied to a specific compiler. Sharing the space cache
causes silent build corruption and makes it impossible to know which artifacts
are in use.

`XDG_CACHE_HOME` is also set independently in `.bashrc.user_env_vars` to
`/spaceN/users/$USER/.cache`. Without override it leaks into worktree builds.
`_nextenv_patch_env` overrides all four vars for worktree paths.

## `~` as an active-env pointer

`~/.cache`, `~/.ccache`, `~/.conan2` are symlinks pointing to the active
worktree's own directories. `_nextenv_sync_home_links <nu>` updates them on
every switch. It only touches entries that are already symlinks (safe on
machines without them) and guards against self-pointing with:
```bash
[[ "$target" == "$home_link" ]] && continue
```

If they become circular, restore manually:
```bash
ln -sfn /space3/users/adin/.{cache,ccache,conan2} ~/
```

## State file format

```
NEXTENV_TYPE=worktree
NEXTENV_LABEL=space4/master
NEXTENV_NEXT_HOME=/space4/users/adin/sw/nextutils_wt/master/next_home
NEXTENV_NEXTUTILS=/space4/users/adin/sw/nextutils_wt/master
```

Empty/missing = no active env. Written by `_nextenv_switch`, cleared by
`_nextenv_remove_worktree` when the active clone is deleted.

## Startup apply — `_nextenv_startup_apply`

1. **Unsets inherited `NEXTENV_*` vars first** — exported vars from a parent
   shell survive into child shells even when the state file is empty or points
   to a deleted path. Unset prevents stale apply.
2. Reads state file
3. Migrates old-format bare labels to `space/label`
4. Calls `_nextenv_patch_env` to update the shell

## Build flow

`_nextenv_add_worktree` full sequence on a fresh clone:
1. `git clone -b <branch>` (with `timeout 8 git ls-remote` pre-check; times out → assume remote branch exists)
2. `git submodule update --init --recursive`
3. Add build artifact dirs to `.git/info/exclude`
4. `mkdir -p` four real cache dirs + `next_home/`
5. `_nextenv_sync_home_links` — update `~` symlinks before build
6. Set all four cache env vars explicitly before the build subshell
7. `./setup.sh --default --force && ./setup.sh --fetch-all --create-buildtools-venv && ./build.sh --install --no-tests`
8. `_nextenv_switch "worktree" "<space>/<dir>" ...`

Option `c` retry logic:
- Checks `[[ -x .buildtools_venv/bin/conan ]]` (not just dir existence) — an
  incomplete venv (missing conan/click) runs `./setup.sh --default --force && ./setup.sh --create-buildtools-venv` first
- `_nextenv_prep_build` runs before every build: cleans stale uv `.tmp*` dirs
  and releases NFS lock files in `.buildtools_venv` via `fuser -TERM` / `fuser -KILL`

Seeding conan cache to avoid re-downloading (~600 MB) on a new clone:
```bash
rsync -a /space3/users/adin/.conan2/ ~/sw/nextutils_wt/<branch>/.conan2/
```

## Known pitfalls

| Symptom | Cause | Fix |
|---|---|---|
| Terminal hangs at startup | Inherited stale NEXTENV_* vars | `unset NEXTENV_*` in `_nextenv_startup_apply` |
| Terminal hangs (CARGO_HOME prompt) | `${CARGO_HOME}` always empty → `[ -d "" ]` false | Use `${CARGO_HOME:-${HOME}/.cargo}` |
| `[env:master]` on both space4 and home | Old bare label in state file | `_nextenv_startup_apply` auto-migrates on next start |
| conan uses space3 cache | `CONAN_HOME` not set before build subshell | Set all four cache vars in `_nextenv_add_worktree` before subshell |
| `ModuleNotFoundError: click` | Setup failed mid-way; venv dir exists but conan not installed | Check for `conan` binary not just venv dir |
| `[Errno 39] Directory not empty` (patch-ng) | Stale uv `.tmp*` from failed build | `_nextenv_prep_build` cleans them before every build |
| NFS lock blocks `setup.sh rm -rf .buildtools_venv` | Process holds `.nfs*` file | `_nextenv_prep_build` runs `fuser -TERM/-KILL` |
| `getcwd` fails after rm -rf active clone | Shell CWD inside deleted dir | `cd "$HOME"` before `rm -rf` and before `git clone` |
| Submodule dirs missing (CMake error) | `git clone` without submodule init | `git submodule update --init --recursive` after every clone |

## cdnext / cdutils alias ordering

These aliases depend on `NEXT_HOME`/`NEXTUTILS` which may be updated by
`_nextenv_startup_apply`. They are created **after** `_nextenv_startup_apply`
in `.bashrc.user` to avoid "Do nothing: path does not exist" warnings.
`_nextenv_patch_env` also refreshes them on every switch.
