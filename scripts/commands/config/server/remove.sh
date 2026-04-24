#!/bin/bash

##
# @menu Remove server
# @order 2
#
# Removes a server from the fleet: uninstalls fleetman, updates config.json,
# deletes its ASCII art file, then runs a quick sync.
#
# Usage: fleetman config server remove [-e <env>] [-h]
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

_remove_from_config() {
    local env="$1" fqdn="$2"
    local tmp
    tmp=$(mktemp)
    if ! jq --arg e "$env" --arg s "$fqdn" \
        '.servers[$e] = [.servers[$e][] | select(. != $s)]' \
        "$CONFIG_FILE" > "$tmp" || ! mv "$tmp" "$CONFIG_FILE"; then
        rm -f "$tmp"
        err "Failed to write config"
        return 1
    fi
    ok "Server '$fqdn' removed from config.json"
}

# ── Main ───────────────────────────────────────────────────────────────────────

cmd_config_server_remove() {
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

    section "Configuration — remove server"

    # ── Env selection ──────────────────────────────────────────────────
    local selected_env
    select_env_colored "Select the target environment:" "$_env_flag"
    selected_env="$SELECTED_ENV"

    # ── Server list for env ────────────────────────────────────────────
    local -a _servers=()
    mapfile -t _servers < <(jq -r --arg e "$selected_env" '.servers[$e][]' "$CONFIG_FILE" 2>/dev/null)

    if [[ ${#_servers[@]} -eq 0 ]]; then
        warn "No servers in environment '$selected_env'"
        exit 0
    fi

    local _git_server
    _git_server=$(get_git_server)

    local -a _labels=() _disabled=()
    local _i _fqdn _short _color _bg
    for _i in "${!_servers[@]}"; do
        _fqdn="${_servers[$_i]}"
        _short=$(short_name "$_fqdn")
        _color=$(jq -r --arg e "$selected_env" '.env_colors[$e] // "white"' "$CONFIG_FILE")
        _bg=$(env_color_ansi "$_color" bg)
        if [[ -n "$_git_server" ]] && \
           [[ "$(short_name "$_fqdn")" == "$(short_name "$_git_server")" ]]; then
            _labels+=("$(printf "%s ${_bg}[%s]${NC}  (git clone)" "$_short" "${selected_env^^}")")
            _disabled+=("$_i")
        else
            _labels+=("$(printf "%s ${_bg}[%s]${NC}" "$_short" "${selected_env^^}")")
        fi
    done

    if [[ ${#_disabled[@]} -ge ${#_servers[@]} ]]; then
        warn "No removable server in '$selected_env' — git clone server is protected"
        exit 0
    fi

    printf "\nSelect the server to remove:\n"
    select_menu_disabled _labels _disabled
    local _target="${_servers[$SELECTED_IDX]}"
    echo ""

    # ── Confirmation ───────────────────────────────────────────────────
    if ! prompt_confirm "Remove '$(short_name "$_target")' from '$selected_env'?" N; then
        warn "Aborted"
        exit 0
    fi
    echo ""

    # ── Execute ────────────────────────────────────────────────────────
    if is_local_server "$_target"; then
        warn "Fleetman will be uninstalled from this server after sync"
        echo ""
        section "Updating config"
        _remove_from_config "$selected_env" "$_target"
        delete_ascii "$_target"
        echo ""
        run_sync_or_warn
        echo ""
        section "Uninstall local — $(short_name "$_target")"
        uninstall_local
        echo ""
        warn "This server is no longer in the fleet"
    else
        check_sshpass
        ask_password
        section "Uninstall — $(short_name "$_target")"
        uninstall_remote "$_target"
        echo ""
        section "Updating config"
        _remove_from_config "$selected_env" "$_target"
        delete_ascii "$_target"
        echo ""
        run_sync_or_warn
    fi

    unset PASSWORD
}
