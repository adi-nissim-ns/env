---
name: env-menu-profiler
description: Use when the user wants to profile any nextloader run — extract CBU usage, mill duplication count, cache hit/miss rate, HBM idle/stall %, MEP request counters, or detect bottlenecks. Provides `profile_analyze`, `profile_compare`, `profile_extra`, `profile_experiment` plus the interactive `menu-profiler` (function in `~/env/.bashrc.menu.profiler`). All functions auto-detect endpoints; no project paths hardcoded.
---

# `menu-profiler` — extract & interpret NextSilicon device profiling data

Generic profile-data tooling for any nextloader run. Auto-detects the
InfluxDB endpoint and the collector's SQLite path from `ps`, so it works
for any binary under any project directory.

## When to use this skill

- The user is running a kernel through `nextloader` / `run_nextloader` and
  wants to know **why it's running at speed X** rather than peak.
- The user wants to compare two variants (e.g. with/without a code change)
  and see what changed in the mill projection / runtime telemetry.
- The user is asking about *any* of: CBUs, duplication count, mill
  structure, cache hit/miss, HBM bandwidth, idle %, stall %, MEP requests,
  cacheline splits, alignment, MMU backpressure.

## Pre-conditions

- `nextsystemd` is running (start via `menu-run` → option 12 "run_pipeline" or
  `_nextsystemd_bg_start <cfg-file>`). All the functions below need it.
- At least one CPU pass + opt cycle has completed for the binary in
  question. That populates the SQLite mill metrics and the InfluxDB
  telemetry. If the application status is `IDLE` (no projection yet) or
  the SQLite tables `ProjectionMillMetrics` / `MillStatistics` are empty,
  there's nothing to analyze — run the kernel first.

## The functions, by use case

| You want to… | Use |
|---|---|
| Pull a metrics snapshot of the current run state | `profile_analyze [--label X] [--out-dir DIR]` |
| Compare two or more saved snapshots side-by-side | `profile_compare <tsv1> <tsv2> [...]` |
| Drill into one specific metric class | `profile_extra <subcommand>` |
| Run a *full experiment cycle* with cool-start protocol | `profile_experiment --label X --warmup '<cmd>' --measure '<cmd>'` |
| Pick from a menu | `menu-profiler` |

## The cool-start protocol (hard rule)

For any **fresh device cycle** (after `nextcli application clear` or any
restart): **first** invocation must run a SMALL workload, **only after the
mill reaches `IMPROVED`** should you run the production-size measurement.

- The JIT's CPU pass runs the binary on the host. If the first
  invocation uses the production-size shape with high iters, the host
  execution can take 20+ minutes (e.g. 2000 iters of a 70B-FFN GEMV on
  host CPU is multi-hour-CPU-time, even on 32 cores).
- **Use a small shape with low iters** (e.g. m=2048 n=2048 iters=50) for
  the first cycle — projection samples gather just as well from a small
  shape as a big one.
- **Only after IMPROVED** should you run the big shape with full iters.
  The loader auto-skips the CPU pass at that point, the mill is on the
  grid, the big workload runs at device speed (sub-second per 200-iter
  device call even for the largest Llama shapes).
- `profile_experiment` enforces this automatically (`--warmup` runs
  first, `--measure` runs after `IMPROVED`).

## What `profile_analyze` reports, in priority order

When the script flags a bottleneck, work through the *causal chain* not
just the symptom. Read in this order:

1. **`placedDup` from `ProjectionMillMetrics`** — if `placedDup == 1`
   you've lost half your compute parallelism, and that's the primary
   problem. Fix by shrinking the mill body (lower unroll, simpler IR)
   until `placedDup ≥ 2`.
2. **`hbm.stallPct`** — if > 5%, memory bus saturated, demand > supply.
   Means lower memory traffic (precision, fusion, layout), NOT more
   parallel loads. Rare on streaming kernels.
3. **`hbm.idlePct`** — if > 25% during active runs AND stall is near
   zero, the kernel isn't issuing enough concurrent loads. *Most common*
   bottleneck on memory-bound kernels. Counter-intuitive fix: more
   *real* memory ops (TILE_M, multi-stream); do NOT use
   `__builtin_prefetch` or `HIGH_THROUGHPUT` — both verified to make
   HBM *more* idle on at least one production kernel.
4. **`cache_miss_rate`** — if it *changed* between two variants of the
   same kernel, your access pattern changed (locality lost/gained).
   A 50% miss rate on streaming GEMV is normal; 66%+ means you're
   touching multiple data streams that fight for L1 lines.
5. **`mep1stSplitCounter` / `mepUnalignedCounter`** — should be 0 on
   well-aligned shapes. Non-zero means alignment broke; investigate
   first. The MEP `HIGH_THROUGHPUT` hint only helps when these are
   non-zero.
6. **`mmuReqBpCounter` / `mmuRespBackpressureCounter`** — should be
   ≪10K. If > 100K, TLB pressure (try huge pages, smaller working set,
   coalesce accesses).
7. **`cache_hits_prefetch` counter** — almost always 0 on streaming
   access patterns (regardless of HW or SW prefetch). The HW prefetcher
   doesn't engage for sequential streaming, and software
   `__builtin_prefetch` doesn't generate prefetcher hits either. **Don't
   try to "improve" this counter** — it's a "this HW feature is
   irrelevant for you" signal.

