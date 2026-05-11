---
name: env-menu-run
description: Use when the user wants to run nextsystemd / nextloader, manage NextSilicon drivers (load/unload/reload/lsmod), invoke the CPU→Device optimization pipeline, or interact with the background nextsystemd helpers. Function is `menu-run` in `~/env/.bashrc.menu.run`.
---

# `menu-run` — drivers, daemons, and the optimize pipeline

Most complex submenu in the env. Key concepts before diving in.

## State files (under `~/env/`)

| File                          | Purpose                                                                |
| ----------------------------- | ----------------------------------------------------------------------- |
| `.history_nextsystemd`        | Recent `--cfg-file` choices for `nextsystemd` (TAB-separated `dir<TAB>cfg`) |
| `.history_nextloader`         | Recent full `nextloader` commands                                      |
| `.nextsystemd.pid`            | PID of the background nextsystemd (used by pipeline option 12)          |
| `.nextsystemd.log`            | Captured stdout/stderr of that background process                       |

`_HISTORY_MAX = 10` — older entries fall off automatically.

## Menu options

| #   | Action                                                                                   |
| --- | ---------------------------------------------------------------------------------------- |
| 2   | `reload-drv` — reload kernel drivers                                                     |
| 3   | `unload-drv`                                                                             |
| 4   | `load-drv`                                                                               |
| 5   | `lsmod` — show currently loaded modules                                                  |
| 6   | `sudo rm -rf /dev/shm/sys_sync_dev1` — clear shm before fresh nextsystemd                |
| 7   | `run_nextsystemd` — pick `--cfg-file` from history, then run in **foreground**           |
| 8   | `cleanup` — pkill nextdaemon/nextloader/nextruntimed/nextsystemd/python + coredumps      |
| 9   | warm reset (`./build/bin/sys_mng_tools --device-id 1 warm-reset`) — keep VM allocated    |
| 10  | `run_nextloader <cmd>` — CPU run, wait for optimization, then Device run                |
| 11  | `nextcli application clear` — drop current app's optimization state                      |
| 12  | `run_pipeline` — start nextsystemd in **background** + nextloader + print profiler link |
| 13  | `_nextsystemd_bg_stop` — kill the background nextsystemd                                 |
| 14  | `_nextsystemd_bg_log` — dump the captured log                                            |

## How the optimize pipeline works (option 10 / 12)

`run_nextloader` is the heart of the pipeline:

1. Validates command starts with `nextloader` (after any `FOO=bar` prefixes).
2. Appends the command to `.history_nextloader`.
3. Queries `nextcli --json application status` to see if this exe is
   already `IMPROVED` / `OPTIMIZED` / `COMPLETED`. If yes → skip CPU run.
4. Otherwise: runs the cmd on CPU, then **polls every 5s** until
   `nextcli application status` reports
   `OPTIMIZED|IMPROVED|Optimization state: READY|COMPLETED`.
5. Optional post-opt hook (`$_NEXTLOADER_POST_OPT_HOOK`) — used by option
   12 to print the profiler link from the bg nextsystemd log.
6. Re-runs the same cmd; this time it's on Device.

## Calling functions directly

| User intent                           | Function                                          |
| ------------------------------------- | ------------------------------------------------- |
| Run nextsystemd interactively         | `run_nextsystemd`                                 |
| Run nextloader cmd through pipeline   | `run_nextloader "<full cmd>"`                     |
| Full bg pipeline + profiler link      | `run_pipeline`                                    |
| Stop background nextsystemd           | `_nextsystemd_bg_stop`                            |
| Tail captured nextsystemd log         | `_nextsystemd_bg_log`                             |
| Wipe everything                       | `cleanup` then `sudo rm -rf /dev/shm/sys_sync_dev1` |

## When debugging

- If a pipeline run "hangs", first check `_nextsystemd_bg_log` —
  nextsystemd may have failed silently. The PID file gets cleaned up on a
  detected crash within 2s of start.
- Existing `nextsystemd` processes block a fresh start; the helper
  prompts to kill them. In a non-interactive Claude run, prefer
  `_nextsystemd_bg_stop` first, then start.
- The history-menu `dN` syntax (e.g. `d3`) deletes a history entry — use
  it when an old cfg path no longer exists.
