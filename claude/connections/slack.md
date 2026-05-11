# Slack connector

Lets Claude search Slack history, read threads, draft replies, and manage
labels/reactions on your behalf.

## Setup

1. Open https://claude.ai → **Settings → Connectors**
2. Find **Slack** → click **Connect**
3. Authorize against your workspace (you'll be redirected to Slack OAuth)
4. Choose which channels/workspaces Claude is allowed to access

That's it — no local install. The connector is now available in any
Claude Code session under the name `Slack`.

## Verify it works

```text
# inside a Claude session
/mcp                  # Slack should appear with status "ready"
```

Then just ask in plain English:
> "Search #sw-infra for messages about the nextsystemd crash this week"
> "Summarize the thread linked here: <slack URL>"
> "Draft a reply saying I'll look at it tomorrow"

## What it can do

- `search_threads` — keyword/date-range search across channels you can access
- `get_thread` — full thread by URL or `ts`
- `create_label`, `label_message`, `label_thread`, `unlabel_*` — Slack labels
- `list_labels` — list labels for a channel/user

It does **not** auto-post on your behalf without confirmation — Claude will
ask before sending.

## Tips

- For long threads, ask Claude to summarize "by speaker" or "by decision
  made" — cleaner than raw transcript.
- Reference channels by `#name` or full Slack URL; both work.
- If a search returns nothing, double-check the connector's allowed-channel
  list in Settings.

## Revoking

Settings → Connectors → Slack → **Disconnect**. The token is invalidated
immediately on the Slack side.
