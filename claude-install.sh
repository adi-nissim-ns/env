#!/bin/bash
# ------------------------------------------------------------------
# claude-install.sh
#
# Per-user install of the Claude Code CLI (https://claude.com/claude-code).
# Uses Anthropic's official installer — no sudo required.
#
# Usage:
#   ./claude-install.sh           # install (skip if already present)
#   ./claude-install.sh --force   # reinstall even if already present
#   ./claude-install.sh --help
# ------------------------------------------------------------------

set -u

_ENV_PROJECT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")

# shellcheck source=.bashrc.basic_funcs
source "${_ENV_PROJECT_DIR}/.bashrc.basic_funcs"

INSTALL_URL="https://claude.ai/install.sh"
FORCE=0

print_help() {
  cat <<EOF
Install the Claude Code CLI for the current user (\$USER=$USER).

Options:
  --force    Reinstall even if 'claude' is already on PATH
  -h, --help Show this help

The installer fetches ${INSTALL_URL} and runs it under your user account.
After install, run 'claude' once to authenticate via browser.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    -h|--help) print_help; exit 0 ;;
    *) echo_error "Unknown argument: $arg"; print_help; exit 1 ;;
  esac
done

# ---- pre-flight checks --------------------------------------------------
if ! command -v curl >/dev/null 2>&1; then
  echo_error "curl is required but not found. Install curl and re-run."
  exit 1
fi

if [ "$FORCE" -eq 0 ] && command -v claude >/dev/null 2>&1; then
  CURRENT_VERSION=$(claude --version 2>/dev/null || echo "unknown")
  echo_success "Claude Code already installed: ${CURRENT_VERSION}"
  echo_info "Path: $(command -v claude)"
  echo_info "Use --force to reinstall."
  exit 0
fi

# ---- install ------------------------------------------------------------
echo_running "Downloading and running Claude Code installer from ${INSTALL_URL}"
if ! curl -fsSL "${INSTALL_URL}" | bash; then
  echo_error "Claude Code installation failed."
  exit 1
fi
echo_success "Installer finished."

# ---- post-install verification -----------------------------------------
# The installer typically drops the binary in ~/.local/bin or ~/.claude/local
# Make sure those are on PATH for this shell so verification can find it.
for d in "$HOME/.local/bin" "$HOME/.claude/local"; do
  if [ -d "$d" ] && [[ ":$PATH:" != *":$d:"* ]]; then
    export PATH="$d:$PATH"
  fi
done

if ! command -v claude >/dev/null 2>&1; then
  echo_warning "'claude' not found on PATH yet. Open a new shell or run:"
  echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
  exit 1
fi

INSTALLED_VERSION=$(claude --version 2>/dev/null || echo "unknown")
echo_success "Installed: ${INSTALLED_VERSION}"
echo_info    "Path:      $(command -v claude)"

# ---- next steps ---------------------------------------------------------
cat <<EOF

Next steps:
  1. Open a new shell (or source your bashrc) so 'claude' is on PATH.
  2. Run 'claude' in any project directory — first run opens a browser
     for authentication. Credentials are cached locally afterwards.
  3. Docs: https://docs.claude.com/en/docs/claude-code/quickstart
EOF
