# Gmail connector

Lets Claude search threads, manage labels, and draft (never auto-send)
emails from your account.

## Setup

1. https://claude.ai → **Settings → Connectors**
2. **Gmail → Connect** → Google OAuth
3. Pick the account; review scopes (read, modify labels, create drafts)

Verify with `/mcp` inside Claude Code — `Gmail` should appear as ready.

## Capabilities

- `search_threads` — search like in the Gmail web UI (`from:`, `has:`,
  `after:`, `is:unread`, …)
- `get_thread` — full message bodies
- `create_draft` — composes a draft; never sends. You confirm in Gmail.
- `list_labels`, `create_label`, `label_message`, `label_thread`,
  `unlabel_message`, `unlabel_thread`
- `list_drafts`

## Example prompts

> "Find the latest thread with the build-infra team about the Jenkins
> outage and draft a one-line ack."

> "Tag every unread thread from `noreply@github.com` with `gh-noise`."

> "Show me unread threads from this week where I'm the only @mention."

## Safety

- Claude can only *draft*. Sending still requires you to click Send in
  Gmail.
- Label changes are not asked-for-every-message by default — review the
  prompt scope first if it's a bulk operation.

## Revoking

Settings → Connectors → Gmail → **Disconnect**.
