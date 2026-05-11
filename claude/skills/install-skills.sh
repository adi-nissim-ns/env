#!/bin/bash
# ------------------------------------------------------------------
# install-skills.sh
#
# Wire the skills in ~/env/claude/skills/* into ~/.claude/skills/
# so Claude Code discovers them on startup.
#
# Usage:
#   ./install-skills.sh             symlink each skill (recommended)
#   ./install-skills.sh --copy      copy instead of symlink
#   ./install-skills.sh --uninstall remove any links/copies we own
#   ./install-skills.sh --help
# ------------------------------------------------------------------

set -u

_SKILLS_SRC=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
_ENV_ROOT=$(dirname "$(dirname "$_SKILLS_SRC")")

# shellcheck source=../../.bashrc.basic_funcs
source "${_ENV_ROOT}/.bashrc.basic_funcs"

DEST="${HOME}/.claude/skills"
MODE="symlink"   # symlink | copy | uninstall

print_help() {
  cat <<EOF
Install env-aware Claude skills into ${DEST}.

Options:
  --copy        Copy instead of symlink (no auto-update on git pull)
  --uninstall   Remove our skills from ${DEST}
  -h, --help    Show this help
EOF
}

for arg in "$@"; do
  case "$arg" in
    --copy)      MODE="copy" ;;
    --uninstall) MODE="uninstall" ;;
    -h|--help)   print_help; exit 0 ;;
    *) echo_error "Unknown argument: $arg"; print_help; exit 1 ;;
  esac
done

mkdir -p "$DEST"

# Skill name = each subdirectory of _SKILLS_SRC that contains a SKILL.md
mapfile -t SKILLS < <(find "$_SKILLS_SRC" -mindepth 2 -maxdepth 2 -name SKILL.md -printf '%h\n' | sort)

if [ "${#SKILLS[@]}" -eq 0 ]; then
  echo_warning "No skills found under $_SKILLS_SRC"
  exit 1
fi

for src_dir in "${SKILLS[@]}"; do
  name=$(basename "$src_dir")
  target="${DEST}/${name}"

  case "$MODE" in
    uninstall)
      if [ -L "$target" ]; then
        rm "$target"
        echo_success "Unlinked $target"
      elif [ -d "$target" ]; then
        # only remove if it's a copy of ours — check for SKILL.md presence + matches
        if [ -f "$target/SKILL.md" ] && cmp -s "$target/SKILL.md" "$src_dir/SKILL.md"; then
          rm -rf "$target"
          echo_success "Removed copy at $target"
        else
          echo_warning "Skipping $target (not ours or modified)"
        fi
      fi
      ;;

    symlink)
      if [ -L "$target" ]; then
        # Already a symlink — re-point if needed
        ln -sfn "$src_dir" "$target"
        echo_info "Refreshed symlink: $target -> $src_dir"
      elif [ -e "$target" ]; then
        echo_warning "Skipping $target (exists and is not a symlink)"
      else
        ln -s "$src_dir" "$target"
        echo_success "Linked $name"
      fi
      ;;

    copy)
      if [ -L "$target" ]; then
        echo_warning "Replacing existing symlink at $target with a copy"
        rm "$target"
      fi
      mkdir -p "$target"
      cp -r "$src_dir/." "$target/"
      echo_success "Copied $name"
      ;;
  esac
done

echo ""
echo_info "Restart any running Claude Code session to pick up the changes."
