#!/bin/bash

##
# Opens an SSH connection to a fleet server.
#
# Usage: fleetman ssh [-e <env>] [-s <server>]
#
# Options:
#   -e <env>      Environment filter (dev, test, prod…)
#   -s <server>   Server shortname filter (substring match)
#   -h, --help    Show this help
#
# Examples:
#   fleetman ssh
#   fleetman ssh -e prod
#   fleetman ssh -s srv2 -e prod
##

_LIB="$(dirname "${BASH_SOURCE[0]}")/../lib"
source "$_LIB/vars.sh"
source "$_LIB/display.sh"
source "$_LIB/auth.sh"
source "$_LIB/config.sh"
source "$_LIB/ui.sh"

# Open an SSH connection to a server (no pod context).
connect_server() {
    local server=$1

    if [ "$server" = "$MASTER_HOST" ]; then
        ok "Local server"
        return 0
    fi

    ok "Connecting to $(short_name "$server")"
    ssh_cmd "$server"
}

cmd_ssh() {
    parse_server_filter_opts "$@" || true
    shift $((OPTIND - 1))

    check_config_file
    collect_servers

    local total=${#server_list[@]}

    if [ "$total" -eq 0 ]; then
        warn "No servers found"
        exit 0
    fi

    # Ask for password only if at least one remote server is involved
    local needs_ssh=false
    local server
    for server in "${server_list[@]}"; do
        [ "$server" != "$MASTER_HOST" ] && needs_ssh=true && break
    done
    if $needs_ssh; then
        check_sshpass
        [ ! -f "$FLEET_KEY" ] && ask_password
    fi

    # Single server: connect directly
    if [ "$total" -eq 1 ]; then
        connect_server "${server_list[0]}"
        exit 0
    fi

    # Multiple servers: interactive arrow-key menu
    # shellcheck disable=SC2034  # labels passed by name to build_server_list_labels
    local labels=()
    build_server_list_labels labels

    local label
    label=$(env_label "$ENV_FILTER")
    section "SSH [$label]"
    echo ""

    select_menu labels
    echo ""

    connect_server "${server_list[$SELECTED_IDX]}"

    unset PASSWORD
}
