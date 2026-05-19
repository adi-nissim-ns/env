---
name: env-menu-nextenv
description: >
  Deep knowledge of .bashrc.menu.nextenv — the NextSilicon SDK environment
  switcher. Covers architecture, per-worktree cache isolation design, state
  management, startup apply, build flow, PS1 indicator, quick switcher, devpod
  workspace support, cross-machine state isolation, binfmt management, and
  known pitfalls. Trigger when the user asks about menu-nextenv, nextenv,
  switching NEXT_HOME/NEXTUTILS, worktree environments, cache isolation,
  devpod, or workspace.
---

# menu-nextenv — architecture and design notes

## What it does

`menu-nextenv` lets the user maintain multiple independent NextSilicon SDK
environments and switch between them in the live shell:

- **Main clone** — a single `sw/nextutils` repo per space (space2/3/4 or `$HOME`)
- **Standalone clone ("worktree")** — independent full clone under `sw/nextutils_wt/<branch>/`
- **Devpod workspace clone** — clone under `/workspace/$USER/sw/nextutils_wt/<branch>/` (fast local SSD on devpod)
- **sw-kit** — system-installed RPM under `/opt/nextsilicon`

Switching exports new `NEXT_HOME`/`NEXTUTILS`, patches `PATH`, updates all
derived vars (`NINJA`, `OBJDUMP`, MPI vars, etc.), redirects the four cache
env vars to the worktree's own directories, updates `~/.cache` etc. symlinks,
and manages binfmt.

## Key files

| File | Purpose |
|---|---|
| `.bashrc.menu.nextenv` | Entire menu implementation (sourced by `.bashrc.user`) |
| `.nextenv_state.<hostname>` | Per-machine state file — persists active env across shell restarts |
| `sw/nextutils_wt/<branch>/` | Root of each standalone clone (NFS spaces) |
| `/workspace/$USER/sw/nextutils_wt/<branch>/` | Devpod-local fast clone |
| `swkit-install.sh` | Downloads and installs sw-kit RPMs from artifactory |

## Per-hostname state files (cross-machine isolation)

The state file is `${_ENV_PROJECT_DIR}/.nextenv_state.$(hostname -s)` — one
file per machine. All files live in the NFS-shared `~/env/` dir, keyed by
hostname.

**Why**: a single shared state file caused sw-kit state (devpod) to bleed onto
dev-sw05 and VMs where sw-kit isn't installed, producing warnings and prompts.

### First-run migration

`_nextenv_startup_apply` on first run:
1. If `.nextenv_state.<hostname>` doesn't exist but `.nextenv_state` (old shared
   file) exists → copy it as a one-time migration
2. If neither exists → call `_nextenv_auto_detect`

### Auto-detect on fresh machines

`_nextenv_auto_detect`: if sw-kit is installed → activate it silently. Otherwise
leave env clean (user picks via menu). Called on first login to a new machine.

### sw-kit-not-installed guard

If the state file says `swkit` but `/opt/nextsilicon` doesn't exist (sw-kit not
installed on this machine), `_nextenv_startup_apply` deletes the state file and
calls `_nextenv_auto_detect` instead of warning and trying to apply a stale state.

## Environment label format

Labels are always `<space>/<dir_name>` — e.g. `space4/master`, `home/feature_foo`,
`workspace/master`.

`_nextenv_startup_apply` auto-migrates old bare labels (e.g. `master`) by
comparing `NEXTENV_NEXTUTILS` against known bases and rewriting the state file.

## Known bases

`_nextenv_known_bases` emits:
- `/space2/users/$USER`, `/space3/users/$USER`, `/space4/users/$USER` — if `sw/` exists
- `/workspace/$USER` — if the directory exists (devpod native or SSHFS-mounted)
- `$HOME` — always (created on demand)

`_nextenv_space_name` maps them to short labels: `space3`, `space4`, `workspace`, `home`.

## Devpod workspace (`/workspace/$USER`)

