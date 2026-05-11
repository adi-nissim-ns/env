# Using Claude Code

Claude Code is Anthropic's CLI coding assistant. After installing with
`~/env/claude-install.sh`, run `claude` in any project directory.

## Day-to-day

| What you want to do                        | How                                           |
| ------------------------------------------ | --------------------------------------------- |
| Start a session                            | `claude` (in the project dir)                 |
| Resume the last session                    | `claude --resume`                             |
| One-shot prompt, no interactive UI         | `claude -p "explain build.sh"`                |
| Use a specific model                       | `/model` (inside the session)                 |
| Faster, cheaper responses                  | `/fast` (toggles Opus-4.6 fast mode)          |
| See available commands                     | `/help`                                       |
| Pick a permission mode                     | `/permissions` (read-only, ask, accept-edits) |
| Compact the conversation                   | `/compact`                                    |
| Pause to plan an approach before any edits | `/plan` then approve                          |
| Run a stored skill                         | `/<skill-name>` or just describe the task     |
| End and clear state                        | `/clear`                                      |

## Permission modes

- **read-only** — Claude can read and search but never edits or runs commands
- **ask** — every write/exec asks once
- **accept-edits** — edits auto-approved, shell commands still asked
- **bypass** — full autonomy (use only in sandboxes / throwaway dirs)

Set the default in `~/.claude/settings.json`:
```json
{ "permissionMode": "ask" }
```

## Project context (`CLAUDE.md`)

Drop a `CLAUDE.md` at the root of a repo to give Claude project-specific
context that loads automatically. Use it for:
- Build/test commands
- Architecture overview
- Coding style rules
- "Always do X / never do Y" guardrails

Example: see `/space3/users/adin/sw/llama/next-dnn/CLAUDE.md`.

## Skills

Skills extend Claude with reusable, named capabilities. The ones shipped
with this repo (in `skills/`) document the `~/env` menus and helpers — see
[skills/README.md](skills/README.md) for install instructions.

## Connectors / MCP servers

MCP (Model Context Protocol) servers let Claude talk to external systems —
Slack, Gmail, Jira, Drive, etc. See [connections/README.md](connections/README.md).

## Useful built-in slash commands

- `/init` — generate a starter `CLAUDE.md` for the current repo
- `/review` — review a pull request
- `/security-review` — security review of pending changes
- `/cost` — show token + cost usage for the session
- `/config` — open Claude Code settings

## Docs

- Claude Code: https://docs.claude.com/en/docs/claude-code/overview
- Quickstart:  https://docs.claude.com/en/docs/claude-code/quickstart
- Skills:      https://docs.claude.com/en/docs/claude-code/skills
- MCP:         https://docs.claude.com/en/docs/claude-code/mcp
