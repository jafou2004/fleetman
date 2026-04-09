#!/bin/bash

##
# @menu Git pull
# @order 8
#
# Runs git pull on a pod directory across all servers hosting it.
# Shows an interactive menu if multiple pods match the search term.
#
# Usage: fleetman pod pull -p <pod-search> [-e <env>]
#
# Options:
#   -p <pod>       Pod search term (required)
#   -e <env>       Environment: dev, test, or prod (default: all)
#   -h, --help     Show this help
#
# Examples:
#   fleetman pod pull -p my-service
#   fleetman pod pull -p my-service -e prod
##

_LIB="$(dirname "${BASH_SOURCE[0]}")/../../lib"
source "$_LIB/vars.sh"
source "$_LIB/display.sh"
source "$_LIB/auth.sh"
source "$_LIB/config.sh"
source "$_LIB/ui.sh"
source "$_LIB/iterate.sh"

# Run git pull on the pod directory on the local server.
pull_local() {
    if [ ! -d "$POD_DIR" ]; then
        warn "$POD_DIR not found, skipping"
        echo ""
        return 0
    fi

    if git -C "$POD_DIR" pull; then
        ok "git pull successful"
        echo ""
        return 0
    else
        err "git pull failed"
        echo ""
        return 1
    fi
}

# Run git pull on the pod directory on a remote server via SSH.
pull_remote() {
    local server=$1
    local result

    result=$(ssh_cmd "$server" bash -s << ENDSSH
if [ ! -d "$POD_DIR" ]; then
    echo "ABSENT"
elif git -C "$POD_DIR" pull >/dev/null 2>&1; then
    echo "OK"
else
    echo "FAILED"
fi
ENDSSH
)

    case "$result" in
        OK)
            ok "git pull successful"
            echo ""
            return 0
            ;;
        ABSENT)
            warn "$POD_DIR not found, skipping"
            echo ""
            return 0
            ;;
        *)
            err "git pull failed"
            echo ""
            return 1
            ;;
    esac
}

cmd_pod_pull() {
    parse_search_env_opts "$@" || true
    shift $((OPTIND - 1))

    if [ -z "$SEARCH" ]; then
        err "Error: a search term is required"
        echo "Usage: fleetman pod pull -p <search> [-e env]"
        exit 1
    fi

    check_sshpass
    check_config_file
    find_and_select_pod "$SEARCH" "$ENV_FILTER" "pod pull: \"$SEARCH\""
    parse_env "$ENV_FILTER"
    collect_pod_servers

    POD_DIR="$PODS_DIR/$SELECTED_POD"

    ask_password

    section "git pull: $SELECTED_POD [$label]"
    echo ""
    iterate_pod_servers pull_local pull_remote
    print_summary

    unset PASSWORD
}
