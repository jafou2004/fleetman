#!/bin/bash

##
# Updates the fleet scripts from git and synchronizes to all servers.
# Finds the server holding the git clone, runs git pull/checkout there,
# runs any pending migrations, then syncs to the whole fleet.
#
# Usage: fleetman selfupdate [-h]
#
# Options:
#   -h, --help   Show this help
#
# config.json "selfupdate" block (all fields optional):
#   track: "tags"    → update to latest semver tag (default)
#          "commits" → pull any new commit on the current upstream branch
#          "branch"  → pull latest commit on a named branch
#   branch: "main"   → branch name used when track="branch" (default: "main")
#   pin:   "v1.2.3"  → stay at this specific version; overrides track
##

_LIB="$(dirname "${BASH_SOURCE[0]}")/../lib"
# shellcheck source=scripts/lib/vars.sh
source "$_LIB/vars.sh"
# shellcheck source=scripts/lib/display.sh
source "$_LIB/display.sh"
# shellcheck source=scripts/lib/auth.sh
source "$_LIB/auth.sh"
# shellcheck source=scripts/lib/config.sh
source "$_LIB/config.sh"

# ── local update helpers (Case 1 — git clone is on this server) ───────────────

# Moves to a pinned version, or skips if already on it.
# Returns: 0 = sync should run, 1 = already up to date or error
_update_pin() {
    local pdir="$1" pin="$2"
    local current_tag
    current_tag=$(git -C "$pdir" tag --points-at HEAD 2>/dev/null | grep -E '^v[0-9]' | head -1)
    if [[ "$current_tag" == "$pin" ]]; then
        ok "Already at pinned version $pin"
        return 1
    fi
    git -C "$pdir" fetch --tags --quiet
    if ! git -C "$pdir" tag -l | grep -qxF "$pin"; then
        err "Pinned version $pin not found in repository tags"
        return 1
    fi
    ok "Moving to pinned version $pin (current: ${current_tag:-none})"
    git -C "$pdir" checkout "$pin" --quiet
    return 0
}

# Checks for a newer semver tag; updates to it if found.
# Falls back to commit tracking if no tags exist.
# Returns: 0 = sync should run, 1 = already up to date
_update_tags() {
    local pdir="$1"
    local latest_tag current_tag new_commits
    git -C "$pdir" fetch --tags --quiet
    latest_tag=$(git -C "$pdir" tag -l 'v[0-9]*.[0-9]*.[0-9]*' | sort -V | tail -1)
    current_tag=$(git -C "$pdir" tag --points-at HEAD 2>/dev/null | grep -E '^v[0-9]' | head -1)
    if [[ -z "$latest_tag" ]]; then
        warn "No semver tags found — falling back to commit tracking"
        git -C "$pdir" fetch --quiet
        # shellcheck disable=SC1083  # @{u} is a git upstream refspec, not a bash brace
        new_commits=$(git -C "$pdir" rev-list HEAD..@{u} --count 2>/dev/null)
        if [[ "$new_commits" -eq 0 ]]; then
            ok "Already up to date (no tags, no new commits)"
            return 1
        fi
        git -C "$pdir" pull --quiet
        return 0
    fi
    if [[ "$latest_tag" == "$current_tag" ]]; then
        ok "Already up to date at $current_tag"
        return 1
    fi
    ok "New version available: $latest_tag (current: ${current_tag:-none})"
    git -C "$pdir" checkout "$latest_tag" --quiet
    return 0
}

# Checks for new commits on the upstream branch; pulls if found.
# If HEAD is detached (e.g. after a tag checkout), checks out <branch> first.
# Returns: 0 = sync should run, 1 = already up to date or error
_update_commits() {
    local pdir="$1" branch="$2"
    if ! git -C "$pdir" symbolic-ref --quiet HEAD &>/dev/null; then
        warn "Detached HEAD detected — checking out branch $branch"
        if ! git -C "$pdir" checkout "$branch" --quiet 2>/dev/null; then
            err "Could not check out branch $branch"
            return 1
        fi
    fi
    local new_commits
    git -C "$pdir" fetch --quiet
    # shellcheck disable=SC1083  # @{u} is a git upstream refspec, not a bash brace
    new_commits=$(git -C "$pdir" rev-list HEAD..@{u} --count 2>/dev/null)
    if [[ "$new_commits" -eq 0 ]]; then
        ok "Already up to date"
        return 1
    fi
    ok "Pulling $new_commits new commit(s)"
    git -C "$pdir" pull --quiet
    return 0
}

