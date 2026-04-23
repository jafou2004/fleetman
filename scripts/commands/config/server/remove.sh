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

# ── Helpers ────────────────────────────────────────────────────────────────────

_get_git_server() {
    if [[ -f "$GIT_SERVER_FILE" ]]; then
        cat "$GIT_SERVER_FILE"
    fi
}

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

_delete_ascii() {
    local fqdn="$1"
    local ascii_file
    ascii_file="$DATA_DIR/welcome_$(short_name "$fqdn").ascii"
    if [[ -f "$ascii_file" ]]; then
        rm -f "$ascii_file"
        ok "ASCII art deleted — $ascii_file"
    fi
}

_uninstall_remote_server() {
    local server="$1"
    local result _ssh_rc

    result=$(ssh_cmd "$server" bash -s << 'ENDSSH' 2>/dev/null
sed -i '/# BEGIN FLEETMAN/,/# END FLEETMAN/d' ~/.bashrc 2>/dev/null || true
echo "BASHRC_DONE"
crontab -l 2>/dev/null | grep -vF "bin/fleetman" | crontab - 2>/dev/null
echo "CRON_DONE"
rm -f ~/.fleet_pass.enc ~/.ssh/fleet_key ~/.ssh/fleet_key.pub ~/config.json ~/.bash_aliases
echo "FILES_DONE"
rm -rf ~/.data
echo "DATA_DONE"
rm -rf ~/scripts
echo "SCRIPTS_DONE"
ENDSSH
    )
    _ssh_rc=$?

    if [[ "$_ssh_rc" -ne 0 ]] || ! echo "$result" | grep -q "^SCRIPTS_DONE$"; then
        err "Uninstall failed on $server"
        return 1
    fi
    ok "Fleetman uninstalled from $server"
}

_uninstall_local_server() {
    sed -i '/# BEGIN FLEETMAN/,/# END FLEETMAN/d' "$HOME/.bashrc" 2>/dev/null || true
    ok ".bashrc blocks removed"
    if crontab -l 2>/dev/null | grep -qF "bin/fleetman"; then
        crontab -l 2>/dev/null | grep -vF "bin/fleetman" | crontab -
        ok "fleetman cron entries removed"
    fi
    rm -f ~/.fleet_pass.enc ~/.ssh/fleet_key ~/.ssh/fleet_key.pub ~/config.json ~/.bash_aliases
    rm -rf ~/.data ~/scripts
    ok "Fleetman uninstalled from local server"
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
        printf "Select the target environment:\n"
        select_menu _env_labels
        selected_env="${_env_names[$SELECTED_IDX]}"
    fi

    # ── Server list for env ────────────────────────────────────────────
    local -a _servers=()
    mapfile -t _servers < <(jq -r --arg e "$selected_env" '.servers[$e][]' "$CONFIG_FILE" 2>/dev/null)

    if [[ ${#_servers[@]} -eq 0 ]]; then
        warn "No servers in environment '$selected_env'"
        exit 0
    fi

    local _git_server
    _git_server=$(_get_git_server)

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
    local _fleetman="$SCRIPTS_DIR/bin/fleetman"

    if is_local_server "$_target"; then
        warn "Fleetman will be uninstalled from this server after sync"
        echo ""
        section "Updating config"
        _remove_from_config "$selected_env" "$_target"
        _delete_ascii "$_target"
        echo ""
        if [[ -f "$_fleetman" ]]; then
            section "Synchronisation"
            bash "$_fleetman" sync -q
            echo ""
        fi
        section "Uninstall local — $(short_name "$_target")"
        _uninstall_local_server
        echo ""
        warn "This server is no longer in the fleet"
    else
        check_sshpass
        ask_password
        section "Uninstall — $(short_name "$_target")"
        _uninstall_remote_server "$_target"
        echo ""
        section "Updating config"
        _remove_from_config "$selected_env" "$_target"
        _delete_ascii "$_target"
        echo ""
        if [[ -f "$_fleetman" ]]; then
            section "Synchronisation"
            bash "$_fleetman" sync -q
        else
            warn "fleetman not found — run 'fleetman sync' manually"
        fi
    fi

    unset PASSWORD
}
