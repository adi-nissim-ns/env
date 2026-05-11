---
name: env-menu-slurm
description: Use when the user wants to allocate or reserve NextSilicon hardware via SLURM (salloc/scontrol), see partition info (sinfo), see what's queued (squeue), ssh to slurm, or fix the VM lustre mount issue. Function is `menu-slurm` in `~/env/.bashrc.menu.slurm`.
---

# `menu-slurm` — SLURM access to NextSilicon HW

Wiki: https://wiki.nextsilicon.com/wiki/software/software-bringup/getting-access-to-a-card-using-slurm/

## Menu options

| #  | Action                                                                                 |
| -- | --------------------------------------------------------------------------------------- |
| 2  | ssh to slurm (`$SSH_SLURM`)                                                            |
| 3  | `sinfo` — partition status                                                              |
| 4  | `squeue` — current allocations                                                          |
| 5  | Allocate in `cloud` partition, exclusive, **N hours** (default 9)                       |
| 6  | Allocate in `BM-Maverick2-Single` (bare metal), exclusive, **N hours** (default 9)      |
| 7  | Reserve in `cloud` partition for N hours                                                |
| 8  | Reserve in `BM-Maverick2-Single` for N hours                                            |
| 9  | VM mount fix (lustre): rmmod, modprobe lnet, lnetctl configure, mount -a               |

## Direct calls

Two underlying helpers:

```bash
allocate_hw <partition> <hours>
# → salloc --partition=<partition> --nodes=1 --time=<hours>:00:00 --exclusive --no-shell

reserve_hw <partition> <hours>
# → scontrol --uid=$USER create reservation StartTime=now Duration=<hours>:00:00 \
#            Partition=<partition> users=$USER
```

Common examples:

```bash
allocate_hw cloud 9                  # 9h on cloud (the default)
allocate_hw BM-Maverick2-Single 4    # 4h on a bare-metal node
reserve_hw cloud 24                  # 24h reservation
```

## VM mount fix (option 9)

If `$SHARED_SPACE_NAME` isn't mounted inside a fresh VM, run option 9 —
it sequences:

```
sudo lustre_rmmod
sudo modprobe lnet
sudo lnetctl lnet configure --all
sudo mount -a
```

Run **inside** the VM (not on the slurm head node).

## Practical guidance

- `salloc` here uses `--no-shell` — you get an allocation but no
  interactive session. ssh into the node separately (option 2) or use
  `srun` against the JobID.
- `--exclusive` is intentional — these are not shared resources.
- Reservations (`scontrol create reservation`) usually require admin
  rights on most clusters; check `sinfo -R` if it fails.
- If a user asks "give me a card for the afternoon", default to **cloud**
  partition for 4h unless they specify bare-metal.
