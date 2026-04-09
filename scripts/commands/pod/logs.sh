#!/bin/bash

##
# @menu Logs
# @order 3
#
# Tails Docker Compose logs for a pod on a chosen server.
#
# Usage: fleetman pod logs -p <pod-search> [-e <env>] [-n <lines>] [-s [service]]
#
# Options:
#   -p <pod>          Pod search term (required)
#   -e <env>          Environment: dev, test, or prod (default: all)
#   -n <lines>        Initial lines to show via --tail (default: 50)
#   -s [service]      Docker Compose service to target; omit value to pick from menu
#   -h, --help        Show this help
#
# Examples:
#   fleetman pod logs -p my-service
#   fleetman pod logs -p my-service -e prod -n 100
#   fleetman pod logs -p my-service -s worker
#   fleetman pod logs -p my-service -s
##

_LIB="$(dirname "${BASH_SOURCE[0]}")/../../lib"
source "$_LIB/vars.sh"
source "$_LIB/display.sh"
source "$_LIB/auth.sh"
source "$_LIB/config.sh"
source "$_LIB/ui.sh"

# Tail logs for a pod on a given server.
# shellcheck disable=SC2154
show_logs() {
    local server=$1
    local pod=$2

    if [ "$server" = "$MASTER_HOST" ]; then
        # shellcheck disable=SC2086
        sudo_run docker compose \
            -f "$PODS_DIR/$pod/docker-compose.yml" \
            logs --tail="$TAIL_LINES" -f${SERVICE:+ $SERVICE}
    else
        # shellcheck disable=SC2154
        ssh_cmd -t "$server" \
            "echo '$B64_PASS' | base64 -d | sudo -S docker compose \
             -f '$PODS_DIR/$pod/docker-compose.yml' logs --tail='$TAIL_LINES' -f${SERVICE:+ $SERVICE} 2>/dev/null"
    fi
}

# Show an interactive menu to pick a Docker Compose service from services.json.
# Sets SERVICE global. Falls back gracefully when services.json is missing or empty.
_select_service_menu() {
    local server=$1
    local pod=$2
    local services_file="$DATA_DIR/services.json"

    if [ ! -f "$services_file" ]; then
        warn "services.json missing — all services will be displayed"
        return 0
    fi

    local env
    env=$(jq -r --arg srv "$server" \
        'to_entries[] | select(.value | has($srv)) | .key' "$services_file" 2>/dev/null | head -1)

    if [ -z "$env" ]; then
        warn "$(short_name "$server") not found in services.json — all services will be displayed"
        return 0
    fi

    local -a service_names
    mapfile -t service_names < <(jq -r \
        --arg e "$env" --arg srv "$server" --arg pod "$pod" \
        '.[$e][$srv][$pod][]?.Service' "$services_file" 2>/dev/null | sort -u)

    if [ "${#service_names[@]}" -eq 0 ]; then
        warn "No service found for $pod — all services will be displayed"
        return 0
    fi

    if [ "${#service_names[@]}" -eq 1 ]; then
        SERVICE="${service_names[0]}"
        return 0
    fi

    select_menu service_names
    SERVICE="${service_names[$SELECTED_IDX]}"
}

# Connect to a server, prompting for a pod when multiple are hosted there.
connect_to_server() {
    local server=$1
    local pods_str="${server_pods[$server]}"
    read -ra pods_arr <<< "$pods_str"

    local pod
    if [ "${#pods_arr[@]}" -eq 1 ]; then
        pod="${pods_arr[0]}"
    else
        # Multiple pods on this server — show a sub-menu
        select_menu pods_arr
        pod="${pods_arr[$SELECTED_IDX]}"
    fi

    if [ "$SELECT_SERVICE" = "true" ]; then
        _select_service_menu "$server" "$pod"
    fi

    show_logs "$server" "$pod"
}

cmd_pod_logs() {
    OPTIND=1
    SEARCH=""
    ENV_FILTER=""
    TAIL_LINES=50
    SERVICE=""
    SELECT_SERVICE=false

    # Pre-scan: detect -s without argument → show interactive service selection menu.
    # Keeps "-s <value>" intact for getopts and removes bare "-s" from the arg list.
    local _new_args=() _idx _arg _next_idx _next
    _idx=1
    while [ "$_idx" -le "$#" ]; do
        _arg="${!_idx}"
        if [[ "$_arg" == "-s" ]]; then
            _next_idx=$((_idx + 1))
            _next="${!_next_idx:-}"
            if [[ -z "$_next" || "$_next" == -* ]]; then
                SELECT_SERVICE=true
            else
                _new_args+=("-s" "$_next")
                _idx=$((_idx + 1))
            fi
        else
            _new_args+=("$_arg")
        fi
        _idx=$((_idx + 1))
    done
    set -- "${_new_args[@]}"

    local opt
    while getopts ":p:e:n:s:" opt; do
        case "$opt" in
            p) SEARCH="$OPTARG" ;;
            e) ENV_FILTER="$OPTARG" ;;
            n) TAIL_LINES="$OPTARG" ;;
            s) SERVICE="$OPTARG" ;;
            :)
                err "Error: -$OPTARG requires an argument"
                echo "Usage: fleetman pod logs -p <pod> [-e env] [-n lines] [-s [service]]"
                exit 1
                ;;
            \?)
                err "Unknown option: -$OPTARG"
                echo "Usage: fleetman pod logs -p <pod> [-e env] [-n lines] [-s [service]]"
                exit 1
                ;;
        esac
    done
    shift $((OPTIND - 1))

    if [ -z "$SEARCH" ]; then
        err "Error: a pod search term is required (-p)"
        echo "Usage: fleetman pod logs -p <pod> [-e env] [-n lines] [-s [service]]"
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

    check_sshpass
    ask_password

    local label
    label=$(env_label "$ENV_FILTER")
    section "Logs: \"$SEARCH\" [$label]"
    echo ""

    if [ "$total" -eq 1 ]; then
        connect_to_server "${server_order[0]}"
        unset PASSWORD
        exit 0
    fi

    # Multiple servers: interactive arrow-key menu
    # shellcheck disable=SC2034
    local labels=()
    build_server_labels labels

    select_menu labels
    echo ""

    connect_to_server "${server_order[$SELECTED_IDX]}"

    unset PASSWORD
}