On the devpod, `/workspace/$USER` is fast local SSD storage. Clones built there
show as `workspace/<branch>` in the menu and PS1.

On other machines (dev-sw05 etc.), the workspace can be SSHFS-mounted from the
devpod using menu options `e`/`f`. After mounting, workspace builds become visible
in the menu on that machine too.

### Menu options e / f

`e` — Mount devpod `/workspace` here via SSHFS. Run on dev-sw05/servers (not on
the devpod itself). Uses `_nextenv_devpod_info` to auto-discover IP/port via
`devpodctl info` (`/tools/qemu/scripts/devpodctl`).

`f` — Unmount devpod `/workspace` (`fusermount -u -z`).

## PS1 indicator

`get_nextenv_name` (defined in `.bashrc.menu.nextenv`) is called from
`PROMPT_COMMAND` via `fix-ps1` in `.bashrc.basic_funcs`. It returns
` [env:<label>]` when `NEXTENV_LABEL` is set, empty otherwise.

Prompt appearance:
```
adin@host [env:space4/master] ~/myproject [git-branch]$
adin@host [env:1.0.2-6182]   ~/myproject [git-branch]$   ← sw-kit active
adin@host                    ~/myproject [git-branch]$    ← no nextenv active
```

## Quick switcher — `nextenv-use`

```bash
nextenv-use                        # print current active env
nextenv-use space4/master          # switch by full label (saves to state file)
nextenv-use master                 # switch by bare name (first match)
nextenv-use swkit                  # switch to installed sw-kit
nextenv-use --local space4/master  # switch this terminal only — no state file write
```

`--local` calls `_nextenv_switch_local` which exports `NEXTENV_*` and patches env
but does NOT write the state file. Other terminals and new shells are unaffected.
Menu option `g` does the same interactively.

## sw-kit version detection

`_nextenv_find_swkits` queries:
1. RPM `next-sw-kit`/`ns-sw-kit` (older package name format)
2. Falls back to `nextruntime`/`nextdriver` RPM version (current format: `1.0.2-6182`)
3. Falls back to `"unknown"`

`_nextenv_startup_apply` migrates the old `"installed"` label to the real version
on first run after upgrade.

## `_nextenv_patch_env` — full set of vars updated on every switch

When `NEXT_HOME` changes, all of these are updated:

| Var | Value |
|---|---|
| `NEXT_HOME` | `$new_nh` |
| `PATH` | old NEXT_HOME entries removed, new `$NEXT_HOME/bin` prepended |
| `OPAL_PREFIX` | `$NEXT_HOME` |
| `MPI_HOME` | `$NEXT_HOME` |
| `OMPI_CC` | `$NEXT_HOME/bin/nextcc` |
| `OMPI_FC` | `$NEXT_HOME/bin/nextfort` |
| `OMPI_CXX` | `$NEXT_HOME/bin/nextcxx` |
| `NEXTCRT_SOURCE` | `$NEXT_HOME/src` |
| `NEXT_LLVM_SOURCE` | `$NEXT_HOME/llvm` |
| `SYSROOT_PATH` | `$NEXT_HOME/sysroot/usr` |
| `OBJDUMP` | `$NEXT_HOME/llvm/bin/objdump` |
| `DIS` | `$NEXT_HOME/llvm/bin/llvm-dis` |

When `NEXTUTILS` changes:
- `NINJA` → `$NEXTUTILS/.buildtools_venv/bin/ninja`

Cache vars (worktree only):
- `CONAN_HOME`, `UV_CACHE_DIR`, `XDG_CACHE_HOME`, `CCACHE_DIR` → worktree-local dirs

## binfmt management

`_nextenv_patch_env` manages `/proc/sys/fs/binfmt_misc/nextloader` on every switch:

- **Switch to worktree** → disable binfmt (`echo -1 | sudo tee …`) — build.sh
  refuses to run if binfmt is registered
