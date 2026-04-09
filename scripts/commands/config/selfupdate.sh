#!/bin/bash

##
# @menu Selfupdate
# @order 10
#
# Configures automatic update behaviour (track, branch, pin).
#
# Usage: fleetman config selfupdate
#
# Options:
#   -h, --help   Show this help
##

_LIB="$(dirname "${BASH_SOURCE[0]}")/../../lib"
# shellcheck source=scripts/lib/vars.sh
source "$_LIB/vars.sh"
# shellcheck source=scripts/lib/display.sh
source "$_LIB/display.sh"
# shellcheck source=scripts/lib/config.sh
source "$_LIB/config.sh"
# shellcheck source=scripts/lib/ui.sh
source "$_LIB/ui.sh"

# Fetches branch names from a remote git repo.
# Usage: _su_fetch_branches <repo_url>
# Stdout: one branch name per line (no refs/heads/ prefix)
# Returns: 1 if git ls-remote fails
_su_fetch_branches() {
    local repo_url="$1"
    local output
    output=$(git ls-remote --heads "$repo_url" 2>/dev/null) || return 1
    printf '%s\n' "$output" | awk '{print $2}' | sed 's|refs/heads/||'
}

# Fetches semver tags from a remote git repo, sorted descending, max 20.
# Usage: _su_fetch_tags <repo_url>
# Stdout: one tag name per line (no refs/tags/ prefix, no ^{})
# Returns: 1 if git ls-remote fails
_su_fetch_tags() {
    local repo_url="$1"
    local output
    output=$(git ls-remote --tags "$repo_url" 2>/dev/null) || return 1
    printf '%s\n' "$output" \
        | awk '{print $2}' \
        | grep -E '^refs/tags/v[0-9]' \
        | grep -vF '^{}' \
        | sed 's|refs/tags/||' \
        | sort -V -r \
        | head -20
}

cmd_config_selfupdate() {
    local OPTIND=1
    while getopts ":" _opt "$@"; do
        case "$_opt" in
            \?) err "Unknown option: -$OPTARG"; exit 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    check_config_file

    local _track _branch _pin _repo
    _track=$(jq -r '.selfupdate.track // "tags"' "$CONFIG_FILE")
    _branch=$(jq -r '.selfupdate.branch // "main"' "$CONFIG_FILE")
    _pin=$(jq -r '.selfupdate.pin // ""' "$CONFIG_FILE")
    _repo=$(jq -r '.repo_url // ""' "$CONFIG_FILE")

    section "Configuration — selfupdate"
    printf "  track  : %s\n" "$_track"
    printf "  branch : %s\n" "$_branch"
    printf "  pin    : %s\n" "${_pin:-(none)}"
    printf "  repo   : %s\n" "${_repo:-(not set)}"
    echo ""

    # ── Step 1: choose tracking mode ──────────────────────────────────
    local -a _track_labels=("Tags (latest semver)" "Commits (upstream branch)" "Branch (named branch)")
    local -a _track_values=("tags" "commits" "branch")

    # Preselect current index
    local _track_idx=0
    local _i
    for _i in "${!_track_values[@]}"; do
        [[ "${_track_values[$_i]}" == "$_track" ]] && _track_idx=$_i
    done
    select_menu _track_labels "$_track_idx"
    local _new_track="${_track_values[$SELECTED_IDX]}"

    # ── Step 2: choose branch (if track=branch) ─────────────────────────
    local _new_branch="$_branch"
    if [[ "$_new_track" == "branch" ]]; then
        local -a _branches=()
        if [[ -n "$_repo" ]]; then
            mapfile -t _branches < <(_su_fetch_branches "$_repo" 2>/dev/null) || true
        fi
        if [[ "${#_branches[@]}" -gt 0 ]]; then
            select_menu _branches
            _new_branch="${_branches[$SELECTED_IDX]}"
        else
            if [[ -z "$_repo" ]]; then
                warn "repo_url missing from config.json — manual input"
            else
                warn "Cannot reach repository — manual input"
            fi
            _new_branch=$(prompt_response "Branch name" "$_branch")
        fi
    fi

    # ── Step 3: pin a version (optional) ─────────────────────────────
    local _new_pin=""
    local -a _tags=()
    if [[ -n "$_repo" ]]; then
        mapfile -t _tags < <(_su_fetch_tags "$_repo" 2>/dev/null) || true
    fi
    if [[ "${#_tags[@]}" -gt 0 ]]; then
        local -a _pin_labels=("(no pin)" "${_tags[@]}")
        select_menu _pin_labels
        if [[ "$SELECTED_IDX" -eq 0 ]]; then
            _new_pin=""
        else
            _new_pin="${_tags[$((SELECTED_IDX - 1))]}"
        fi
    else
        _new_pin=$(prompt_response "Pin version (laisser vide = aucun)" "$_pin")
    fi

    # ── Unchanged check ───────────────────────────────────────────────────────
    if [[ "$_new_track" == "$_track" && "$_new_branch" == "$_branch" && "$_new_pin" == "$_pin" ]]; then
        ok "Unchanged"
        return 0
    fi

    # ── Atomic write ──────────────────────────────────────────────────────────
    local _tmp
    _tmp=$(mktemp)
    if ! jq --arg t "$_new_track" --arg b "$_new_branch" --arg p "$_new_pin" \
            '.selfupdate.track = $t | .selfupdate.branch = $b | .selfupdate.pin = $p' \
            "$CONFIG_FILE" > "$_tmp" || ! mv "$_tmp" "$CONFIG_FILE"; then
        rm -f "$_tmp"
        err "Failed to write config"
        exit 1
    fi

    ok "selfupdate: track=$_new_track branch=$_new_branch pin=${_new_pin:-(none)}"
    prompt_sync_confirm
}
