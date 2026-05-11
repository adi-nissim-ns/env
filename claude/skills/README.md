# Shared Claude skills for `~/env`

This directory holds **Claude Code skills** that teach Claude how to work
with the helpers and menus defined in `~/env`. Once installed, you can
just say things like:

> "allocate a cloud node for 9 hours"
> "rebuild nextutils clean"
> "start the optimize pipeline with my last cfg"
> "write a script that uses our echo helpers and logs to /tmp/foo.log"

…and Claude will use the right bash function, follow the conventions, and
keep history files / PID files where this env expects them.

## Install (per-user)

```bash
~/env/claude/skills/install-skills.sh           # symlink into ~/.claude/skills/
~/env/claude/skills/install-skills.sh --copy    # copy instead of symlink
~/env/claude/skills/install-skills.sh --uninstall
```

Symlink is the default — pull the `~/env` repo and you get the latest skill
versions for free. Restart any running Claude Code session so it re-scans
the skills directory.

## What's here

| Skill                 | When Claude uses it                                                       |
| --------------------- | -------------------------------------------------------------------------- |
| `env-install`         | "Set up `~/env` on a new machine" / first-time bootstrap                  |
| `env-menu-main`       | Anything about the top-level `menu` function or navigation                 |
| `env-menu-claude`     | Onboarding to Claude Code itself: install, run, activate connectors        |
| `env-menu-env`        | nextutils clone/setup/build, pre-commit install, build cleanup            |
| `env-menu-run`        | nextsystemd, nextloader, drivers, the CPU→Device optimization pipeline    |
| `env-menu-slurm`      | SLURM allocations, reservations, partition info                           |
| `env-menu-kokkos`     | Cloning, building, cleaning kokkos                                        |
| `env-bash-helpers`    | Writing scripts that use `echo_info`/`run_command`/`create_softlink`/etc. |

## How a skill gets picked up

Claude Code scans `~/.claude/skills/*/SKILL.md` on startup. Each `SKILL.md`
begins with frontmatter:

```yaml
---
name: env-menu-slurm
description: When the user wants SLURM allocations / reservations on NextSilicon HW
---
```

Claude matches the user's prompt against the `description`. If it's a
match, the skill body is loaded into context and Claude follows it. There
is no slash command needed — though you *can* invoke a skill explicitly
with `/env-menu-slurm`.

## Writing your own

Add a new directory under `skills/`, put a `SKILL.md` inside with the
frontmatter shown above, and re-run `install-skills.sh`. Keep the body
short and action-oriented — Claude reads it every time the skill is
triggered.

Docs: https://docs.claude.com/en/docs/claude-code/skills
