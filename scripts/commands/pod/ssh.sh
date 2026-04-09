#!/bin/bash

##
# @menu SSH to pod
# @order 1
#
# Opens an SSH connection to a server hosting a pod.
#
# Auto-cd to the pod directory on single match; interactive menu on multiple.
#
# Usage: fleetman pod ssh -p <pod-search> [-e <env>]
#
# Options:
#   -p <pod>      Pod search term (required)
#   -e <env>      Environment: dev, test, or prod (default: all)
#   -h, --help    Show this help
#
# Examples:
#   fleetman pod ssh -p my-service
#   fleetman pod ssh -p my-service -e prod
##

_LIB="$(dirname "${BASH_SOURCE[0]}")/../../lib"
source "$_LIB/vars.sh"
source "$_LIB/display.sh"
source "$_LIB/auth.sh"
source "$_LIB/config.sh"
source "$_LIB/ui.sh"

# Open an SSH connection (or local shell) to a server, optionally cd to a pod.
connect() {
    local server=$1
    local pod=$2

    if [ "$server" = "$MASTER_HOST" ]; then
        if [ -n "$pod" ]; then
            ok "Local server — changing to $PODS_DIR/$pod"
            # shellcheck disable=SC2164  # interactive shell: cd failure is visible to the user
            cd "$PODS_DIR/$pod"
        else
            ok "Local server"
            # shellcheck disable=SC2164  # interactive shell: cd failure is visible to the user
            cd "$PODS_DIR"
        fi
        return 0
    fi

    if [ -n "$pod" ]; then
        ok "Connecting to $(short_name "$server") → $PODS_DIR/$pod"
        ssh_cmd -t "$server" "cd $PODS_DIR/$pod && SHLVL=2 exec bash"
    else
        ok "Connecting to $(short_name "$server")"
        ssh_cmd "$server"
    fi
}

# Connect to a server, auto-selecting the pod if there is exactly one match.
connect_to_server() {
    local server=$1
    local pods_str="${server_pods[$server]}"
    read -ra pods_arr <<< "$pods_str"
    local pod=""
    [ "${#pods_arr[@]}" -eq 1 ] && pod="${pods_arr[0]}"
    connect "$server" "$pod"
}

cmd_pod_ssh() {
    parse_search_env_opts "$@" || true
    shift $((OPTIND - 1))

    if [ -z "$SEARCH" ]; then
        err "Error: a search term is required"
        echo "Usage: fleetman pod ssh -p <search> [-e env]"
        exit 1
    fi

    check_config_file
    check_pods_file
    validate_env_filter
    collect_server_pods

    local total=${#server_order[@]}

    if [ "$total" -eq 0 ]; then
        warn "No results for \"$SEARCH\""
        exit 0
    fi

    # Ask for password only if at least one remote server is involved
    local needs_ssh=false
    local server
    for server in "${server_order[@]}"; do
        [ "$server" != "$MASTER_HOST" ] && needs_ssh=true && break
    done
    if $needs_ssh; then
        check_sshpass
        [ ! -f "$FLEET_KEY" ] && ask_password
    fi

    # Single server: connect directly
    if [ "$total" -eq 1 ]; then
        connect_to_server "${server_order[0]}"
        exit 0
    fi

    # Multiple servers: interactive arrow-key menu
    # shellcheck disable=SC2034  # labels passed by name to build_server_labels
    local labels=()
    build_server_labels labels

    local label
    label=$(env_label "$ENV_FILTER")
    section "SSH: \"$SEARCH\" [$label]"
    echo ""

    select_menu labels
    echo ""

    connect_to_server "${server_order[$SELECTED_IDX]}"

    unset PASSWORD
}
