---
name: env-menu-main
description: Use when the user references the top-level bash `menu` function, asks how to navigate the env menus, or wants to know what `cdsw`/`cdnext`/`cdutils` and the standard env vars (NEXT_HOME, SW_HOME, NEXTUTILS, …) point to.
---

# Main menu (`menu`)

Defined in `~/env/.bashrc.menu.main`. Entry point that dispatches to all
the submenus.

## Layout

```
0. Exit
1. fix-ps1                    → restyle the prompt (git branch, venv, colors)
2. enter menu-run             → drivers / nextsystemd / nextloader / pipeline
3. enter menu-slurm           → SLURM allocations & reservations
4. enter menu-env             → clone/setup/build nextutils
5. enter menu-kokkos          → clone/build/clean kokkos
6. Known aliases              → list cdsw/cdnext/cdutils/.. shortcuts
7. Known parameters           → list NEXT_HOME / SW_HOME / NEXTUTILS / etc.
8. Activate Python virtual environment
```

## How to drive it from a non-interactive prompt

The user may ask "do step 4 of the env menu" — the submenu functions are
all callable directly:

| Action                          | Direct call                       |
| ------------------------------- | --------------------------------- |
| Open run submenu                | `menu-run`                        |
| Open slurm submenu              | `menu-slurm`                      |
| Open env (nextutils) submenu    | `menu-env`                        |
| Open kokkos submenu             | `menu-kokkos`                     |
| Restyle prompt                  | `fix-ps1`                         |
| Activate Python venv            | `activate_python_env`             |

Prefer calling the underlying stage function instead of going through the
interactive menu when the user is unambiguous. For example
"clone nextutils" → `stage1_clone_nextutils` (no need to navigate).

## Known aliases (option 6)

| Alias    | Target                          |
| -------- | ------------------------------- |
| `cdsw`   | `$SW_HOME`                      |
| `cdnext` | `$NEXT_HOME`                    |
| `cdutils`| `$NEXTUTILS`                    |
| `..`     | parent directory                |
| `...`    | grandparent                     |
| `....`   | great-grandparent               |
| `lookfor`| `grep -rnw . -e`                |

## Known env vars (option 7)

`SPACE_PATH`, `NEXT_HOME`, `SW_HOME`, `NEXTUTILS`, `CCACHE_DIR`,
`CONAN_USER_HOME`, `XDG_CACHE_HOME`, `_ENV_DIR`, `_ENV`, `_SPACE_DIR`,
`_OS`, `_BASH_VENV`, `_FISH_VENV`, `_PRIVATE_VENV`, `_NEXTSW_VENV`.

When the user asks where one of these points, check the live value with
`echo "$VAR_NAME"` rather than guessing.
