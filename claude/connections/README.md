# Connecting Claude to external services (MCP)

Claude Code can talk to external systems through **MCP servers** (Model
Context Protocol). Once a server is added and authenticated, Claude can
list channels, search threads, create Jira tickets, read Drive docs, etc.

## Two flavours

| Flavour                 | Where it lives                            | Best for                            |
| ----------------------- | ----------------------------------------- | ----------------------------------- |
| **Claude.ai connector** | claude.ai web account (per user)          | SaaS apps (Slack, Gmail, Jira, …)   |
| **Local MCP server**    | a process you run on your machine         | repo-local tools, private services  |

The official connectors (Slack, Gmail, Atlassian, Notion, Drive, Calendar)
appear automatically in Claude Code once you've authenticated them in
**claude.ai → Settings → Connectors**. There's nothing to install locally.

## Listing what's available

Inside a Claude Code session:
```text
/mcp                       # list configured servers + their status
/mcp <server> tools        # list tools the server exposes
```

From the shell:
```bash
claude mcp list
claude mcp add <name> <command-or-url>   # add a local server
claude mcp remove <name>
```

## Common connectors

- [slack.md](slack.md)       — search, post, threads, labels
- [gmail.md](gmail.md)       — drafts, labels, thread search
- [atlassian.md](atlassian.md) — Jira issues, Confluence pages

Other available connectors (same setup pattern): Google Drive, Google
Calendar, Notion, Canva, NetSuite. Authenticate via claude.ai → Connectors,
then call `/mcp` inside Claude to confirm they're visible.

## Per-project servers

If a project needs its own MCP servers (e.g. a private database tool),
commit a `.mcp.json` at the repo root:

```json
{
  "mcpServers": {
    "my-tool": {
      "command": "/abs/path/to/my-tool-mcp",
      "args": ["--config", ".my-tool.yaml"]
    }
  }
}
```

Everyone who clones the repo gets the same servers. Claude Code prompts
once per project before trusting them.

## Docs

- MCP overview: https://docs.claude.com/en/docs/claude-code/mcp
- Connectors:   https://docs.claude.com/en/docs/claude-code/connectors
