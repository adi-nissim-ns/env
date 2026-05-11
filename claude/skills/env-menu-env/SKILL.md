---
name: env-menu-env
description: Use when the user wants to clone, setup, build, or clean **nextutils** (the NextSilicon toolchain). Also covers pre-commit install, vscode settings, build dir cleanup, conan/cache cleanup, submodule init, and ninja builds. Function is `menu-env` in `~/env/.bashrc.menu.env`.
---

# `menu-env` — nextutils lifecycle

Bringup wiki: https://wiki.nextsilicon.com/wiki/software/software-bringup/utils-toolchain-install

## Three-stage standard bringup

| Stage  | Function                          | What it does                                                            |
| ------ | --------------------------------- | ----------------------------------------------------------------------- |
| 1      | `stage1_clone_nextutils`          | `git clone --recurse-submodules …/nextutils.git` into `$SW_HOME`         |
| 2      | `stage2_setup_nextutils`          | `./setup.sh --fetch-all --create-buildtools-venv` (inside `$NEXTUTILS`) |
| 3      | `stage3_build_nextutils`          | `./build.sh --install --no-tests` (after activating Python venv)        |

Call them directly when the user is unambiguous — no need to use the
menu UI. Each stage checks that the previous stage's directory exists and
prints a clear error if not.

## Build variants (also in `menu-env`)

| Variant                                  | Function                                |
| ---------------------------------------- | --------------------------------------- |
| Install **with** tests                   | `build_nextutils_with_tests`            |
| Install with tests, fresh clean rebuild  | `build_nextutils_with_tests_clean`      |
| Config-only (cmake, no compile)          | `./build.sh --config-only` in `$NEXTUTILS` |
| Build via ninja in the existing build dir | `cd $NEXTUTILS/build && ninja`          |

## One-off ops the menu exposes

| Op                                            | Command                                                                                |
| --------------------------------------------- | --------------------------------------------------------------------------------------- |
| Install pre-commit hooks                      | `pip install -U pre-commit identify && pre-commit install` (inside `$NEXTUTILS`)        |
| Install VSCode settings                       | `./setup.sh --install-vscode-settings`                                                  |
| Clean build dir                               | `cd $NEXTUTILS && rm -rf build`                                                         |
| Clean Conan + general cache                   | `rm -rf ~/.conan2/* ~/.cache/*`                                                         |
| Re-init submodules                            | `git submodule update --init --recursive` (inside `$NEXTUTILS`)                         |
| Reset configs to defaults                     | `./setup.sh --default --force`                                                          |

## When to use which build option

- **`stage3_build_nextutils`** — fastest "just install it" path; skips tests.
- **`build_nextutils_with_tests`** — when about to develop; need tests.
- **`build_nextutils_with_tests_clean`** — only when caches are suspected
  to be stale or after a major branch switch. It's slow.

## Conventions

- `activate_python_env` is called before any build that runs Python (sets
  up the buildtools venv).
- `run_command` (from `.bashrc.basic_funcs`) is used to echo and check
  the result of every step — preserve that idiom if writing new helpers.
