---
name: env-menu-claude
description: Use when the user is new to Claude Code and wants to install it, install the env-aware skills, start a session, activate connectors (Slack/Gmail/Atlassian/Drive/…) via the browser, or look up Claude Code docs. Function is `menu-claude` in `~/env/.bashrc.menu.claude`.
---

# `menu-claude` — onboard a new Claude Code user

The friendly entry point for someone who has never used Claude Code
before. Wraps the install scripts, the connector helper, and the docs.

## Menu options

| #   | Action                                                                                  |
| --- | ---------------------------------------------------------------------------------------- |
| 2   | Run `~/env/claude-install.sh` (per-user install, no sudo)                                |
| 3   | Run `~/env/claude/skills/install-skills.sh` (symlinks env skills into `~/.claude/skills`)|
| 4   | `claude --version` + show install path                                                   |
| 5   | Launch `claude` in the current dir (wrapped in tmux session `claude-$(basename PWD)`)    |
| 6   | Launch `claude --resume` (also tmux-wrapped)                                             |
| 7   | List installed skills (parses `description:` from each `SKILL.md`)                       |
| 8   | Run `~/env/claude/connect.sh` — opens connectors page in browser, then `claude mcp list` |
| 9   | `claude mcp list`                                                                        |
| 10  | `cat ~/env/claude/connections/README.md`                                                 |
| 11  | `cat ~/env/claude/USAGE.md`                                                              |
| 12  | Print docs URLs (overview, quickstart, skills, MCP, connectors)                          |

## Direct calls

| User intent                                          | Function / command                                   |
| ---------------------------------------------------- | ----------------------------------------------------- |
| Open the menu                                        | `menu-claude`                                         |
| Install Claude CLI non-interactively                 | `~/env/claude-install.sh`                             |
| Install env skills                                   | `~/env/claude/skills/install-skills.sh`               |
| Activate a connector (browser-driven)                | `~/env/claude/connect.sh`                             |
| Just verify connectors visible to local CLI          | `~/env/claude/connect.sh --verify-only`               |
| List installed skills                                | `_claude_show_skills` (defined alongside the menu)    |

## Activating connectors

Slack/Gmail/Atlassian/Drive/Notion are **claude.ai-managed OAuth flows**,
not local installs. There is no `claude connect slack` command. The flow:

1. `~/env/claude/connect.sh` opens `https://claude.ai/settings/connectors`
   in the user's default browser.
2. User picks a connector, clicks **Connect**, completes OAuth, picks
   scopes.
3. Script runs `claude mcp list` to confirm the local CLI sees it.

Inside any `claude` session, `/mcp` shows live status of all servers.

## tmux wrapping for sessions

Options 5 and 6 call the helper `_claude_run`, which:

1. If `$TMUX` is set (already inside tmux) → runs `claude` directly to
   avoid nesting.
2. If `$_CLAUDE_NO_TMUX=1` → bypasses tmux entirely.
3. Else if `tmux` is on PATH → wraps the command in:
   `tmux new-session -A -s "claude-$(basename $PWD)" claude <args>`
   (`-A` attaches if a session of that name already exists).
4. Else → warns and runs `claude` bare.

This means an SSH drop won't kill an in-progress Claude session; reattach
with `ta claude-<dir>` (alias from `.bashrc.tmux`). Pair with **mosh** to
get a connection that itself survives network changes — the two are
complementary, not alternatives:

- **mosh** keeps the *connection* alive across roaming / disconnects
- **tmux** keeps the *session* alive across full logout/reconnect cycles

## Common confusions to clear up for a beginner

- **"How do I install Slack?"** — You don't install anything. Connect on
  claude.ai → Settings → Connectors. Then `claude` already knows about it.
- **"Why doesn't `claude` see my new connector?"** — Restart the session
  (or run `/mcp` to refresh). The session reads connectors at start-up.
- **"What's the difference between a skill and a connector?"** — A skill
  is local instructions in `~/.claude/skills/`; a connector is an
  external service Claude talks to over MCP.
- **"Do I need sudo?"** — No. Everything in this menu is per-user.
