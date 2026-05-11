#!/bin/bash
# ------------------------------------------------------------------
# connect.sh
#
# Helper to activate Claude.ai connectors (Slack, Gmail, Atlassian, …).
#
# Connectors are SaaS OAuth flows — there's no shell command to "log
# in"; you have to authorize them in your browser at claude.ai. This
# script opens the right page, prints the list of common connectors,
# and verifies your local Claude CLI sees them via `claude mcp list`.
#
# Usage:
#   ./connect.sh                       # show menu, open connectors page
#   ./connect.sh --no-browser          # don't auto-open the URL
#   ./connect.sh --verify-only         # just run `claude mcp list`
#   ./connect.sh --help
# ------------------------------------------------------------------

set -u

_SCRIPT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
_ENV_PROJECT_DIR=$(dirname "$_SCRIPT_DIR")

# shellcheck source=../.bashrc.basic_funcs
source "${_ENV_PROJECT_DIR}/.bashrc.basic_funcs"

CONNECTORS_URL="https://claude.ai/settings/connectors"
OPEN_BROWSER=1
VERIFY_ONLY=0

print_help() {
  cat <<EOF
Activate Claude.ai connectors (MCP).

Options:
  --no-browser    Don't try to open the connectors page
  --verify-only   Skip the URL/instructions; just run \`claude mcp list\`
  -h, --help      Show this help

After authorizing in the browser, this script runs \`claude mcp list\` so
you can confirm the connector is visible to your local CLI.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --no-browser)  OPEN_BROWSER=0 ;;
    --verify-only) VERIFY_ONLY=1 ;;
    -h|--help)     print_help; exit 0 ;;
    *) echo_error "Unknown argument: $arg"; print_help; exit 1 ;;
  esac
done

verify_mcp() {
  if ! command -v claude >/dev/null 2>&1; then
    echo_error "claude CLI not on PATH. Install with: ~/env/claude-install.sh"
    return 1
  fi
  echo ""
  echo_running "claude mcp list"
  echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
  claude mcp list
  echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
}

if [ "$VERIFY_ONLY" -eq 1 ]; then
  verify_mcp
  exit $?
fi

open_url() {
  local url="$1"
  for cmd in xdg-open open sensible-browser firefox google-chrome chromium; do
    if command -v "$cmd" >/dev/null 2>&1; then
      echo_running "Opening $url with $cmd"
      "$cmd" "$url" >/dev/null 2>&1 &
      return 0
    fi
  done
  return 1
}

# ---- menu --------------------------------------------------------------
echo ""
echo -e "${bldcyn}╔═════════════════════════════════════════════════════════════╗${NC}"
echo -e "${bldcyn}║              Claude.ai connectors — activation              ║${NC}"
echo -e "${bldcyn}╚═════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo_info "Common connectors (each is a separate OAuth flow):"
echo "    Slack         — search threads, drafts, labels"
echo "    Gmail         — drafts, labels, thread search"
echo "    Atlassian     — Jira issues, Confluence pages"
echo "    Google Drive  — read/search docs"
echo "    Google Cal    — read events"
echo "    Notion        — pages and databases"
echo ""
echo_info "Connectors page: ${CONNECTORS_URL}"
echo ""

if [ "$OPEN_BROWSER" -eq 1 ]; then
  if ! open_url "$CONNECTORS_URL"; then
    echo_warning "No browser command found. Open this URL manually in any browser:"
    echo "    ${CONNECTORS_URL}"
  fi
fi

echo ""
echo "Steps in the browser:"
echo "  1. Find the connector you want and click 'Connect'"
echo "  2. Complete the provider's OAuth flow (Slack workspace / Google /"
echo "     Atlassian site / …)"
echo "  3. Pick allowed scopes (channels, accounts, sites, …)"
echo "  4. Come back here and press Enter to verify"
echo ""
read -r -p "Press Enter when done (or Ctrl-C to abort)... " _

verify_mcp

echo ""
echo_info "Tip: inside any \`claude\` session, type '/mcp' to see live status."
