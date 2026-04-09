#!/bin/bash

##
# @menu Copy .env to fleet
# @order 1
#
# Propagates the local .env file to all servers hosting a pod.
# Applies per-server template substitution for variables defined in env_templates.
#
# Usage: fleetman pod env cp -p <pod-search> [-e <env>]
#
# Options:
#   -p <pod>       Pod search term (required)
#   -e <env>       Environment: dev, test, or prod (default: all)
#   -h, --help     Show this help
#
# Examples:
#   fleetman pod env cp -p my-service
#   fleetman pod env cp -p my-service -e prod
##

_LIB="$(dirname "${BASH_SOURCE[0]}")/../../../lib"
source "$_LIB/vars.sh"
source "$_LIB/display.sh"
source "$_LIB/auth.sh"
source "$_LIB/config.sh"
source "$_LIB/ui.sh"
source "$_LIB/iterate.sh"
source "$_LIB/templates.sh"

# Updates the local .env with per-server template substitutions.
cp_local() {
    if [ -z "$TEMPLATES_JSON" ]; then
        ok ".env already local"
        echo ""
        return 0
    fi
    if _apply_templates "$MASTER_HOST" "$POD_ENV"; then
        ok ".env updated"
        echo ""
        return 0
    else
        err "Failed to apply templates"
        echo ""
        return 1
    fi
}

# Copies the .env to a remote server and applies per-server template substitutions.
cp_remote() {
    local server="$1"
    local result
    if ! scp_cmd "$POD_ENV" "$server:$POD_ENV" > /dev/null 2>&1; then
        err "Failed to copy .env"
        echo ""
        return 1
    fi
    if [ -z "$TEMPLATES_JSON" ]; then
        ok ".env propagated"
        echo ""
        return 0
    fi
    _build_sed_cmds "$server"
    result=$(ssh_cmd "$server" bash -s << ENDSSH
if sed -i "$SED_CMDS" "$POD_ENV" 2>/dev/null; then echo "UPDATED"; else echo "SED_FAILED"; fi
ENDSSH
)
    case "$result" in
        UPDATED)
            ok ".env propagated + templates applied"
            echo ""
            return 0
            ;;
        *)
            err "Failed to apply templates"
            echo ""
            return 1
            ;;
    esac
}

cmd_pod_env_cp() {
    parse_search_env_opts "$@" || true
    shift $((OPTIND - 1))

    if [ -z "$SEARCH" ]; then
        err "Error: a search term is required"
        echo "Usage: fleetman pod env cp -p <search> [-e env]"
        exit 1
    fi

    check_sshpass
    check_config_file
    find_and_select_pod "$SEARCH" "$ENV_FILTER" "pod env cp: \"$SEARCH\""
    parse_env "$ENV_FILTER"
    collect_pod_servers

    POD_DIR="$PODS_DIR/$SELECTED_POD"
    POD_ENV="$POD_DIR/.env"
    load_pod_templates "$SELECTED_POD"

    if [ ! -f "$POD_ENV" ]; then
        err "$POD_ENV not found on local server"
        exit 1
    fi

    ask_password

    section "Propagating $SELECTED_POD .env [$label]"
    echo ""
    iterate_pod_servers cp_local cp_remote
    print_summary

    unset PASSWORD
}
