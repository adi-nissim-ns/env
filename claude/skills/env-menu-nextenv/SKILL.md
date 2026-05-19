---
name: env-menu-nextenv
description: >
  Deep knowledge of .bashrc.menu.nextenv — the NextSilicon SDK environment
  switcher. Covers architecture, per-worktree cache isolation design, state
  management, startup apply, known pitfalls, and how to debug or extend the
  menu. Trigger when the user asks about menu-nextenv, nextenv, switching
  NEXT_HOME/NEXTUTILS, worktree environments, or cache isolation.
---

# menu-nextenv — architecture and design notes

## What it does

`menu-nextenv` lets the user maintain multiple independent NextSilicon SDK
environments and switch between them in the live shell:

- **Main clone** — a single `sw/nextutils` repo per space (space2/3/4 or `$HOME`)
- **Standalone clone ("worktree")** — independent full clone under `sw/nextutils_wt/<branch>/`
- **sw-kit** — system-installed RPM under `/opt/nextsilicon`

Switching an environment exports new `NEXT_HOME` / `NEXTUTILS` values, patches
`PATH`, updates all derived vars (`NINJA`, `OBJDUMP`, etc.), and redirects the
four cache env vars to the new worktree's own directories.

## Key files

| File | Purpose |
|---|---|
| `.bashrc.menu.nextenv` | Entire menu implementation (sourced by `.bashrc.user`) |
| `.nextenv_state` | Persists active environment across shell restarts |
| `sw/nextutils_wt/<branch>/` | Root of each standalone clone |
| `sw/nextutils_wt/<branch>/next_home/` | NEXT_HOME for that clone |

## Per-worktree cache isolation (critical design)

Each standalone clone owns **four real directories** (not symlinks to space):

```
sw/nextutils_wt/<branch>/
  .cache/       ← XDG_CACHE_HOME  (toolchain downloads, etc.)
  .ccache/      ← CCACHE_DIR      (compiler cache)
  .conan2/      ← CONAN_HOME      (conan package cache)
  .uv_cache/    ← UV_CACHE_DIR    (uv/pip cache)
  next_home/    ← NEXT_HOME
```

These are created by `_nextenv_add_worktree` via `mkdir -p`.

**Why**: conan/ccache are tied to a specific compiler/toolchain. Mixing
worktrees sharing the same space3 cache causes silent build corruption and
makes it impossible to know which worktree's build artifacts are in use.

## `~` as an active-env pointer

`~/.cache`, `~/.ccache`, `~/.conan2` are **symlinks in `$HOME`** that always
point to the **active worktree's own directories**. They are NOT the real dirs.

`_nextenv_sync_home_links <nu>` updates them:
```bash
for cache_dir in .cache .ccache .conan2; do
    home_link="${HOME}/${cache_dir}"
    [[ -L "$home_link" ]] || continue   # only manage existing symlinks
    target="${nu}/${cache_dir}"
    [[ "$target" == "$home_link" ]] && continue   # never self-point (circular symlink guard)
    [[ -d "$target" ]] || continue
    current=$(readlink "$home_link")
    [[ "$target" != "$current" ]] && ln -sfn "$target" "$home_link"
done
```

**Circular symlink pitfall**: if `nu` resolves to `$HOME`, then
`target = /home/adin/.cache` == `home_link` → `ln -sfn` creates a self-pointer.
The guard `[[ "$target" == "$home_link" ]] && continue` prevents this.

If `~/.cache` etc. become circular, restore manually:
```bash
ln -sfn /space3/users/adin/.{cache,ccache,conan2} ~/
```

## Four cache env vars — all must be per-worktree

`XDG_CACHE_HOME` is set independently in `.bashrc.user_env_vars:62` to
`/spaceN/users/$USER/.cache`. Without override, build scripts use that shared
path even when a worktree is active. `_nextenv_patch_env` overrides all four:

```bash
if [[ "$NEXTUTILS" == *"/nextutils_wt/"* ]]; then
    export CONAN_HOME="${NEXTUTILS}/.conan2"
    export UV_CACHE_DIR="${NEXTUTILS}/.uv_cache"
    export XDG_CACHE_HOME="${NEXTUTILS}/.cache"
    export CCACHE_DIR="${NEXTUTILS}/.ccache"
else
    # Restore defaults captured at source time
    ...
fi
```

Defaults are captured at file-source time:
```bash
_NEXTENV_DEFAULT_CONAN_HOME="${CONAN_HOME:-}"
_NEXTENV_DEFAULT_XDG_CACHE_HOME="${XDG_CACHE_HOME:-}"
_NEXTENV_DEFAULT_CCACHE_DIR="${CCACHE_DIR:-}"
_NEXTENV_DEFAULT_UV_CACHE_DIR="${UV_CACHE_DIR:-}"
```

