#!/bin/bash

##
# @menu Start pod
# @order 5
#
# Starts a pod (docker compose up -d) across all servers hosting it.
# Shows an interactive menu if multiple pods match the search term.
#
# Usage: fleetman pod up -p <pod-search> [-e <env>]
#
# Options:
#   -p <pod>       Pod search term (required)
#   -e <env>       Environment: dev, test, or prod (default: all)
#   -h, --help     Show this help
#
# Examples:
#   fleetman pod up -p my-service
#   fleetman pod up -p my-service -e prod
##

_LIB="$(dirname "${BASH_SOURCE[0]}")/../../lib"
source "$_LIB/vars.sh"
source "$_LIB/display.sh"
source "$_LIB/auth.sh"
source "$_LIB/config.sh"
source "$_LIB/ui.sh"
source "$_LIB/iterate.sh"

# Start the pod on the local server.
up_local() {
    if [ ! -d "$POD_DIR" ]; then
        warn "$POD_DIR not found, skipping"
        echo ""
        append_result absent "$(short_name "$MASTER_HOST") (local)"
        return 0
    fi

    if sudo_run docker compose -f "$POD_COMPOSE" up -d; then
        ok "started successfully"
        echo ""
        return 0
    else
        err "docker compose up -d failed"
        echo ""
        return 1
    fi
}

# Start the pod on a remote server via SSH.
up_remote() {
    local server=$1
    local result

    result=$(ssh_cmd "$server" bash -s << ENDSSH
if [ ! -d "$POD_DIR" ]; then
    echo "ABSENT"
elif echo "$B64_PASS" | base64 -d | sudo -S docker compose -f "$POD_COMPOSE" up -d >/dev/null 2>&1; then
    echo "STARTED"
else
    echo "FAILED"
fi
ENDSSH
)

    case "$result" in
        STARTED)
            ok "started successfully"
            echo ""
            return 0
            ;;
        ABSENT)
            warn "$POD_DIR not found, skipping"
            echo ""
            append_result absent "$(short_name "$server")"
            return 0
            ;;
        *)
            err "docker compose up -d failed"
            echo ""
            return 1
            ;;
    esac
}

cmd_pod_up() {
    parse_search_env_opts "$@" || true
    shift $((OPTIND - 1))

    if [ -z "$SEARCH" ]; then
        err "Error: a search term is required"
        echo "Usage: fleetman pod up -p <search> [-e env]"
        exit 1
    fi

    check_sshpass
    check_config_file
    find_and_select_pod "$SEARCH" "$ENV_FILTER" "pod up: \"$SEARCH\""
    parse_env "$ENV_FILTER"
    collect_pod_servers

    POD_DIR="$PODS_DIR/$SELECTED_POD"
    POD_COMPOSE="$POD_DIR/docker-compose.yml"

    ask_password

    absent=()

    section "Starting $SELECTED_POD [$label]"
    echo ""
    iterate_pod_servers up_local up_remote
    print_summary

    unset PASSWORD
}
