#!/bin/bash
# swkit-install.sh — NextSilicon swkit interactive installer

set -uo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
ARTIFACTORY_HOST="https://artifactory.k8s.nextsilicon.com"
REPO="generic-repo"
BASE_PATH="nextsilicon-files"

# Auto-detect OS key (e.g., rocky-9)
if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    source /etc/os-release
    OS_KEY="${ID}-${VERSION_ID%%.*}"
else
    OS_KEY="rocky-9"
fi

BASHRC="${HOME}/.bashrc.${USER}"

# Optional: export ARTIFACTORY_API_KEY for authenticated access
API_KEY="${ARTIFACTORY_API_KEY:-}"

# Source swkit-githash / swkit-date helpers so _best_file can rank installers
# by commit date instead of the embedded build number — build numbers across
# channels and forks (244 vs 2621) don't reliably reflect chronology.
GITHASH_HELPERS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.bashrc.swkit-githash"
if [[ -f "$GITHASH_HELPERS" ]]; then
    # shellcheck source=/dev/null
    source "$GITHASH_HELPERS"
fi

# ── Colors (only if stdout is a terminal) ─────────────────────────────────────
if [[ -t 1 ]]; then
    YELLOW=$'\033[1;33m'
    GREEN=$'\033[1;32m'
    RED=$'\033[1;31m'
    NC=$'\033[0m'
else
    YELLOW=""; GREEN=""; RED=""; NC=""
fi

# ── Low-level helpers ──────────────────────────────────────────────────────────
_curl() {
    local -a args=(-sf)
    [[ -n "$API_KEY" ]] && args+=(-H "X-JFrog-Art-Api: $API_KEY")
    curl "${args[@]}" "$@"
}

# Extract build number from filename (the trailing -NNNN before .sh)
# stable-next-sw-kit-rocky-9-1.2.0-244.sh  →  244
# ns-sw-kit-rocky-9-1.2.0-2621.sh          →  2621
_build_num() {
    echo "$1" | sed 's/\.sh$//' | rev | cut -d'-' -f1 | rev
}

# Map filename prefix to quality label
_quality() {
    case "$1" in
        do-not-use-*)   echo "do-not-use" ;;
        *-remove.sh)    echo "remove"     ;;
        stable-*)       echo "stable"     ;;
        verified-*)     echo "verified"   ;;
        ns-sw-kit-*)    echo "latest"     ;;
        untested-*)     echo "untested"   ;;
        unstable-*)     echo "unstable"   ;;
        *)              echo "unknown"    ;;
    esac
}

# Numeric sort weight for quality (lower = better)
_quality_rank() {
    case "$1" in
        stable)   echo 1 ;;
        verified) echo 2 ;;
        latest)   echo 3 ;;
        untested) echo 4 ;;
        unstable) echo 5 ;;
        *)        echo 9 ;;
    esac
}

# List version subdirectories for channel/OS; one per line, sorted ascending.
# The Artifactory response is pretty-printed JSON, so we flatten to one line first.
_list_versions() {
    local channel="$1"
    local url="${ARTIFACTORY_HOST}/artifactory/api/storage/${REPO}/${BASE_PATH}/${channel}/${OS_KEY}"
    local resp
    resp=$(_curl "$url" 2>/dev/null) || return 1
    echo "$resp" \
        | tr '\n' ' ' \
        | tr '}' '\n' \
        | grep -E '"folder"[[:space:]]*:[[:space:]]*true' \
        | grep -oE '"uri"[[:space:]]*:[[:space:]]*"[^"]*"' \
        | sed 's/.*"\/\([^"]*\)"/\1/' \
        | grep -E '^[0-9]' \
        | sort -V
}

# List usable installer files in channel/OS/version; one per line.
# Excludes: do-not-use-* and *-remove.sh
_list_files() {
    local channel="$1" version="$2"
    local url="${ARTIFACTORY_HOST}/artifactory/api/storage/${REPO}/${BASE_PATH}/${channel}/${OS_KEY}/${version}"
    local resp
    resp=$(_curl "$url" 2>/dev/null) || return 1
    echo "$resp" \
        | tr '\n' ' ' \
        | tr '}' '\n' \
        | grep -E '"folder"[[:space:]]*:[[:space:]]*false' \
        | grep -oE '"uri"[[:space:]]*:[[:space:]]*"[^"]*"' \
        | sed 's/.*"\/\([^"]*\)"/\1/' \
        | grep -v '^$' \
        | grep -Ev '(^do-not-use-|-remove\.sh$)'
}

