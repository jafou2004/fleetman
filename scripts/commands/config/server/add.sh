#!/bin/bash

##
# @menu Add server
# @order 1
#
# Adds one or more new servers to config.json (.servers).
#
# Usage: fleetman config server add
#
# Options:
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

_list_servers() {
    local env color bg
    while IFS= read -r env; do
        color=$(jq -r --arg e "$env" '.env_colors[$e] // "white"' "$CONFIG_FILE" 2>/dev/null)
        bg=$(env_color_ansi "$color" bg)
        printf "  ${bg}%s${NC}\n" "$env"
        jq -r --arg e "$env" '.servers[$e][]' "$CONFIG_FILE" 2>/dev/null | while IFS= read -r s; do
            printf "    %s\n" "$s"
        done
    done < <(jq -r '.servers | keys[]' "$CONFIG_FILE" 2>/dev/null)
}

_is_valid_fqdn() {
    local fqdn="$1"
    [[ "$fqdn" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$ ]]
}

_is_server_registered() {
    local fqdn="$1"
    jq -e --arg s "$fqdn" '[.servers[] | .[]] | any(. == $s)' "$CONFIG_FILE" > /dev/null 2>&1
}

_deploy_key() {
    local fqdn="$1"

    if [[ ! -f "$FLEET_KEY" ]] || [[ ! -f "$FLEET_PASS_FILE" ]]; then
        err "No fleet credentials found — run install.sh first"
        exit 1
    fi

    local raw_password
    raw_password=$(openssl pkeyutl -decrypt -inkey "$FLEET_KEY" \
        -pkeyopt rsa_padding_mode:oaep -in "$FLEET_PASS_FILE" 2>/dev/null)
    if [[ -z "$raw_password" ]]; then
        err "Could not decrypt fleet password — run install.sh first"
        exit 1
    fi

    if ! sshpass -p "$raw_password" ssh-copy-id \
            -i "$FLEET_KEY.pub" \
            -o StrictHostKeyChecking=no \
            "$fqdn" > /dev/null 2>&1; then
        err "Failed to deploy public key to $fqdn"
        unset raw_password
        return 1
    fi
    ok "Public key deployed to $fqdn"

    if ! ssh -i "$FLEET_KEY" -o StrictHostKeyChecking=no -o BatchMode=yes \
            "$fqdn" true > /dev/null 2>&1; then
        err "Key authentication test failed for $fqdn"
        unset raw_password
        return 1
    fi
    ok "Key authentication verified"

    unset raw_password
}

cmd_config_server_add() {
    local OPTIND=1
    while getopts ":" _opt "$@"; do
        case "$_opt" in
            \?) err "Unknown option: -$OPTARG"; exit 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    check_config_file

    section "Configuration — add server"

    printf "List of current servers:\n"
    _list_servers
    echo ""

    # ── Menu: environment selection ──────────────────────────────────
    local -a env_names=()
    mapfile -t env_names < <(jq -r '.servers | keys[]' "$CONFIG_FILE")

    local -a env_labels=()
    local e color bg
    for e in "${env_names[@]}"; do
        color=$(jq -r --arg e "$e" '.env_colors[$e] // "white"' "$CONFIG_FILE")
        bg=$(env_color_ansi "$color" bg)
        env_labels+=("$(printf "${bg}%s${NC}" "$e")")
    done

    printf "Select the target environment:\n"
    select_menu env_labels
    local selected_env="${env_names[$SELECTED_IDX]}"

    # ── FQDN collection loop ──────────────────────────────────────────
    local -a added_servers=()
    local new_server
    while true; do
        printf "FQDN of the new server (empty to finish) ? " >&2
        read -r new_server
        [[ -z "$new_server" ]] && break
        new_server="${new_server,,}"

        if ! _is_valid_fqdn "$new_server"; then
            warn "Invalid format — expected: server.domain.tld (e.g. prod4.abc.example.com)"
            continue
        fi

        if _is_server_registered "$new_server"; then
            warn "Server '$new_server' is already registered"
            continue
        fi

        local tmp
        tmp=$(mktemp)
        if ! jq --arg e "$selected_env" --arg s "$new_server" \
            '.servers[$e] += [$s]' \
            "$CONFIG_FILE" > "$tmp" || ! mv "$tmp" "$CONFIG_FILE"; then
            rm -f "$tmp"
            err "Failed to write config"
            exit 1
        fi

        ok "Server '$new_server' added to environment '$selected_env'"
        added_servers+=("$new_server")
    done

    if [[ ${#added_servers[@]} -eq 0 ]]; then
        warn "No server added"
        exit 0
    fi

    # ── Deploy keys (one per server) ──────────────────────────────────
    local fqdn
    for fqdn in "${added_servers[@]}"; do
        _deploy_key "$fqdn"
    done

    # ── Sync (once) ───────────────────────────────────────────────────
    local _fleetman="$SCRIPTS_DIR/bin/fleetman"
    if [[ -f "$_fleetman" ]]; then
        section "Launching sync"
        echo ""
        bash "$_fleetman" sync
    else
        warn "fleetman not found — run 'fleetman sync' manually"
    fi
}