# Checks for new commits on a named branch; pulls if found.
# Returns: 0 = sync should run, 1 = already up to date or error
_update_branch() {
    local pdir="$1" branch="$2"
    local current_commit upstream_commit new_commits
    git -C "$pdir" fetch --quiet origin "$branch" 2>/dev/null
    if ! git -C "$pdir" rev-parse "origin/$branch" &>/dev/null; then
        err "Branch '$branch' not found on remote"
        return 1
    fi
    current_commit=$(git -C "$pdir" rev-parse HEAD 2>/dev/null)
    upstream_commit=$(git -C "$pdir" rev-parse "origin/$branch" 2>/dev/null)
    if [[ "$current_commit" == "$upstream_commit" ]]; then
        ok "Already up to date on branch $branch"
        return 1
    fi
    new_commits=$(git -C "$pdir" rev-list HEAD.."origin/$branch" --count 2>/dev/null)
    ok "Pulling $new_commits new commit(s) on branch $branch"
    git -C "$pdir" checkout "$branch" --quiet
    git -C "$pdir" pull --quiet
    return 0
}

# ── Case 1 helper ─────────────────────────────────────────────────────────────

# Performs the local git update (pin/tags/branch/commits), then runs migrations
# and triggers sync if an update was applied.
# Arguments: pdir track pin branch
# Returns: 0 always
_selfupdate_local() {
    local pdir="$1" track="$2" pin="$3" branch="$4"
    local _old_ver _should_sync=0

    _old_ver=$(cat "$pdir/scripts/internal/VERSION" 2>/dev/null || echo "0.0.0")

    if [[ -n "$pin" ]]; then
        _update_pin "$pdir" "$pin" && _should_sync=1
    elif [[ "$track" == "tags" ]]; then
        _update_tags "$pdir" && _should_sync=1
    elif [[ "$track" == "branch" ]]; then
        _update_branch "$pdir" "$branch" && _should_sync=1
    else
        _update_commits "$pdir" "$branch" && _should_sync=1
    fi

    if [[ "$_should_sync" -eq 0 ]]; then
        return 0
    fi

    local _new_ver
    _new_ver=$(cat "$pdir/scripts/internal/VERSION" 2>/dev/null || echo "0.0.0")
    echo ""
    bash "$SCRIPTS_DIR/internal/run_migrations.sh" "$_old_ver" "$_new_ver"

    section "Synchronization"
    echo ""
    bash "$SCRIPTS_DIR/bin/fleetman" sync --quick
}

# ── Case 2 helper ─────────────────────────────────────────────────────────────

# Scans all servers from config.json for one that holds the git clone.
# On success: prints the server FQDN, caches it to GIT_SERVER_FILE, returns 0.
# On failure: returns 1 with no output and no cache write.
_find_git_server() {
    local _s
    while IFS= read -r _s; do
        # shellcheck disable=SC2016
        if ssh_cmd "$_s" '[[ -d "${FLEETMAN_DIR:-$HOME/fleetman}/.git" ]]' 2>/dev/null; then
            ok "Git clone found on $(short_name "$_s")"
            echo "$_s" > "$GIT_SERVER_FILE"
            echo "$_s"
            return 0
        fi
    done < <(jq -r '.servers[] | .[]' "$CONFIG_FILE")
    return 1
}