## State file format

`.nextenv_state` is a flat key=value file:
```
# nextenv active environment — managed by menu-nextenv — do not edit manually
NEXTENV_TYPE=worktree
NEXTENV_LABEL=master
NEXTENV_NEXT_HOME=/home/adin/sw/nextutils_wt/master/next_home
NEXTENV_NEXTUTILS=/home/adin/sw/nextutils_wt/master
```

Empty file (or missing) = no active env (default). Written by `_nextenv_switch`,
cleared by `_nextenv_remove_worktree` when the active clone is deleted.

## Startup apply — `_nextenv_startup_apply`

Called from `.bashrc.user` after all menus are sourced. Critical: it **unsets
`NEXTENV_*` inherited vars first**, then reads the state file. Without this,
exported vars from a parent shell survive into child shells even if the state
file is empty or points to a deleted path.

```bash
function _nextenv_startup_apply() {
    unset NEXTENV_TYPE NEXTENV_LABEL NEXTENV_NEXT_HOME NEXTENV_NEXTUTILS
    [[ ! -f "$_NEXTENV_STATE_FILE" ]] && return 0
    # ... parse state file ...
    [[ -z "$new_nh" && -z "$new_nu" ]] && return 0
    _nextenv_patch_env "$new_nh" "$new_nu"
}
```

## Known pitfalls and fixes

### Terminal doesn't load (hangs at startup)
1. **Inherited stale NEXTENV_* vars** pointing at deleted paths — fixed by
   `unset NEXTENV_*` at top of `_nextenv_startup_apply`.
2. **CARGO_HOME check** in `.bashrc.user` used bare `${CARGO_HOME}` which is
   never set at startup → `[ -d "" ]` = false → blocked on `read -p`.
   Fixed: `${CARGO_HOME:-${HOME}/.cargo}`.
3. **Python venv check** used wrong variable `$setup_rust_env` instead of
   `$setup_python_env` and had `return 1` on skip which aborted all of
   `.bashrc.user`. Both fixed.

### `getcwd` failure after `rm -rf` of active clone
If the shell's CWD is inside the deleted directory, all subsequent commands
fail with `cannot access parent directories`. Two places guard against this:
- `_nextenv_remove_worktree`: `case "$PWD" in "${wt_dir}"/*|"${wt_dir}") cd "$HOME" ;; esac` before `rm -rf`
- `_nextenv_add_worktree`: `cd "$HOME" 2>/dev/null || true` before `git clone`

### Source builds empty / not found
`_nextenv_find_worktrees` checks `[[ -d "${wt_dir}/.git" ]]`. If the directory
exists but `.git` is missing (stale NFS, incomplete clone), it is silently
skipped. Remove the stale directory and re-clone.

### First build re-downloads toolchains (~600 MB)
Per-worktree isolation means each new clone starts with an empty `.cache/`.
Seed it from an existing clone to save time:
```bash
cp -r /space3/users/adin/.cache/nextutils_fetch ~/sw/nextutils_wt/master/.cache/
```

### Stale NFS handle
`rm -rf` may fail with "Stale file handle" on NFS mounts. Open a fresh shell
and retry; the NFS mount usually recovers.

## Adding a new standalone clone

`_nextenv_add_worktree` flow:
1. Pick space (space2/3/4 or $HOME)
2. Enter branch name → sanitize to filesystem-safe `dir_name`
3. Check remote for branch existence via `git ls-remote`
4. Confirm + clone (`git clone -b <branch>` or clone + `checkout -b`)
5. Add build artifact dirs to `.git/info/exclude` (not tracked `.gitignore`)
6. `mkdir -p` four real cache dirs inside the clone
7. `_nextenv_sync_home_links` → update `~/.cache` etc. to point here
8. Optional build: `cd $wt_dir && ./setup.sh --fetch-all --create-buildtools-venv && ./build.sh --install --no-tests`
9. `_nextenv_switch "worktree" ...` → write state, patch env

## Removing a standalone clone

`_nextenv_remove_worktree` allows removing the **active** clone (with
confirmation). Steps:
1. Detect if active (`NEXTENV_NEXTUTILS == wt_dir`)
2. `cd $HOME` if CWD is inside clone
3. `rm -rf $wt_dir`
4. If was active: clear state file, `unset NEXTENV_*`

## Extending the menu

To support a new environment type:
1. Add a `_nextenv_find_<type>` function emitting `base|label|path|next_home`
2. Add entries to `menu-nextenv()` under the appropriate section header
3. Handle the type in `_nextenv_patch_env` if it needs custom cache paths
4. The state file format is open — add new `NEXTENV_<KEY>=` lines as needed,
   just `unset` them at the top of `_nextenv_startup_apply`
