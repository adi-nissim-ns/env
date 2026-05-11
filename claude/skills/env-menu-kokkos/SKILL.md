---
name: env-menu-kokkos
description: Use when the user wants to clone, build, or clean **kokkos** (https://github.com/nextsilicon/kokkos). Function is `menu-kokkos` in `~/env/.bashrc.menu.kokkos`.
---

# `menu-kokkos` — kokkos clone / build / clean

Repo: https://github.com/nextsilicon/kokkos

## Menu options

| # | Action                                                                  |
| - | ----------------------------------------------------------------------- |
| 2 | `clone_kokkos`  → `git clone --recurse-submodules` into `$SW_HOME`      |
| 3 | `build_kokkos`  → `./build.sh --uvm --benchmarks --tests`               |
| 4 | `clean_kokkos`  → `./build.sh --clean` (prompts for confirmation)       |

## Direct calls

```bash
clone_kokkos    # cdsw; git clone --recurse-submodules .../kokkos.git
build_kokkos    # cdsw; cd kokkos; ./build.sh --uvm --benchmarks --tests
clean_kokkos    # confirms first; runs --clean; offers rm -rf build on failure
```

## Build flags

`build_kokkos` always passes:

- `--uvm` — unified-virtual-memory build (required for NextSilicon UVM path)
- `--benchmarks` — build the benchmark suite
- `--tests` — build the unit tests

If the user wants a different combination (e.g. release build, no
benchmarks), don't call `build_kokkos` — run `./build.sh` directly from
`$SW_HOME/kokkos` with the desired flags.

## Clean behavior

`clean_kokkos` is two-stage and interactive:

1. Confirms "Are you sure?" (y/n).
2. Runs `./build.sh --clean`.
3. If `--clean` returns non-zero, asks whether to nuke the `build/`
   directory with `rm -rf`.

In a non-interactive Claude run, prefer to skip the menu helper and run
`./build.sh --clean` (or `rm -rf $SW_HOME/kokkos/build`) yourself, so you
can answer prompts inline.