# Parses the captured SSH output from a remote git update and acts on the result.
# Arguments: remote_out git_server
# Returns: 0 for UP_TO_DATE or UPDATED, 1 for FAILED or unknown
_parse_remote_result() {
    local remote_out="$1" git_server="$2"
    local _old_ver _new_ver _marker_line _detail

    _old_ver=$(echo "$remote_out" | grep '^OLD_VER:' | cut -d: -f2-)
    _new_ver=$(echo "$remote_out" | grep '^NEW_VER:' | cut -d: -f2-)
    _marker_line=$(echo "$remote_out" | grep -E '^(UP_TO_DATE|UPDATED|FAILED):' | head -1)
    _detail="${_marker_line#*:}"

    case "$_marker_line" in
        UP_TO_DATE:*)
            ok "Already up to date — $_detail"
            ;;
        UPDATED:*)
            ok "Updated — $_detail"
            echo ""
            # Phase B: migrations via ssh -t (interactive, full TTY)
            ssh_cmd -t "$git_server" \
                "bash \"\${FLEETMAN_DIR:-\$HOME/fleetman}/scripts/internal/run_migrations.sh\" '$_old_ver' '$_new_ver'"
            # Phase C: sync triggered from the git server (source of truth)
            echo ""
            section "Synchronization"
            echo ""
            ssh_cmd "$git_server" \
                "bash \"\${FLEETMAN_DIR:-\$HOME/fleetman}/scripts/bin/fleetman\" sync --quick"
            ;;
        FAILED:*)
            err "Update failed — $_detail"
            return 1
            ;;
        *)
            err "selfupdate on $(short_name "$git_server") failed or produced no status"
            return 1
            ;;
    esac
}

# ── entry point ───────────────────────────────────────────────────────────────

