#!/usr/bin/env bash
# RTK installer for NextSilicon dev servers
# Usage: bash install.sh --install [TARBALL] | --uninstall | --help
set -euo pipefail

BINARY_NAME="rtk"
INSTALL_DIR="${HOME}/.local/bin"
SETTINGS_FILE="${HOME}/.claude/settings.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── helpers ───────────────────────────────────────────────────────────────────

info()  { echo "[rtk-install] $*"; }
warn()  { echo "[rtk-install] WARN: $*" >&2; }
die()   { echo "[rtk-install] ERROR: $*" >&2; exit 1; }

usage() {
    cat <<'EOF'
Usage: bash install.sh COMMAND [TARBALL]

Commands:
  --install [TARBALL]   Install rtk and wire the Claude Code hook.
                        TARBALL is optional: if omitted the script looks for
                        rtk-linux-*.tar.gz next to itself.
  --uninstall           Remove the rtk binary and Claude Code hook.
  --help                Show this message.

Examples:
  bash install.sh --install
  bash install.sh --install rtk-linux-x86_64.tar.gz
  bash install.sh --uninstall
EOF
}

# ── Python helpers (merge / remove Claude Code hook) ─────────────────────────

# Merge the Claude Code PreToolUse hook into settings.json using Python.
# Handles: file missing, empty file, existing hooks with other matchers.
merge_hook() {
    python3 - "${SETTINGS_FILE}" <<'PYEOF'
import json, sys, os
from pathlib import Path

path = sys.argv[1]
os.makedirs(os.path.dirname(path), exist_ok=True)

try:
    with open(path) as f:
        cfg = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    cfg = {}

hook_entry = {"type": "command", "command": "rtk hook claude"}
matcher    = {"matcher": "Bash", "hooks": [hook_entry]}

hooks = cfg.setdefault("hooks", {})
pre   = hooks.setdefault("PreToolUse", [])

# check if our hook is already there
for entry in pre:
    if entry.get("matcher") == "Bash":
        for h in entry.get("hooks", []):
            if "rtk hook claude" in h.get("command", ""):
                print("  hook already present — nothing to do")
                sys.exit(0)

pre.append(matcher)

with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")

print(f"  hook added to {path}")
PYEOF
}

# Remove only the rtk hook entry from settings.json, leave everything else.
remove_hook() {
    python3 - "${SETTINGS_FILE}" <<'PYEOF'
import json, sys, os

path = sys.argv[1]
if not os.path.exists(path):
    print("  settings.json not found — nothing to do")
    sys.exit(0)

with open(path) as f:
    cfg = json.load(f)

pre = cfg.get("hooks", {}).get("PreToolUse", [])
new_pre = []
removed = False
for entry in pre:
    if entry.get("matcher") == "Bash":
        filtered = [h for h in entry.get("hooks", []) if "rtk hook claude" not in h.get("command", "")]
        if len(filtered) != len(entry.get("hooks", [])):
            removed = True
        if filtered:
            new_pre.append({**entry, "hooks": filtered})
    else:
        new_pre.append(entry)

if not removed:
    print("  rtk hook not found — nothing to do")
    sys.exit(0)

cfg["hooks"]["PreToolUse"] = new_pre

with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")

print(f"  hook removed from {path}")
PYEOF
}

# ── resolve binary source ─────────────────────────────────────────────────────
# Sets global BINARY_SRC; uses a tmpdir cleaned up on script EXIT.

BINARY_SRC=""

resolve_binary() {
    local tarball="${1:-}"

    # if no tarball given, auto-detect one next to this script
    if [[ -z "${tarball}" ]]; then
        tarball=$(ls "${SCRIPT_DIR}"/rtk-linux-*.tar.gz 2>/dev/null | head -1 || true)
    fi

    [[ -n "${tarball}" ]] || die "No tarball found. Provide one: bash install.sh --install rtk-linux-x86_64.tar.gz"
    [[ -f "${tarball}" ]] || die "Tarball not found: ${tarball}"

    local tmpdir
    tmpdir=$(mktemp -d)
    trap "rm -rf '${tmpdir}'" EXIT
    info "Extracting binary from $(basename "${tarball}")..."
    tar -xzf "${tarball}" -C "${tmpdir}" "${BINARY_NAME}" \
        || die "Failed to extract ${BINARY_NAME} from ${tarball}"
    BINARY_SRC="${tmpdir}/${BINARY_NAME}"
}

# ── install ───────────────────────────────────────────────────────────────────

do_install() {
    resolve_binary "${1:-}"

    info "Installing rtk v$("${BINARY_SRC}" --version 2>/dev/null | awk '{print $2}' || echo '?')..."

    mkdir -p "${INSTALL_DIR}"
    cp "${BINARY_SRC}" "${INSTALL_DIR}/${BINARY_NAME}"
    chmod +x "${INSTALL_DIR}/${BINARY_NAME}"
    info "Binary installed to ${INSTALL_DIR}/${BINARY_NAME}"

    if ! echo ":${PATH}:" | grep -q ":${INSTALL_DIR}:"; then
        # Detect shell profile file.
        # On systems where ~/.bashrc is admin-managed, each user has ~/.bashrc.$USER.
        local profile
        case "${SHELL:-}" in
            */zsh) profile="${HOME}/.zshrc" ;;
            *)
                if [[ -f "${HOME}/.bashrc.${USER}" ]]; then
                    profile="${HOME}/.bashrc.${USER}"
                else
                    profile="${HOME}/.bashrc"
                fi
                ;;
        esac
        local export_line='export PATH="${HOME}/.local/bin:${PATH}"'
        if ! grep -qF "${export_line}" "${profile}" 2>/dev/null; then
            echo "" >> "${profile}"
            echo "# Added by rtk installer" >> "${profile}"
            echo "${export_line}" >> "${profile}"
            info "Added ${INSTALL_DIR} to PATH in ${profile}"
            info "Run: source ${profile}   (or open a new terminal)"
        else
            info "${INSTALL_DIR} already in ${profile} — open a new terminal to pick it up"
        fi
    fi

    "${INSTALL_DIR}/${BINARY_NAME}" --version > /dev/null \
        || die "Binary does not run — wrong architecture or missing libc?"

    if [[ ! -d "${HOME}/.claude" ]]; then
        warn "~/.claude directory not found — is Claude Code installed?"
        warn "Hook not installed. Run the following after installing Claude Code:"
        warn "  rtk init -g"
        exit 0
    fi

    info "Merging Claude Code hook into ${SETTINGS_FILE}..."
    merge_hook

    info "Done. Restart Claude Code (or start a new session) to activate the hook."
    info "Test with: git status   (output should be compressed)"
    info "Toggle off per-command: RTK_DISABLED=1 git status"
}

# ── uninstall ─────────────────────────────────────────────────────────────────

do_uninstall() {
    info "Uninstalling rtk..."
    remove_hook
    if [[ -f "${INSTALL_DIR}/${BINARY_NAME}" ]]; then
        rm "${INSTALL_DIR}/${BINARY_NAME}"
        info "Binary removed from ${INSTALL_DIR}/${BINARY_NAME}"
    else
        warn "Binary not found at ${INSTALL_DIR}/${BINARY_NAME}"
    fi
    info "Done."
}

# ── entry point ───────────────────────────────────────────────────────────────

case "${1:-}" in
    --install)   do_install "${2:-}" ;;
    --uninstall) do_uninstall ;;
    --help|-h)   usage ;;
    "")          usage ;;
    *)           die "Unknown argument: ${1}. Run 'bash install.sh --help' for usage." ;;
esac
