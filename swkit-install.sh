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

# Source the swkit-githash helpers so the menu can decorate labels with cached
# commit dates and spawn background workers to populate the cache on first
# launch. Optional — the installer still runs end-to-end without them, just
# without dates.
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

# ── Menu history — adaptive defaults ──────────────────────────────────────────
# Tracks user selections per menu. When the last 3 consecutive picks are the
# same non-default value, that value becomes the new default for that menu.
# Stored in ~/.config/swkit/ (home dir — shared across dev environments).
SWKIT_CONFIG_DIR="${HOME}/.config/swkit"

_log_menu_choice() {
    local menu="$1" choice="$2"
    mkdir -p "$SWKIT_CONFIG_DIR" 2>/dev/null
    echo "$choice" >> "${SWKIT_CONFIG_DIR}/${menu}.history"
}

_get_menu_default() {
    local menu="$1" fallback="$2"
    local hfile="${SWKIT_CONFIG_DIR}/${menu}.history"
    [[ -f "$hfile" ]] || { echo "$fallback"; return; }
    local -a last3=()
    while IFS= read -r line; do
        last3+=("$line")
    done < <(tail -3 "$hfile" 2>/dev/null)
    (( ${#last3[@]} < 3 )) && { echo "$fallback"; return; }
    if [[ "${last3[0]}" == "${last3[1]}" && "${last3[1]}" == "${last3[2]}" ]]; then
        echo "${last3[0]}"
    else
        echo "$fallback"
    fi
}

_clear_local_data() {
    echo "  Clearing all local swkit data..."
    rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}/swkit-githash" 2>/dev/null
    rm -rf "${SWKIT_CONFIG_DIR}" 2>/dev/null
    echo "  Removed: ~/.cache/swkit-githash/ (listings, dates, locks)"
    echo "  Removed: ~/.config/swkit/ (menu history)"
    echo "  Done."
}

# ── Low-level helpers ──────────────────────────────────────────────────────────
_curl() {
    local -a args=(-sf)
    [[ -n "$API_KEY" ]] && args+=(-H "X-JFrog-Art-Api: $API_KEY")
    curl "${args[@]}" "$@"
}

# Disk-cached fetch with TTL. Listings change rarely on the user's timescale
# and the menu issues several of them, so caching makes repeat launches
# instant and lets us pre-warm in parallel on a cold cache.
LISTINGS_TTL="${SWKIT_LISTINGS_TTL:-600}"
LISTINGS_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/swkit-githash/listings"

_curl_cached() {
    local key="$1" url="$2"
    local cache="${LISTINGS_DIR}/${key}"
    if [[ -s "$cache" ]]; then
        local now mtime
        now=$(date +%s 2>/dev/null) || now=0
        mtime=$(stat -c %Y "$cache" 2>/dev/null) || mtime=0
        if (( now - mtime < LISTINGS_TTL )); then
            cat -- "$cache"
            return 0
        fi
    fi
    local content
    content=$(_curl "$url") || return 1
    mkdir -p "$LISTINGS_DIR" 2>/dev/null
    printf '%s' "$content" >"${cache}.tmp.$$" 2>/dev/null \
        && mv -f "${cache}.tmp.$$" "$cache" 2>/dev/null
    printf '%s' "$content"
}

# Cache-only read — never touches the network. Returns 1 on miss. Used by the
# main menu so it never blocks; a detached __refresh worker is responsible
# for keeping the cache populated.
_curl_cache_only() {
    local key="$1"
    local cache="${LISTINGS_DIR}/${key}"
    [[ -s "$cache" ]] || return 1
    cat -- "$cache"
}

# Extract build number from filename (the trailing -NNNN before .sh)
# stable-next-sw-kit-rocky-9-1.2.0-244.sh  →  244
# ns-sw-kit-rocky-9-1.2.0-2621.sh          →  2621
_build_num() {
    echo "$1" | sed 's/\.sh$//' | rev | cut -d'-' -f1 | rev
}

# Heuristic build ordering: trailing number truncated to its first 3 digits.
# Suffixes >3 digits are "buildNNN" + "subversion" (e.g. 2621 -> Jenkins build
# 262 with subversion 1) and the per-fork subversion is not chronological, so
# we rank by the Jenkins build prefix only.
# stable-...-244.sh    → 244
# ns-sw-kit-...-2621.sh → 262
_build_num_heuristic() {
    local b
    b=$(_build_num "$1")
    [[ "$b" =~ ^[0-9]+$ ]] || { echo ""; return 1; }
    (( ${#b} > 3 )) && b="${b:0:3}"
    printf '%s\n' "$b"
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
    local cache_only=0
    [[ "${1:-}" == "--cache-only" ]] && { cache_only=1; shift; }
    local channel="$1"
    local url="${ARTIFACTORY_HOST}/artifactory/api/storage/${REPO}/${BASE_PATH}/${channel}/${OS_KEY}"
    local key="versions_${channel}_${OS_KEY}"
    local resp
    if (( cache_only )); then
        resp=$(_curl_cache_only "$key" 2>/dev/null) || return 1
    else
        resp=$(_curl_cached "$key" "$url" 2>/dev/null) || return 1
    fi
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
    local cache_only=0
    [[ "${1:-}" == "--cache-only" ]] && { cache_only=1; shift; }
    local channel="$1" version="$2"
    local url="${ARTIFACTORY_HOST}/artifactory/api/storage/${REPO}/${BASE_PATH}/${channel}/${OS_KEY}/${version}"
    local key="files_${channel}_${OS_KEY}_${version}"
    local resp
    if (( cache_only )); then
        resp=$(_curl_cache_only "$key" 2>/dev/null) || return 1
    else
        resp=$(_curl_cached "$key" "$url" 2>/dev/null) || return 1
    fi
    echo "$resp" \
        | tr '\n' ' ' \
        | tr '}' '\n' \
        | grep -E '"folder"[[:space:]]*:[[:space:]]*false' \
        | grep -oE '"uri"[[:space:]]*:[[:space:]]*"[^"]*"' \
        | sed 's/.*"\/\([^"]*\)"/\1/' \
        | grep -v '^$' \
        | grep -Ev '(^do-not-use-|-remove\.sh$)'
}

# Read from stdin: return the file with the highest build-number heuristic
# (first 3 digits of the trailing -NNNN suffix). Pure bash — no forks per
# line, so it stays fast even with hundreds of candidates. (Previously this
# delegated to _build_num / _quality, each ~5 subshell forks per file, which
# dominated cold-warm-cache menu latency.)
_best_file() {
    local quality_filter="${1:-}"
    local best="" best_h=-1
    local fname q h
    while IFS= read -r fname; do
        [[ -z "$fname" ]] && continue
        if [[ -n "$quality_filter" ]]; then
            case "$fname" in
                do-not-use-*)   q="do-not-use" ;;
                *-remove.sh)    q="remove"     ;;
                stable-*)       q="stable"     ;;
                verified-*)     q="verified"   ;;
                ns-sw-kit-*)    q="latest"     ;;
                untested-*)     q="untested"   ;;
                unstable-*)     q="unstable"   ;;
                *)              q="unknown"    ;;
            esac
            [[ "$q" != "$quality_filter" ]] && continue
        fi
        h="${fname%.sh}"
        h="${h##*-}"
        [[ "$h" =~ ^[0-9]+$ ]] || continue
        (( ${#h} > 3 )) && h="${h:0:3}"
        if (( 10#$h > best_h )); then
            best_h=$((10#$h))
            best="$fname"
        fi
    done
    [[ -n "$best" ]] && echo "$best"
    return 0
}

# Cached date lookup — returns the cached ISO date (or empty string). Never
# blocks. Used for label decoration in the menu and confirmation prompts.
_cached_date() {
    command -v swkit-date-cached &>/dev/null || { echo ""; return 0; }
    swkit-date-cached "$1" 2>/dev/null || echo ""
}

# Compose a label like "<filename>" or "<filename>, <YYYY-MM-DD>" depending on
# whether the date is already in the local cache.
_label_with_date() {
    local fname="$1" d
    [[ -z "$fname" ]] && { echo ""; return 0; }
    d=$(_cached_date "$fname")
    if [[ -n "$d" ]]; then
        printf '%s, %s\n' "$fname" "${d%%T*}"
    else
        printf '%s\n' "$fname"
    fi
}

# Pre-warm Artifactory listings in parallel. Two rounds: first the latest.txt
# + version listings; then file listings for the newest version per channel.
# Used by the detached __refresh worker — NOT by the foreground menu, which
# reads strictly from the local cache so it never blocks on the network.
_warm_listings() {
    (
        _read_latest_txt >/dev/null 2>&1 &
        _list_versions release >/dev/null 2>&1 &
        _list_versions rc >/dev/null 2>&1 &
        wait
    )

    local rel_ver rc_ver
    rel_ver=$(_list_versions release 2>/dev/null | tail -1)
    rc_ver=$(_list_versions rc 2>/dev/null | tail -1)

    (
        [[ -n "$rel_ver" ]] && _list_files release "$rel_ver" >/dev/null 2>&1 &
        [[ -n "$rc_ver"  ]] && _list_files rc      "$rc_ver"  >/dev/null 2>&1 &
        wait
    )
}

# Detached refresh worker. Warms the listings cache for the next launch and
# spawns per-build date workers for anything newly surfaced. Held by a single
# flock so a flurry of installer launches collapses to one refresher process.
# Invoked via `bash <this-script> __refresh` from _spawn_refresh.
_run_refresh() {
    local lock_dir="${XDG_CACHE_HOME:-$HOME/.cache}/swkit-githash"
    mkdir -p "$lock_dir" 2>/dev/null
    local lock="${lock_dir}/refresh.lock"
    exec 9>"$lock" 2>/dev/null || return 0
    if command -v flock &>/dev/null; then
        flock -n 9 2>/dev/null || return 0
    fi

    _warm_listings

    # Resolve dates ONLY for the three files the menu will show — not every
    # build in the version dir. A version dir often has 30–80 builds; sending
    # an ssh git-fetch for each would flood GitHub and dominate CPU on every
    # launch.
    local _ver _files cand
    local -a menu_files=()
    _ver=$(_list_versions release 2>/dev/null | tail -1)
    if [[ -n "$_ver" ]]; then
        _files=$(_list_files release "$_ver" 2>/dev/null)
        cand=$(echo "$_files" | _best_file "stable")
        [[ -z "$cand" ]] && cand=$(echo "$_files" | _best_file "")
        [[ -n "$cand" ]] && menu_files+=("$cand")
    fi
    _ver=$(_list_versions rc 2>/dev/null | tail -1)
    if [[ -n "$_ver" ]]; then
        _files=$(_list_files rc "$_ver" 2>/dev/null)
        cand=$(echo "$_files" | _best_file "stable")
        [[ -n "$cand" ]] && menu_files+=("$cand")
        cand=$(echo "$_files" | _best_file "")
        [[ -n "$cand" ]] && menu_files+=("$cand")
    fi
    (( ${#menu_files[@]} > 0 )) && _spawn_date_workers "${menu_files[@]}"
}

# Spawn _run_refresh in a fully-detached session so it survives the installer
# exiting. No-ops silently if anything goes wrong — the menu never depends on
# the refresher having succeeded.
_spawn_refresh() {
    local self_dir self_path
    self_dir="$(cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd 2>/dev/null)" || return 0
    self_path="${self_dir}/$(basename -- "${BASH_SOURCE[0]}")"
    [[ -f "$self_path" ]] || return 0
    (
        setsid bash "$self_path" __refresh </dev/null >/dev/null 2>&1 &
    ) 2>/dev/null
}

# Spawn one detached background worker per file with no cached date. Each
# worker takes a per-build flock via _swkit-resolve-one, so concurrent
# installer launches don't double-up on the same build — the loser exits
# silently without a network round-trip.
_spawn_date_workers() {
    command -v _swkit-resolve-one &>/dev/null || return 0
    [[ -f "${GITHASH_HELPERS:-}" ]] || return 0

    local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/swkit-githash/dates"
    local fname digits cache
    declare -A _seen=()

    for fname in "$@"; do
        [[ -z "$fname" ]] && continue
        digits=$(_swkit-githash-digits "$fname" 2>/dev/null) || continue
        # Dedup within this launch — many files may share Jenkins build digits.
        [[ -n "${_seen[$digits]:-}" ]] && continue
        _seen[$digits]=1
        cache="${cache_dir}/${digits}"
        [[ -s "$cache" ]] && continue

        # Fully-detached worker. setsid puts it in a new session so it
        # survives the installer exiting. flock -n inside the worker is the
        # gate against duplicates from concurrent launches.
        (
            setsid bash -c "source '${GITHASH_HELPERS}' >/dev/null 2>&1; _swkit-resolve-one '${digits}' >/dev/null 2>&1" \
                </dev/null >/dev/null 2>&1 &
        ) 2>/dev/null
    done
}

# Parse latest.txt from release channel; echo "version|filename" if valid
_read_latest_txt() {
    local cache_only=0
    [[ "${1:-}" == "--cache-only" ]] && { cache_only=1; shift; }
    local url="${ARTIFACTORY_HOST}/artifactory/${REPO}/${BASE_PATH}/release/${OS_KEY}/latest.txt"
    local key="latest_txt_${OS_KEY}"
    local content
    if (( cache_only )); then
        content=$(_curl_cache_only "$key" 2>/dev/null) || return 1
    else
        content=$(_curl_cached "$key" "$url" 2>/dev/null) || return 1
    fi
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
    local lib_arg="--no-nextsilicon-libs"
    echo "  swkit includes two compute libraries: nextfft and nextblas (C++ with C"
    echo "  and Fortran interfaces). If you are developing a custom build of either"
    echo "  library, skip this — swkit's copies may conflict with your local build."
    echo "  For all other users, installing the libraries is recommended."
    _prompt_yn "install_libs" "  Install NextSilicon libraries?" "n" && lib_arg=""

    local clear_opt=1
    echo ""
    echo "  Clearing removes existing swkit packages, DKMS modules, and /opt/nextsilicon"
    echo "  before the fresh install. Recommended when downgrading swkit (old files may"
    echo "  otherwise linger) or when switching from a with-libraries to a"
    echo "  without-libraries install. Safe to skip only on a first-time install."
    _prompt_yn "install_clear" "  Clear /opt/nextsilicon before install?" "y" || clear_opt=0

    local update_bashrc=0
    echo ""
    echo "  swkit always installs into /opt/nextsilicon. If you maintain a custom-built"
    echo "  nextutils stack, your NEXT_HOME may currently point to that location instead."
    echo "  Choosing Y updates your ~/.bashrc.USER to source swkit's environment and"
    echo "  exports NEXT_HOME immediately so the change takes effect in the current shell."
    echo "  Choose N to keep using your custom build."
    _prompt_yn "install_bashrc" "  Update ${BASHRC} to activate swkit?" "y" && update_bashrc=1
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
_prompt_yn() {
    local menu="$1" prompt_text="$2" hardcoded_default="$3"
    local default
    default=$(_get_menu_default "$menu" "$hardcoded_default")
    local ans
    if [[ "$default" == "y" ]]; then
        read -rp "${GREEN}${prompt_text} [${GREEN}Y${GREEN}/${RED}n${GREEN}]: ${NC}" ans
        ans="${ans:-y}"
    else
        read -rp "${GREEN}${prompt_text} [${RED}y${GREEN}/${GREEN}N${GREEN}]: ${NC}" ans
        ans="${ans:-n}"
    fi
    local norm
    norm=$(printf '%s' "$ans" | tr '[:upper:]' '[:lower:]')
    norm="${norm:0:1}"
    _log_menu_choice "$menu" "$norm"
    [[ "$ans" =~ ^[Yy]$ ]]
}

_find_index_of() {
    local value="$1"; shift
    local arr=("$@")
    local i
    for i in "${!arr[@]}"; do
        [[ "${arr[$i]}" == "$value" ]] && { echo "$((i + 1))"; return 0; }
    done
    return 1
}

_offer_clear() {
    if _prompt_yn "offer_clear" "  Clear existing swkit installation?" "n"; then
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
            echo "  Latest stable (latest.txt): release/${version}/$(_label_with_date "$filename")"
            if _prompt_yn "confirm_install" "Install?" "n"; then
                _install "release" "$version" "$filename"
            else
                _offer_clear
            fi
            return 0
        fi
        echo "  (latest.txt target not found — scanning release channel)"
    fi

    # Fallback: highest-heuristic stable-* (or any file) in latest release version
    version=$(_list_versions "release" | tail -1) \
        || { echo "  No versions found in release channel."; return 1; }
    [[ -z "$version" ]] && { echo "  No versions found in release channel."; return 1; }

    files=$(_list_files "release" "$version") \
        || { echo "  Could not list files in release/${version}."; return 1; }

    filename=$(echo "$files" | _best_file "stable")
    [[ -z "$filename" ]] && filename=$(echo "$files" | _best_file "")
    [[ -z "$filename" ]] && { echo "  No kit found in release/${version}."; return 1; }

    echo "  Found: release/${version}/$(_label_with_date "$filename")"
    if _prompt_yn "confirm_install" "Install?" "n"; then
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

    echo "  Found: rc/${ver}/$(_label_with_date "$filename")"
    if _prompt_yn "confirm_install" "Install?" "n"; then
        _install "rc" "$ver" "$filename"
    else
        _offer_clear
    fi
}

# ── Flow 3: install latest kit ─────────────────────────────────────────────────
# Picks the file with the highest build-number heuristic (first 3 digits of the
# trailing -NNNN suffix) in the latest rc version, regardless of quality
# prefix. Falls back to release if rc is empty.
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
    echo "  Found: ${channel}/${ver}/$(_label_with_date "$filename")"
    if _prompt_yn "confirm_install" "Install?" "n"; then
        _install "$channel" "$ver" "$filename"
    else
        _offer_clear
    fi
}

# ── Flow 3: list versions → pick version → list files → pick file → install ───
_flow_select() {
    # Step 1 — pick a version. Warm both channel listings in parallel; the
    # foreground calls below then hit the disk cache.
    echo "Fetching available versions..."
    (
        _list_versions release >/dev/null 2>&1 &
        _list_versions rc      >/dev/null 2>&1 &
        wait
    )

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

    # Build combined labels for history lookup
    local -a V_LABELS=()
    for i in "${!V_VERSIONS[@]}"; do
        V_LABELS+=("${V_CHANNELS[$i]}/${V_VERSIONS[$i]}")
    done

    local default_vsel="1"
    local prev_ver
    prev_ver=$(_get_menu_default "select_version" "")
    if [[ -n "$prev_ver" ]]; then
        local found_idx
        found_idx=$(_find_index_of "$prev_ver" "${V_LABELS[@]}") && default_vsel="$found_idx"
    fi

    echo ""
    printf "  %-4s  %-9s  %s\n"  "#"    "Channel"   "Version"
    printf "  %-4s  %-9s  %s\n"  "----" "---------" "-------"
    local i
    for i in "${!V_VERSIONS[@]}"; do
        local marker=""
        [[ "$((i+1))" == "$default_vsel" ]] && marker=" [default]"
        printf "  %-4s  %-9s  %s%s\n" "$((i+1))" "${V_CHANNELS[$i]}" "${V_VERSIONS[$i]}" "$marker"
    done
    echo ""

    local vsel
    read -rp "${GREEN}Select version (0 to cancel) [${default_vsel}]: ${NC}" vsel
    vsel="${vsel:-$default_vsel}"
    [[ "$vsel" == "0" ]] && { echo "Cancelled."; return 0; }
    if ! [[ "$vsel" =~ ^[0-9]+$ ]] || [[ "$vsel" -lt 1 ]] || [[ "$vsel" -gt "${#V_VERSIONS[@]}" ]]; then
        echo "Invalid selection."
        return 1
    fi

    local vidx=$(( vsel - 1 ))
    local sel_channel="${V_CHANNELS[$vidx]}"
    local sel_version="${V_VERSIONS[$vidx]}"
    _log_menu_choice "select_version" "${sel_channel}/${sel_version}"

    # Step 2 — pick a file
    echo ""
    echo "Fetching kits for ${sel_channel}/${sel_version}..."

    local files
    files=$(_list_files "$sel_channel" "$sel_version") \
        || { echo "Could not list files."; return 1; }
    [[ -z "$files" ]] && { echo "No kits found."; return 1; }

    # Classify, sort, and emit (quality, build, filename) lines in a single
    # awk → sort → cut pipeline. Avoids ~5 subshell forks per file that the
    # previous _quality / _build_num / _quality_rank loop incurred.
    local sorted_rows
    sorted_rows=$(echo "$files" | awk -F'\n' '
        function quality(fn) {
            if (fn ~ /^do-not-use-/) return "do-not-use"
            if (fn ~ /-remove\.sh$/)  return "remove"
            if (fn ~ /^stable-/)      return "stable"
            if (fn ~ /^verified-/)    return "verified"
            if (fn ~ /^ns-sw-kit-/)   return "latest"
            if (fn ~ /^untested-/)    return "untested"
            if (fn ~ /^unstable-/)    return "unstable"
            return "unknown"
        }
        function qrank(q) {
            if (q == "stable")   return 1
            if (q == "verified") return 2
            if (q == "latest")   return 3
            if (q == "untested") return 4
            if (q == "unstable") return 5
            return 9
        }
        {
            fn = $0
            if (fn == "") next
            n = fn; sub(/\.sh$/, "", n); sub(/.*-/, "", n)
            if (n !~ /^[0-9]+$/) n = 0
            q = quality(fn)
            printf "%d\t%08d\t%s\t%s\t%s\n", qrank(q), 99999999 - n, q, n, fn
        }
    ' | sort -t$'\t' -k1,1n -k2,2n | cut -f3-)

    # Pull each row into parallel arrays, decorating with cached date (read
    # directly from the dates cache without forking).
    local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/swkit-githash/dates"
    local -a F_FILES=() F_QUALITIES=() F_BUILDS=() F_DATES=()
    local q b fname digits cache_file d
    while IFS=$'\t' read -r q b fname; do
        [[ -z "$fname" ]] && continue
        F_FILES+=("$fname")
        F_QUALITIES+=("$q")
        F_BUILDS+=("$b")
        digits="$b"
        (( ${#digits} > 3 )) && digits="${digits:0:3}"
        cache_file="${cache_dir}/${digits}"
        if [[ -s "$cache_file" ]]; then
            d=$(<"$cache_file")
            F_DATES+=("${d%%T*}")
        else
            F_DATES+=("")
        fi
    done <<< "$sorted_rows"

    # Kick off background workers for any files whose dates aren't cached —
    # next launch will show them inline.
    _spawn_date_workers "${F_FILES[@]}"

    local default_fsel="1"
    local prev_kit
    prev_kit=$(_get_menu_default "select_kit" "")
    if [[ -n "$prev_kit" ]]; then
        local found_idx
        found_idx=$(_find_index_of "$prev_kit" "${F_FILES[@]}") && default_fsel="$found_idx"
    fi

    echo ""
    printf "  %-4s  %-10s  %-7s  %-12s  %s\n"  "#"    "Quality"    "Build"   "Date"         "File"
    printf "  %-4s  %-10s  %-7s  %-12s  %s\n"  "----" "----------" "-------" "------------" "----"
    for i in "${!F_FILES[@]}"; do
        local marker=""
        [[ "$((i+1))" == "$default_fsel" ]] && marker="  [default]"
        printf "  %-4s  %-10s  %-7s  %-12s  %s%s\n" \
            "$((i+1))" "${F_QUALITIES[$i]}" "${F_BUILDS[$i]}" "${F_DATES[$i]}" "${F_FILES[$i]}" "$marker"
    done
    echo ""

    local fsel
    read -rp "${GREEN}Select kit (0 to cancel) [${default_fsel}]: ${NC}" fsel
    fsel="${fsel:-$default_fsel}"
    [[ "$fsel" == "0" ]] && { echo "Cancelled."; return 0; }
    if ! [[ "$fsel" =~ ^[0-9]+$ ]] || [[ "$fsel" -lt 1 ]] || [[ "$fsel" -gt "${#F_FILES[@]}" ]]; then
        echo "Invalid selection."
        return 1
    fi

    local selected="${F_FILES[$(( fsel - 1 ))]}"
    _log_menu_choice "select_kit" "$selected"
    if _prompt_yn "confirm_install" "Install ${sel_channel}/${sel_version}/${selected}?" "n"; then
        _install "$sel_channel" "$sel_version" "$selected"
    else
        _offer_clear
    fi
}

# ── Flow 5: clear only ────────────────────────────────────────────────────────
_flow_clear() {
    if _prompt_yn "confirm_clear" "Clear existing swkit installation?" "n"; then
        _clear_swkit
    else
        echo "Cancelled."
    fi
}

# ── Main ───────────────────────────────────────────────────────────────────────
main() {
    # Detached refresh worker dispatch — fully off the user's critical path.
    if [[ "${1:-}" == "__refresh" ]]; then
        _run_refresh
        return 0
    fi

    # Spawn the detached refresher up front. It populates the listings cache
    # (and per-build date cache) for the *next* launch. We never block on it.
    _spawn_refresh

    echo "==========================================="
    echo "  NextSilicon swkit Installer"
    echo "  OS detected: ${OS_KEY}"
    echo "==========================================="
    echo ""

    # Resolve labels from cached listings when available, falling back to a
    # live fetch on a cold cache so the menu always shows filenames.
    local stable_label="" stable_rc_label="" latest_label=""
    local _ver _files _fname _info _ch

    # Option 1: latest stable.
    if _info=$(_read_latest_txt 2>/dev/null) && [[ -n "$_info" ]]; then
        _ver="${_info%%|*}"
        _fname="${_info##*|}"
        _files=$(_list_files "release" "$_ver" 2>/dev/null) || _files=""
        echo "$_files" | grep -qxF "$_fname" && stable_label="$_fname"
    fi
    if [[ -z "$stable_label" ]]; then
        _ver=$(_list_versions "release" 2>/dev/null | tail -1)
        if [[ -n "$_ver" ]]; then
            _files=$(_list_files "release" "$_ver" 2>/dev/null) || _files=""
            stable_label=$(echo "$_files" | _best_file "stable")
            [[ -z "$stable_label" ]] && stable_label=$(echo "$_files" | _best_file "")
        fi
    fi

    # Option 2: latest stable RC.
    _ver=$(_list_versions "rc" 2>/dev/null | tail -1)
    if [[ -n "$_ver" ]]; then
        _files=$(_list_files "rc" "$_ver" 2>/dev/null) || _files=""
        stable_rc_label=$(echo "$_files" | _best_file "stable")
    fi

    # Option 3: latest kit — rc first, fall back to release.
    for _ch in "rc" "release"; do
        _ver=$(_list_versions "$_ch" 2>/dev/null | tail -1)
        [[ -z "$_ver" ]] && continue
        _files=$(_list_files "$_ch" "$_ver" 2>/dev/null) || continue
        latest_label=$(echo "$_files" | _best_file "")
        [[ -n "$latest_label" ]] && break
    done

    # Compose labels with cached dates where available.
    local s1="last stable kit" s2="last stable RC" s3="last kit"
    [[ -n "$stable_label" ]]    && s1="last stable kit  ($(_label_with_date "$stable_label"))"
    [[ -n "$stable_rc_label" ]] && s2="last stable RC   ($(_label_with_date "$stable_rc_label"))"
    [[ -n "$latest_label" ]]    && s3="last kit         ($(_label_with_date "$latest_label"))"

    local default_choice
    default_choice=$(_get_menu_default "main" "1")
    local -a _d=("" "" "" "" "" "" "")
    _d[$((default_choice - 1))]="  [default]"

    echo "${GREEN}  1) Install ${s1}${_d[0]}${NC}"
    echo "${GREEN}  2) Install ${s2}${_d[1]}${NC}"
    echo "${GREEN}  3) Install ${s3}${_d[2]}${NC}"
    echo "${GREEN}  4) List available kits and select${_d[3]}${NC}"
    echo "${GREEN}  5) Clear swkit${_d[4]}${NC}"
    echo "${GREEN}  6) Clear all local data (cache + history)${_d[5]}${NC}"
    echo "${GREEN}  7) Exit${_d[6]}${NC}"
    echo ""

    local choice
    read -rp "${GREEN}Enter choice [${GREEN}${default_choice}${GREEN}]: ${NC}" choice
    choice="${choice:-$default_choice}"
    echo ""

    case "$choice" in
        1) _log_menu_choice "main" "1"; _flow_stable      ;;
        2) _log_menu_choice "main" "2"; _flow_stable_rc   ;;
        3) _log_menu_choice "main" "3"; _flow_latest      ;;
        4) _log_menu_choice "main" "4"; _flow_select      ;;
        5) _log_menu_choice "main" "5"; _flow_clear       ;;
        6) _clear_local_data                              ;;
        7) echo "Bye."                                    ;;
        *) echo "Invalid choice: '${choice}'"; exit 1    ;;
    esac
}

main "$@"