cmd_selfupdate() {
    while getopts ":" _opt "$@"; do
        case "$_opt" in
            \?) err "Unknown option: -$OPTARG"; exit 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    check_sshpass
    check_config_file
    ask_password

    local _pdir="${FLEETMAN_DIR:-$HOME/fleetman}"
    local _track _pin _branch
    _track=$(jq -r '.selfupdate.track // "tags"' "$CONFIG_FILE")
    _pin=$(jq -r '.selfupdate.pin // ""' "$CONFIG_FILE")
    _branch=$(jq -r '.selfupdate.branch // "main"' "$CONFIG_FILE")

    if [[ "$_track" != "tags" && "$_track" != "commits" && "$_track" != "branch" ]]; then
        err "config.json: selfupdate.track must be \"tags\", \"commits\", or \"branch\" (got \"$_track\")"
        unset PASSWORD
        exit 1
    fi

    section "Self-update"
    echo ""

    # ── Case 1: git clone is on this server ───────────────────────────────────
    if [[ -d "$_pdir/.git" ]]; then
        ok "Git clone found locally on this server"
        echo ""
        _selfupdate_local "$_pdir" "$_track" "$_pin" "$_branch"
        unset PASSWORD
        return
    fi

    # ── Case 2: find git clone server (cache or fleet scan) ───────────────────
    section "Searching for the git clone"
    echo ""

    local _git_server=""

    if [[ -s "$GIT_SERVER_FILE" ]]; then
        local _cached
        _cached=$(< "$GIT_SERVER_FILE")
        # shellcheck disable=SC2016
        if ssh_cmd "$_cached" '[[ -d "${FLEETMAN_DIR:-$HOME/fleetman}/.git" ]]' 2>/dev/null; then
            _git_server="$_cached"
            ok "Git clone server (cached): $(short_name "$_git_server")"
            echo ""
        else
            warn "Cached server $(short_name "$_cached") unreachable or git clone missing — scanning fleet..."
            echo ""
        fi
    else
        warn "Git clone server not cached — scanning fleet..."
        echo ""
    fi

    if [[ -z "$_git_server" ]]; then
        _git_server=$(_find_git_server)
        if [[ -z "$_git_server" ]]; then
            err "No server with git clone found in fleet"
            unset PASSWORD
            exit 1
        fi
        echo ""
    fi

    section "Update from $(short_name "$_git_server")"
    echo ""

    # Phase A: git update (no TTY needed) — capture versions and marker
    local _remote_out
    _remote_out=$(ssh_cmd "$_git_server" bash -s << ENDSSH
set -e
_pdir="\${FLEETMAN_DIR:-\$HOME/fleetman}"
_track="$_track"
_pin="$_pin"
_branch="$_branch"
_old_ver=\$(cat "\$_pdir/scripts/internal/VERSION" 2>/dev/null || echo "0.0.0")

_fetch_pin() {
    local _current
    _current=\$(git -C "\$_pdir" tag --points-at HEAD 2>/dev/null | grep -E '^v[0-9]' | head -1)
    if [[ "\$_current" == "\$_pin" ]]; then echo "UP_TO_DATE:\$_pin"; return; fi
    git -C "\$_pdir" fetch --tags --quiet
    if ! git -C "\$_pdir" tag -l | grep -qxF "\$_pin"; then
        echo "FAILED:tag \$_pin not found"; return
    fi
    git -C "\$_pdir" checkout "\$_pin" --quiet
    echo "UPDATED:\$_pin"
}

_fetch_tags() {
    git -C "\$_pdir" fetch --tags --quiet
    local _latest _current _nc
    _latest=\$(git -C "\$_pdir" tag -l 'v[0-9]*.[0-9]*.[0-9]*' | sort -V | tail -1)
    _current=\$(git -C "\$_pdir" tag --points-at HEAD 2>/dev/null | grep -E '^v[0-9]' | head -1)
    if [[ -z "\$_latest" ]]; then
        git -C "\$_pdir" fetch --quiet
        _nc=\$(git -C "\$_pdir" rev-list HEAD..@{u} --count 2>/dev/null)
        if [[ "\$_nc" -eq 0 ]]; then echo "UP_TO_DATE:no tags, no new commits"; return; fi
        git -C "\$_pdir" pull --quiet
        echo "UPDATED:\$_nc commit(s) (no tags)"
        return
    fi
    if [[ "\$_latest" == "\$_current" ]]; then echo "UP_TO_DATE:\$_latest"; return; fi
    git -C "\$_pdir" checkout "\$_latest" --quiet
    echo "UPDATED:\$_latest"
}

_fetch_commits() {
    if ! git -C "\$_pdir" symbolic-ref --quiet HEAD &>/dev/null; then
        if ! git -C "\$_pdir" checkout "\$_branch" --quiet 2>/dev/null; then
            echo "FAILED:detached HEAD and could not check out branch \$_branch"; return
        fi
    fi
    git -C "\$_pdir" fetch --quiet
    local _nc
    _nc=\$(git -C "\$_pdir" rev-list HEAD..@{u} --count 2>/dev/null)
    if [[ "\$_nc" -eq 0 ]]; then echo "UP_TO_DATE:0 new commits"; return; fi
    git -C "\$_pdir" pull --quiet
    echo "UPDATED:\$_nc commit(s)"
}

_fetch_branch() {
    git -C "\$_pdir" fetch --quiet origin "\$_branch" 2>/dev/null
    if ! git -C "\$_pdir" rev-parse "origin/\$_branch" &>/dev/null; then
        echo "FAILED:branch \$_branch not found on remote"; return
    fi
    local _cur _up _nc
    _cur=\$(git -C "\$_pdir" rev-parse HEAD 2>/dev/null)
    _up=\$(git -C "\$_pdir" rev-parse "origin/\$_branch" 2>/dev/null)
    if [[ "\$_cur" == "\$_up" ]]; then echo "UP_TO_DATE:branch \$_branch"; return; fi
    _nc=\$(git -C "\$_pdir" rev-list HEAD.."origin/\$_branch" --count 2>/dev/null)
    git -C "\$_pdir" checkout "\$_branch" --quiet
    git -C "\$_pdir" pull --quiet
    echo "UPDATED:\$_nc commit(s) on branch \$_branch"
}

if [[ -n "\$_pin" ]]; then
    _marker=\$(_fetch_pin)
elif [[ "\$_track" == "tags" ]]; then
    _marker=\$(_fetch_tags)
elif [[ "\$_track" == "branch" ]]; then
    _marker=\$(_fetch_branch)
else
    _marker=\$(_fetch_commits)
fi

_new_ver=\$(cat "\$_pdir/scripts/internal/VERSION" 2>/dev/null || echo "0.0.0")
echo "OLD_VER:\$_old_ver"
echo "NEW_VER:\$_new_ver"
echo "\$_marker"
ENDSSH
)

    _parse_remote_result "$_remote_out" "$_git_server"
    unset PASSWORD
}