# Read from stdin: return the newest file by commit date (via swkit-date, when
# available); falls back to highest build number when the date can't be
# resolved. If quality_filter is given, only consider files of that quality.
_best_file() {
    local quality_filter="${1:-}"
    local -a candidates=()
    local fname q
    while IFS= read -r fname; do
        [[ -z "$fname" ]] && continue
        if [[ -n "$quality_filter" ]]; then
            q=$(_quality "$fname")
            [[ "$q" != "$quality_filter" ]] && continue
        fi
        candidates+=("$fname")
    done

    [[ ${#candidates[@]} -eq 0 ]] && return 0

    if command -v swkit-date &>/dev/null; then
        local best_fname="" best_date="" d
        for fname in "${candidates[@]}"; do
            d=$(swkit-date "$fname" 2>/dev/null) || d=""
            [[ -z "$d" ]] && continue
            if [[ -z "$best_date" || "$d" > "$best_date" ]]; then
                best_date="$d"
                best_fname="$fname"
            fi
        done
        [[ -n "$best_fname" ]] && { echo "$best_fname"; return 0; }
    fi

    local best="" best_build=-1 b
    for fname in "${candidates[@]}"; do
        b=$(_build_num "$fname")
        [[ "$b" =~ ^[0-9]+$ ]] || continue
        (( b > best_build )) && { best_build=$b; best="$fname"; }
    done
    [[ -n "$best" ]] && echo "$best"
    return 0
}

# Parse latest.txt from release channel; echo "version|filename" if valid
_read_latest_txt() {
    local url="${ARTIFACTORY_HOST}/artifactory/${REPO}/${BASE_PATH}/release/${OS_KEY}/latest.txt"
    local content
    content=$(_curl "$url" 2>/dev/null) || return 1
    local path_part
    path_part=$(echo "$content" | grep -o "release/${OS_KEY}/[^[:space:]]*" | head -1)
    [[ -z "$path_part" ]] && return 1
    local version filename
    version=$(echo "$path_part" | cut -d'/' -f3)
    filename=$(echo "$path_part" | cut -d'/' -f4 | tr -d '*')
    [[ -z "$version" || -z "$filename" ]] && return 1
    echo "${version}|${filename}"
}

# ── swkit clear ───────────────────────────────────────────────────────────────
# Removes all installed NextSilicon components: DKMS modules, RPMs, /opt/nextsilicon.
# Needed because the installer cannot overwrite an existing DKMS registration.
_clear_swkit() {
    # Collect what's installed
    local rpms dkms_mods
    rpms=$(rpm -qa 2>/dev/null | grep -iE '^(next|ns-sw)') || rpms=""
    if command -v dkms &>/dev/null; then
        dkms_mods=$(dkms status 2>/dev/null \
            | grep -oE '^[a-zA-Z][^,/ ]+/[^, ]+' \
            | grep -i next | sort -u) || dkms_mods=""
    else
        dkms_mods=""
    fi

    # nextruntime's %post creates this with plain `ln -s` (no -f); a leftover
    # from a previous install makes the scriptlet exit 1 on reinstall.
    local binfmt_conf="/usr/lib/binfmt.d/nextloader.conf"
    local has_binfmt=0
    [[ -e "$binfmt_conf" || -L "$binfmt_conf" ]] && has_binfmt=1

    # Same problem: nextruntime's %post does `cp -s` (no -f) for these systemd
    # user-unit symlinks, and `rpm -e` doesn't clean them up.
    local user_links=(
        /usr/lib/systemd/user/nextsilicon.service
        /usr/lib/systemd/user/nextsilicon-no-hardware.service.d/20-no-hardware.conf
        /usr/lib/systemd/user/nextsilicon@.service.d/drop_in.conf
    )
    local stale_user_links=()
    local l
    for l in "${user_links[@]}"; do
        [[ -e "$l" || -L "$l" ]] && stale_user_links+=("$l")
    done

    if [[ -z "$rpms" && -z "$dkms_mods" && ! -d /opt/nextsilicon && $has_binfmt -eq 0 && ${#stale_user_links[@]} -eq 0 ]]; then
        echo "  Nothing to clear."
        return 0
    fi

    echo "  Will remove:"
    [[ -n "$dkms_mods" ]]              && echo "    DKMS      : $(echo "$dkms_mods" | tr '\n' ' ')"
    [[ -n "$rpms" ]]                   && echo "    RPMs      : $(echo "$rpms"      | tr '\n' ' ')"
    [[ -d /opt/nextsilicon ]]          && echo "    Directory : /opt/nextsilicon"
    [[ $has_binfmt -eq 1 ]]            && echo "    Binfmt    : ${binfmt_conf}"
    [[ ${#stale_user_links[@]} -gt 0 ]] && echo "    User units: ${stale_user_links[*]}"

    if [[ -n "$dkms_mods" ]]; then
        while IFS= read -r mod; do
            [[ -z "$mod" ]] && continue
            echo "  Removing DKMS module: ${mod}"
            sudo dkms remove "$mod" --all 2>/dev/null || true
        done <<< "$dkms_mods"
    fi

    if [[ -n "$rpms" ]]; then
        echo "  Removing RPMs..."
        echo "$rpms" | xargs sudo rpm -e --nodeps 2>/dev/null || true
    fi

    if [[ -d /opt/nextsilicon ]]; then
        echo "  Removing /opt/nextsilicon..."
        sudo rm -rf /opt/nextsilicon
    fi

    if [[ $has_binfmt -eq 1 ]]; then
        echo "  Removing ${binfmt_conf}..."
        sudo rm -f "$binfmt_conf"
        sudo systemctl restart systemd-binfmt.service 2>/dev/null || true
    fi

    if [[ ${#stale_user_links[@]} -gt 0 ]]; then
        echo "  Removing stale systemd user-unit symlinks..."
        sudo rm -f "${stale_user_links[@]}"
    fi
}

# ── bashrc update ──────────────────────────────────────────────────────────────
# Inserts "source /etc/profile.d/nextsilicon.sh" right after the existing
# "export NEXT_HOME=..." line so swkit overrides the custom build path.
# Remove that source line to revert to the custom build.
_update_bashrc() {
    touch "$BASHRC"

    # Already activated?
    if grep -qF 'source /etc/profile.d/nextsilicon.sh' "$BASHRC"; then
        echo "  [bashrc] swkit already activated in ${BASHRC}"
        return 0
    fi

    local need_path=1
    grep -q 'NEXT_HOME.*bin' "$BASHRC" 2>/dev/null && need_path=0

    if grep -q 'export NEXT_HOME' "$BASHRC" 2>/dev/null; then
        # Insert source line (+ PATH export if absent) right after NEXT_HOME= line
        local tmp="${BASHRC}.swkit.tmp"
        awk -v add_path="$need_path" '
            /export NEXT_HOME/ {
                print
                print "source /etc/profile.d/nextsilicon.sh  # swkit — remove to revert to custom build"
                if (add_path == "1") print "export PATH=$NEXT_HOME/bin:$NEXT_HOME/sysroot/usr/bin:$PATH"
                next
            }
            { print }
        ' "$BASHRC" > "$tmp" && mv "$tmp" "$BASHRC"
        echo "  [bashrc] Inserted swkit activation after NEXT_HOME in ${BASHRC}"
    else
        {
            printf '\n# NextSilicon swkit activation — added by swkit-install.sh\n'
            printf 'source /etc/profile.d/nextsilicon.sh\n'
            [[ $need_path -eq 1 ]] && printf 'export PATH=$NEXT_HOME/bin:$NEXT_HOME/sysroot/usr/bin:$PATH\n'
        } >> "$BASHRC"
        echo "  [bashrc] Appended swkit activation to ${BASHRC}"
    fi
}

# ── Core install ───────────────────────────────────────────────────────────────
_install() {
    local channel="$1" version="$2" filename="$3"
    local quality
    quality=$(_quality "$filename")

    echo ""
    echo "  File    : ${filename}"
    echo "  Channel : ${channel}    Version : ${version}    Quality : ${quality}"
    echo ""

    # Ask all options up front before any downloading
    local lib_ans lib_arg="--no-nextsilicon-libs"
    echo "  swkit includes two compute libraries: nextfft and nextblas (C++ with C"
    echo "  and Fortran interfaces). If you are developing a custom build of either"
    echo "  library, skip this — swkit's copies may conflict with your local build."
    echo "  For all other users, installing the libraries is recommended."
    read -rp "${GREEN}  Install NextSilicon libraries? [${RED}y${GREEN}/${GREEN}N${GREEN}]: ${NC}" lib_ans
    [[ "$lib_ans" =~ ^[Yy]$ ]] && lib_arg=""

    local clear_ans clear_opt=1
    echo ""
    echo "  Clearing removes existing swkit packages, DKMS modules, and /opt/nextsilicon"
    echo "  before the fresh install. Recommended when downgrading swkit (old files may"
    echo "  otherwise linger) or when switching from a with-libraries to a"
    echo "  without-libraries install. Safe to skip only on a first-time install."
    read -rp "${GREEN}  Clear /opt/nextsilicon before install? [${GREEN}Y${GREEN}/${RED}n${GREEN}]: ${NC}" clear_ans
    [[ "$clear_ans" =~ ^[Nn]$ ]] && clear_opt=0

    local bashrc_ans update_bashrc=0
    echo ""
    echo "  swkit always installs into /opt/nextsilicon. If you maintain a custom-built"
    echo "  nextutils stack, your NEXT_HOME may currently point to that location instead."
    echo "  Choosing Y updates your ~/.bashrc.USER to source swkit's environment and"
    echo "  exports NEXT_HOME immediately so the change takes effect in the current shell."
    echo "  Choose N to keep using your custom build."
    read -rp "${GREEN}  Update ${BASHRC} to activate swkit? [${GREEN}Y${GREEN}/${RED}n${GREEN}]: ${NC}" bashrc_ans
    [[ "$bashrc_ans" =~ ^[Nn]$ ]] || update_bashrc=1
    echo ""

    local dl_url="${ARTIFACTORY_HOST}/artifactory/${REPO}/${BASE_PATH}/${channel}/${OS_KEY}/${version}/${filename}"
    local tmpdir
    tmpdir=$(mktemp -d)
    trap '[[ -n "${tmpdir:-}" ]] && rm -rf "$tmpdir"; trap - RETURN' RETURN

    echo "  Downloading..."
    wget -q --show-progress -O "${tmpdir}/${filename}" "$dl_url" \
        || { echo "  Download failed."; return 1; }
    chmod +x "${tmpdir}/${filename}"

    if [[ $clear_opt -eq 1 ]]; then
        echo "  Clearing previous swkit installation..."
        _clear_swkit
    fi

    echo "  Running installer (sudo required)..."
    # Invoke from $tmpdir so the installer's trailing popd lands in /tmp, not
    # the caller's cwd — on NFS root_squash homes root cannot chdir back and
    # popd exits 1, falsely flagging the install as failed.
    if [[ -n "$lib_arg" ]]; then
        ( cd "$tmpdir" && sudo "./${filename}" "$lib_arg" ) || { echo "  Installer failed."; return 1; }
    else
        ( cd "$tmpdir" && sudo "./${filename}" ) || { echo "  Installer failed."; return 1; }
    fi

    [[ -f /etc/profile.d/nextsilicon.sh ]] && source /etc/profile.d/nextsilicon.sh

    if [[ $update_bashrc -eq 1 ]]; then
        _update_bashrc
        export NEXT_HOME=/opt/nextsilicon
        echo ""
        echo "Done! Apply changes in current shell:  source ${BASHRC}"
    else
        echo ""
        echo "Done!"
    fi
}

# ── UI helpers ─────────────────────────────────────────────────────────────────
_confirm() {
    local ans
    read -rp "${GREEN}$1 [${RED}y${GREEN}/${GREEN}N${GREEN}]: ${NC}" ans
    [[ "$ans" =~ ^[Yy]$ ]]
}

_offer_clear() {
    if _confirm "  Clear existing swkit installation?"; then
        _clear_swkit
    fi
}

# ── Flow 1: install last stable ────────────────────────────────────────────────
# Uses release/latest.txt as the authoritative pointer.
# Falls back to the highest-build stable-* file in the latest release version.
_flow_stable() {
    local version filename files latest_info

    echo "Looking up latest stable kit..."

    if latest_info=$(_read_latest_txt 2>/dev/null) && [[ -n "$latest_info" ]]; then
        version="${latest_info%%|*}"
        filename="${latest_info##*|}"
        files=$(_list_files "release" "$version" 2>/dev/null) || files=""
        if echo "$files" | grep -qxF "$filename"; then
            echo "  Latest stable (latest.txt): release/${version}/${filename}"
            if _confirm "Install?"; then
                _install "release" "$version" "$filename"
            else
                _offer_clear
            fi
            return 0
        fi
        echo "  (latest.txt target not found — scanning release channel)"
    fi

    # Fallback: highest-build stable-* (or any file) in latest release version
    version=$(_list_versions "release" | tail -1) \
        || { echo "  No versions found in release channel."; return 1; }
    [[ -z "$version" ]] && { echo "  No versions found in release channel."; return 1; }

    files=$(_list_files "release" "$version") \
        || { echo "  Could not list files in release/${version}."; return 1; }

    filename=$(echo "$files" | _best_file "stable")
    [[ -z "$filename" ]] && filename=$(echo "$files" | _best_file "")
    [[ -z "$filename" ]] && { echo "  No kit found in release/${version}."; return 1; }

    echo "  Found: release/${version}/${filename}"
    if _confirm "Install?"; then
        _install "release" "$version" "$filename"
    else
        _offer_clear
    fi
}

# ── Flow 2: install last stable RC (rc channel, stable-* prefix) ──────────────
_flow_stable_rc() {
    local ver files filename

    echo "Looking up latest stable RC..."
    ver=$(_list_versions "rc" 2>/dev/null | tail -1)
    [[ -z "$ver" ]] && { echo "  No RC versions found for ${OS_KEY}."; return 1; }
    files=$(_list_files "rc" "$ver" 2>/dev/null) \
        || { echo "  Could not list files in rc/${ver}."; return 1; }
    filename=$(echo "$files" | _best_file "stable")
    [[ -z "$filename" ]] && { echo "  No stable RC kit found in rc/${ver}."; return 1; }

    echo "  Found: rc/${ver}/${filename}"
    if _confirm "Install?"; then
        _install "rc" "$ver" "$filename"
    else
        _offer_clear
    fi
}

# ── Flow 3: install latest kit ─────────────────────────────────────────────────
# Picks the chronologically newest file (by commit date, via swkit-date) in the
# latest rc version, regardless of quality prefix. Falls back to release.
_flow_latest() {
    local channel ver files filename

    echo "Looking up latest kit..."

    filename=""
    for channel in "rc" "release"; do
        ver=$(_list_versions "$channel" 2>/dev/null | tail -1) || continue
        [[ -z "$ver" ]] && continue
        files=$(_list_files "$channel" "$ver" 2>/dev/null) || continue
        filename=$(echo "$files" | _best_file "")
        [[ -n "$filename" ]] && break
    done

    [[ -z "$filename" ]] && { echo "  No kits found."; return 1; }
    echo "  Found: ${channel}/${ver}/${filename}"
    if _confirm "Install?"; then
        _install "$channel" "$ver" "$filename"
    else
        _offer_clear
    fi
}

# ── Flow 3: list versions → pick version → list files → pick file → install ───
_flow_select() {
    # Step 1 — pick a version
    echo "Fetching available versions..."

    local -a V_CHANNELS=() V_VERSIONS=()
    local channel ver

    for channel in "release" "rc"; do
        while IFS= read -r ver; do
            V_CHANNELS+=("$channel")
            V_VERSIONS+=("$ver")
        done < <(_list_versions "$channel" 2>/dev/null | sort -rV)
    done

    if [[ ${#V_VERSIONS[@]} -eq 0 ]]; then
        echo "No versions found for ${OS_KEY}."
        return 1
    fi

    echo ""
    printf "  %-4s  %-9s  %s\n"  "#"    "Channel"   "Version"
    printf "  %-4s  %-9s  %s\n"  "----" "---------" "-------"
    local i
    for i in "${!V_VERSIONS[@]}"; do
        printf "  %-4s  %-9s  %s\n" "$((i+1))" "${V_CHANNELS[$i]}" "${V_VERSIONS[$i]}"
    done
    echo ""

    local vsel
    read -rp "${GREEN}Select version (0 to cancel): ${NC}" vsel
    [[ "$vsel" == "0" ]] && { echo "Cancelled."; return 0; }
    if ! [[ "$vsel" =~ ^[0-9]+$ ]] || [[ "$vsel" -lt 1 ]] || [[ "$vsel" -gt "${#V_VERSIONS[@]}" ]]; then
        echo "Invalid selection."
        return 1
    fi

    local vidx=$(( vsel - 1 ))
    local sel_channel="${V_CHANNELS[$vidx]}"
    local sel_version="${V_VERSIONS[$vidx]}"

    # Step 2 — pick a file
    echo ""
    echo "Fetching kits for ${sel_channel}/${sel_version}..."

    local files
    files=$(_list_files "$sel_channel" "$sel_version") \
        || { echo "Could not list files."; return 1; }
    [[ -z "$files" ]] && { echo "No kits found."; return 1; }

    # Sort by quality rank (asc) then build number (desc)
    local sorted_files
    sorted_files=$(
        while IFS= read -r fname; do
            [[ -z "$fname" ]] && continue
            local q b rank
            q=$(_quality "$fname")
            b=$(_build_num "$fname")
            [[ "$b" =~ ^[0-9]+$ ]] || b=0
            rank=$(_quality_rank "$q")
            printf '%d %08d %s\n' "$rank" "$(( 99999999 - b ))" "$fname"
        done <<< "$files" \
        | sort -k1,1n -k2,2n \
        | awk '{print $3}'
    )

    echo ""
    printf "  %-4s  %-10s  %-7s  %s\n"  "#"    "Quality"    "Build"   "File"
    printf "  %-4s  %-10s  %-7s  %s\n"  "----" "----------" "-------" "----"

    local -a F_FILES=()
    local n=1 fname q b
    while IFS= read -r fname; do
        [[ -z "$fname" ]] && continue
        q=$(_quality "$fname")
        b=$(_build_num "$fname")
        printf "  %-4s  %-10s  %-7s  %s\n" "$n" "$q" "$b" "$fname"
        F_FILES+=("$fname")
        n=$(( n + 1 ))
    done <<< "$sorted_files"
    echo ""

    local fsel
    read -rp "${GREEN}Select kit (0 to cancel): ${NC}" fsel
    [[ "$fsel" == "0" ]] && { echo "Cancelled."; return 0; }
    if ! [[ "$fsel" =~ ^[0-9]+$ ]] || [[ "$fsel" -lt 1 ]] || [[ "$fsel" -gt "${#F_FILES[@]}" ]]; then
        echo "Invalid selection."
        return 1
    fi

    local selected="${F_FILES[$(( fsel - 1 ))]}"
    if _confirm "Install ${sel_channel}/${sel_version}/${selected}?"; then
        _install "$sel_channel" "$sel_version" "$selected"
    else
        _offer_clear
    fi
}

# ── Flow 5: clear only ────────────────────────────────────────────────────────
_flow_clear() {
    if _confirm "Clear existing swkit installation?"; then
        _clear_swkit
    else
        echo "Cancelled."
    fi
}

# ── Main ───────────────────────────────────────────────────────────────────────
main() {
    echo "==========================================="
    echo "  NextSilicon swkit Installer"
    echo "  OS detected: ${OS_KEY}"
    echo "==========================================="
    echo ""

    echo "${GREEN}  1) Install last stable kit  [default]${NC}"
    echo "${GREEN}  2) Install last stable RC${NC}"
    echo "${GREEN}  3) Install last kit${NC}"
    echo "${GREEN}  4) List available kits and select${NC}"
    echo "${GREEN}  5) Clear swkit${NC}"
    echo "${GREEN}  6) Exit${NC}"
    echo ""

    local choice
    read -rp "${GREEN}Enter choice [${GREEN}1${GREEN}]: ${NC}" choice
    choice="${choice:-1}"
    echo ""

    case "$choice" in
        1) _flow_stable     ;;
        2) _flow_stable_rc  ;;
        3) _flow_latest     ;;
        4) _flow_select     ;;
        5) _flow_clear      ;;
        6) echo "Bye."      ;;
        *) echo "Invalid choice: '${choice}'"; exit 1 ;;
    esac
}

main "$@"
