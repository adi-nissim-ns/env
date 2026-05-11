# Atlassian connector (Jira + Confluence)

Lets Claude read/write Jira issues and Confluence pages.

## Setup

1. https://claude.ai → **Settings → Connectors**
2. **Atlassian → Connect** → log into your Atlassian account → pick the
   site (e.g. `nextsilicon.atlassian.net`)
3. Approve the requested scopes

Verify in Claude Code with `/mcp`.

## Typical uses

> "List my open Jira tickets in the SW project sorted by priority."

> "Read the Confluence page 'SW Bringup Onboarding' and summarize the
> SLURM section."

> "Create a Jira ticket in INGEST titled 'nextsystemd hangs on warm reset'
> with these reproduction steps: …"

> "Comment on JIRA-1234 with a status update saying the PR is merged."

## Tips

- Identify issues by full key (`PROJ-123`) — Claude is conservative about
  inferring projects.
- For Confluence, paste the page URL or give a precise title + space.
- Bulk operations: Claude will confirm before creating/modifying more than
  one issue or page in a single turn.

## Revoking

Settings → Connectors → Atlassian → **Disconnect**.