## Reading change between variants

When comparing two TSVs via `profile_compare`, **ignore absolute values**
of counters that depend on run length (`mep_requests`,
`cache_hits_no_prefetch`, `cache_misses`, `hbm_rd_total`) — those scale
with how long the device ran, and slower variants accumulate more
samples. The meaningful diffs are:

- `placedDup`, `usedCbu`, `nodeCount`, `memAccessCount`, `feuCount`
  — projection metrics, stable per run, comparable directly.
- `hbm_idle_avg_pct`, `hbm_idle_min_pct`, `hbm_stall_pct` —
  percentages, stable.
- `miss_rate` (misses / (hits + misses)) — percentage, stable.
- `mep_splits / mep_unaligned` — should be 0/0 in both; if not,
  alignment changed.

## HBM samples can be sparse on short device runs

If a device run is short (~3 seconds for 2000 iters of a 70B FFN GEMV),
the HBM sampler (10s+ cadence) may capture **0 samples in the active
window**. You'll see `n=0` and `idlePct=0.0%` in the report — misleading.

**Fix**: re-run the same kernel 2–3 more times to accumulate samples,
then re-run `profile_analyze --label X`. The function reads the
InfluxDB cumulative state, so each new device run adds to it.

## Counter cheat-sheet (sqlite + influx tables it reads)

| Section | Source | Tables |
|---|---|---|
| Mill structure | SQLite `collector.db` | `ProjectionMillMetrics`, `Mills`, `MillStatistics` |
| MEP totals | InfluxDB `database` | `mepRequestsCounter`, `mep1stSplitCounter`, `mepUnalignedCounter` |
| CBU L1 cache | InfluxDB | `cbuMemcipMcuHitFipAndPrefetchCounter`, `cbuMemcipMcuHitFipNoPrefetchCounter`, `cbuMemcipMcuMissCounter` |
| MMU backpressure | InfluxDB | `mmuReqBpCounter`, `mmuRespBackpressureCounter` |
| HBM | InfluxDB | `hbm` (fields `rdBandwidth`, `wrBandwidth`, `idlePct`, `stallPct`) |

To dump the live InfluxDB schema yourself:
```bash
curl -s "$(_profiler_influx_url)/api/v3/query_sql?db=database&q=SHOW%20TABLES&format=jsonl"
```

## Output paths

By default, `profile_analyze` writes `profile_<label>.tsv` into
`$PWD/profile_data/` (creating the directory if needed). Override via:

```bash
export NEXT_PROFILER_OUT_DIR=/some/other/dir
# or per-invocation
profile_analyze --label X --out-dir /tmp/foo
```

## Patterns observed on NextSilicon (May 2026, applicable to ANY kernel)

These are conclusions from prior experiments — they apply broadly, not
just to one project. Project-specific findings live in the relevant
project skill (e.g. `nextdnn-perf` in next-dnn).

- **CBU budget is per-mill-footprint, not a fixed cap.** Small mill →
  more dups fit (D=4 observed at 8 CBUs/dup); big mill → fewer
  (D=1 at 33+ CBUs/dup). The "best D" is not the maximum D — too-small
  per-dup mills are starved for inner-iter ILP.
- **`__builtin_prefetch` is harmful on grid-projected kernels.** It
  consumes a memory port slot without populating the prefetcher's
  cacheline counters. Verified -26% perf on a memory-bound GEMV across
  two VMs. Don't use it; if you want explicit prefetch, look for a
  NextSilicon-native primitive instead.
- **MEP `HIGH_THROUGHPUT` split hint is harmful on aligned access
  patterns.** Allocates 2 MEPs per load even when only 1 is needed,
  doubling MEP pressure. Only useful when `mep1stSplitCounter > 0` (your
  loads actually cross cachelines).
- **`__builtin_assume(...)` is benign**: replacing `assert(...)` with
  `__builtin_assume(...)` is functionally equivalent at runtime (both
  no-ops under NDEBUG), gives the compiler/JIT a hint, and is within
  measurement noise on perf. Safe to use as a contract declaration.
- **Device perf drifts across hours / VMs.** Same source, same
  kernel — re-running the baseline several hours later (or after driver
  reload, or on a different VM of the same nominal HW) can shift numbers
  by 5–25% per shape. When measuring a small change, always re-run the
  baseline in the *same hour, same machine* as the experiment. Saved
  baselines are unreliable for ±5% comparisons.

## Quick examples

```bash
# After a manual run via menu-run:
profile_analyze --label my_kernel_v1

# Compare two recent runs:
profile_compare profile_my_kernel_v1.tsv profile_my_kernel_v2.tsv

# Full experiment cycle (auto cool-start + analyze):
profile_experiment --label tile_m2_u3 \
    --warmup  './build/bin/next-dnn-cli gemv_add_packed m=2048 n=2048 --iters 50 --device' \
    --measure './build/bin/next-dnn-cli gemv_add_packed m=8192 n=28672 --iters 2000 --device --peak-bw 800'

# Drill in on a specific metric class:
profile_extra hbm-dist        # HBM idle% buckets
profile_extra cache-rates     # detailed cache hit/miss
profile_extra mill            # all projected mills
```
