# Claude in `~/env`

Everything in this directory is about using **Claude Code** (Anthropic's CLI
assistant) together with the `~/env` repo: how to install it, how to wire up
useful integrations (Slack, Gmail, Jira…), and a set of **shareable skills**
that teach Claude how to drive the menus and helpers defined here.

## Layout

```
claude/
├── README.md            ← you are here
├── USAGE.md             ← how to use Claude Code day-to-day
├── connections/         ← optional integrations (MCP connectors)
│   ├── README.md
│   ├── slack.md
│   ├── gmail.md
│   └── atlassian.md
├── connect.sh           ← activate connectors (opens browser + verifies)
└── skills/              ← drop-in Claude skills for this env
    ├── README.md
    ├── install-skills.sh
    ├── env-install/        SKILL.md
    ├── env-menu-main/      SKILL.md
    ├── env-menu-claude/    SKILL.md
    ├── env-menu-env/       SKILL.md
    ├── env-menu-run/       SKILL.md
    ├── env-menu-slurm/     SKILL.md
    ├── env-menu-kokkos/    SKILL.md
    └── env-bash-helpers/   SKILL.md
```

## Quick start

```bash
# 1. Install Claude Code (per-user, no sudo)
~/env/claude-install.sh

# 2. (Optional) Install env-aware skills into your user skill dir
~/env/claude/skills/install-skills.sh

# 3. Launch Claude in any project
cd /path/to/project && claude
```

Don't want to remember the script paths? Open a fresh shell and run:

```bash
menu-claude
```

That opens an interactive menu with options for installing, starting a
session, activating connectors, and viewing the docs — designed for
someone who has never used Claude Code before.

After step 2, the next time Claude Code starts it will discover skills like
`env-menu-slurm` and `env-bash-helpers` and use them whenever your prompt
matches their trigger description (e.g. "allocate me a cloud node for 9
hours", "write a script that uses our echo helpers").

## What a skill is

A Claude Code *skill* is a folder containing a `SKILL.md` file with YAML
frontmatter (`name`, `description`) and free-form instructions. When the user
asks something that matches the description, Claude reads the skill body and
follows it. Skills live in `~/.claude/skills/<name>/SKILL.md` (user-wide) or
`.claude/skills/<name>/SKILL.md` (project-local). The installer in this
directory symlinks the skills here into your user skill dir, so updating the
repo updates the skills.

See also:
- [USAGE.md](USAGE.md) — Claude Code basics, slash commands, model selection
- [connections/README.md](connections/README.md) — MCP connectors for
  Slack/Gmail/Jira/Drive/etc.
- [skills/README.md](skills/README.md) — how to install and write skills
