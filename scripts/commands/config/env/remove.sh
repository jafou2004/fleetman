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

_get_git_server() {
    if [[ -f "$GIT_SERVER_FILE" ]]; then
        cat "$GIT_SERVER_FILE"
    fi
}

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

_delete_ascii() {
    local fqdn="$1"
    local ascii_file
    ascii_file="$DATA_DIR/welcome_$(short_name "$fqdn").ascii"
    if [[ -f "$ascii_file" ]]; then
        rm -f "$ascii_file"
        ok "ASCII art deleted — $ascii_file"
    fi
}

# ── Main ───────────────────────────────────────────────────────────────────────

cmd_config_env_remove() {
    local OPTIND=1 _env_flag=""
    while getopts ":e:h" _opt "$@"; do
        case "$_opt" in
            e) _env_flag="$OPTARG" ;;
            h) grep -A999 '^# Usage' "${BASH_SOURCE[0]}" | grep -m1 -A999 '^##$' | head -n-1 | sed 's/^# //' | sed 's/^#$//' | sed 's/^##//'; exit 0 ;;
            \?) err "Unknown option: -$OPTARG"; exit 1 ;;
            :)  err "Option -$OPTARG requires an argument."; exit 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    check_config_file

    section "Configuration — remove environment"

    # ── Env selection ──────────────────────────────────────────────────
    local selected_env
    if [[ -n "$_env_flag" ]]; then
        if ! jq -e --arg e "$_env_flag" '.servers | has($e)' "$CONFIG_FILE" > /dev/null 2>&1; then
            local _valid
            _valid=$(jq -r '[.servers | keys[]] | join(", ")' "$CONFIG_FILE")
            err "Invalid environment '$_env_flag'. Valid: $_valid"
            exit 1
        fi
        selected_env="$_env_flag"
    else
        local -a _env_names=()
        mapfile -t _env_names < <(jq -r '.servers | keys[]' "$CONFIG_FILE")
        local -a _env_labels=()
        local _e _color _bg
        for _e in "${_env_names[@]}"; do
            _color=$(jq -r --arg e "$_e" '.env_colors[$e] // "white"' "$CONFIG_FILE")
            _bg=$(env_color_ansi "$_color" bg)
            _env_labels+=("$(printf "${_bg}%s${NC}" "$_e")")
        done
        printf "Select the environment to remove:\n"
        select_menu _env_labels
        selected_env="${_env_names[$SELECTED_IDX]}"
    fi

    # ── Git clone protection ───────────────────────────────────────────
    local _git_server _gs_short
    _git_server=$(_get_git_server)
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

    local _fleetman="$SCRIPTS_DIR/bin/fleetman"

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
        _delete_ascii "$_s"
    done
    echo ""

    # ── Update config ──────────────────────────────────────────────────
    section "Updating config"
    _remove_env_from_config "$selected_env"
    echo ""

    # ── Sync + optional local uninstall ───────────────────────────────
    if [[ -n "$_local_server" ]]; then
        if [[ -f "$_fleetman" ]]; then
            section "Synchronisation"
            bash "$_fleetman" sync -q
            echo ""
        fi
        section "Uninstall local — $(short_name "$_local_server")"
        uninstall_local
        echo ""
        warn "This server is no longer in the fleet"
    else
        if [[ -f "$_fleetman" ]]; then
            section "Synchronisation"
            bash "$_fleetman" sync -q
        else
            warn "fleetman not found — run 'fleetman sync' manually"
        fi
    fi

    unset PASSWORD
}
