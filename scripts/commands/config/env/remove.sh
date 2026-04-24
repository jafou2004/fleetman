#!/bin/bash

##
# @menu Remove environment
# @order 3
#
# Removes an environment from the fleet: uninstalls fleetman on all its
# servers, updates config.json, deletes ASCII art files, then runs a quick sync.
#
# Usage: fleetman config env remove [-e <env>] [-h]
#
# Options:
#   -e <env>     Target environment (skips interactive env menu)
#   -h, --help   Show this help
##

_LIB="$(dirname "${BASH_SOURCE[0]}")/../../../lib"
# shellcheck source=scripts/lib/vars.sh
source "$_LIB/vars.sh"
# shellcheck source=scripts/lib/display.sh
source "$_LIB/display.sh"
# shellcheck source=scripts/lib/config.sh
source "$_LIB/config.sh"
# shellcheck source=scripts/lib/ui.sh
source "$_LIB/ui.sh"
# shellcheck source=scripts/lib/auth.sh
source "$_LIB/auth.sh"
# shellcheck source=scripts/lib/uninstall.sh
source "$_LIB/uninstall.sh"

# ── Helpers ────────────────────────────────────────────────────────────────────

_remove_env_from_config() {
    local env="$1"
    local tmp
    tmp=$(mktemp)
    if ! jq --arg e "$env" \
        'del(.servers[$e]) | del(.env_colors[$e])' \
        "$CONFIG_FILE" > "$tmp" || ! mv "$tmp" "$CONFIG_FILE"; then
        rm -f "$tmp"
        err "Failed to write config"
        return 1
    fi
    ok "Environment '$env' removed from config.json"
}

# ── Main ───────────────────────────────────────────────────────────────────────

cmd_config_env_remove() {
    local OPTIND=1 _env_flag=""
    while getopts ":e:" _opt "$@"; do
        case "$_opt" in
            e) _env_flag="$OPTARG" ;;
            \?) err "Unknown option: -$OPTARG"; exit 1 ;;
            :)  err "Option -$OPTARG requires an argument."; exit 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    check_config_file

    section "Configuration — remove environment"

    # ── Env selection ──────────────────────────────────────────────────
    local selected_env
    select_env_colored "Select the environment to remove:" "$_env_flag"
    selected_env="$SELECTED_ENV"

    # ── Git clone protection ───────────────────────────────────────────
    local _git_server _gs_short
    _git_server=$(get_git_server)
    if [[ -n "$_git_server" ]]; then
        _gs_short=$(short_name "$_git_server")
        local _s
        while IFS= read -r _s; do
            if [[ "$(short_name "$_s")" == "$_gs_short" ]]; then
                err "Cannot remove '$selected_env': contains git clone server '$_gs_short'"
                exit 1
            fi
        done < <(jq -r --arg e "$selected_env" '.servers[$e][]' "$CONFIG_FILE" 2>/dev/null)
    fi

    # ── Server list ────────────────────────────────────────────────────
    local -a _servers=()
    mapfile -t _servers < <(jq -r --arg e "$selected_env" '.servers[$e][]' "$CONFIG_FILE" 2>/dev/null)

    if [[ ${#_servers[@]} -eq 0 ]]; then
        warn "No servers in environment '$selected_env'"
        exit 0
    fi

    # ── Confirmation ───────────────────────────────────────────────────
    if ! prompt_confirm "Remove environment '$selected_env' and uninstall ${#_servers[@]} server(s)?" N; then
        warn "Aborted"
        exit 0
    fi
    echo ""

    check_sshpass
    ask_password

    # ── Detect local server ────────────────────────────────────────────
    local _local_server="" _s
    for _s in "${_servers[@]}"; do
        if is_local_server "$_s"; then
            _local_server="$_s"
            break
        fi
    done

    # ── Uninstall remote servers ───────────────────────────────────────
    section "Uninstall — $selected_env"
    for _s in "${_servers[@]}"; do
        if [[ "$_s" != "$_local_server" ]]; then
            uninstall_remote "$_s"
            echo ""
        fi
    done

    # ── Delete ASCII art files ─────────────────────────────────────────
    for _s in "${_servers[@]}"; do
        delete_ascii "$_s"
    done
    echo ""

    # ── Update config ──────────────────────────────────────────────────
    section "Updating config"
    _remove_env_from_config "$selected_env"
    echo ""

    # ── Sync + optional local uninstall ───────────────────────────────
    if [[ -n "$_local_server" ]]; then
        run_sync_or_warn
        echo ""
        section "Uninstall local — $(short_name "$_local_server")"
        uninstall_local
        echo ""
        warn "This server is no longer in the fleet"
    else
        run_sync_or_warn
    fi

    unset PASSWORD
}