- **Switch to sw-kit** → re-enable via `sudo systemctl restart systemd-binfmt`
  (re-reads sw-kit's registration from `/etc/binfmt.d/`)

Runs on startup too (via `_nextenv_startup_apply` → `_nextenv_patch_env`), so
entering a machine with the wrong binfmt state is corrected automatically.

## sw-kit system-level footprint

Items the sw-kit installer sets up and their management status:

| Item | Managed by |
|---|---|
| `/proc/sys/fs/binfmt_misc/nextloader` | `_nextenv_patch_env` (auto) |
| `/etc/profile.d/nextsilicon.sh` vars | `_nextenv_patch_env` fully overrides all |
| `nextsilicon.drivers.service` (autoload) | `menu-run` (separate) |
| `/etc/modprobe.d/nextdriver-blacklist.conf` | static, no action needed |
| Bind mounts `/opt/next_home`, `/opt/nextutils` | devpod-specific, separate concern |

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
causes silent build corruption.

`XDG_CACHE_HOME` is also set independently in `.bashrc.user_env_vars` to
`/spaceN/users/$USER/.cache`. Without override it leaks into worktree builds.
`_nextenv_patch_env` overrides all four vars for worktree paths.

## `~` as an active-env pointer

`~/.cache`, `~/.ccache`, `~/.conan2` are symlinks pointing to the active
worktree's own directories. `_nextenv_sync_home_links <nu>` updates them on
every switch. It only touches entries that are already symlinks and guards
against self-pointing:
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

1. **Unsets inherited `NEXTENV_*` vars** — prevents stale parent-shell state
2. Per-hostname file missing → migrate old shared file or auto-detect
3. Reads state file
4. sw-kit guard: if `swkit` type but no `/opt/nextsilicon` → clear + auto-detect
5. Migrate `"installed"` sw-kit label → real RPM version
6. Migrate old bare labels → `space/label`
7. Calls `_nextenv_patch_env` (which also manages binfmt)

## Build flow

`_nextenv_add_worktree` full sequence on a fresh clone:
1. `timeout 8 git ls-remote` pre-check (timeout → assume branch exists)
2. `git clone -b <branch>`
3. `git submodule update --init --recursive`
4. Add build artifact dirs to `.git/info/exclude`
5. `mkdir -p` four real cache dirs + `next_home/`
6. `_nextenv_sync_home_links` — update `~` symlinks before build
7. Set all four cache env vars explicitly before the build subshell
8. `./setup.sh --default --force && ./setup.sh --fetch-all --create-buildtools-venv && ./build.sh --install --no-tests`
9. `_nextenv_switch "worktree" "<space>/<dir>" ...`

Option `c` retry logic:
- Checks `[[ -x .buildtools_venv/bin/conan ]]` (not just dir existence) — an
  incomplete venv runs `./setup.sh --default --force && ./setup.sh --create-buildtools-venv` first
- `_nextenv_prep_build` runs before every build: cleans stale uv `.tmp*` dirs
  and releases NFS lock files via `fuser -TERM` / `fuser -KILL`

Seeding conan cache to avoid re-downloading (~600 MB) on a new clone:
```bash
rsync -a /space3/users/adin/.conan2/ ~/sw/nextutils_wt/<branch>/.conan2/
```

## cdnext / cdutils alias behavior

Only created when `NEXTENV_TYPE` is set (active env exists). Without a nextenv,
the default `NEXT_HOME` from `user_env_vars` may not exist on that machine and
would produce spurious warnings. `_nextenv_patch_env` refreshes them on every switch.

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
| sw-kit warnings on dev-sw05 / fresh VM | Old shared state file applied on machine without sw-kit | Per-hostname state + swkit guard in `_nextenv_startup_apply` |
| `build.sh` fails: "binfmt registered" | Switched to worktree but binfmt not cleared | `_nextenv_patch_env` disables binfmt automatically on switch to worktree |
| OMPI_CC / MPI_HOME still point to sw-kit after switch | profile.d set them; not overridden | `_nextenv_patch_env` now overrides all profile.d vars |
| `[env:installed]` in PS1 | Old fallback label before version detection | `_nextenv_startup_apply` migrates to real RPM version |
