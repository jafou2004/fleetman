#!/bin/bash

##
# Runs an arbitrary shell command on all servers (or a specific environment).
# Output is shown per server with a header.
#
# Usage: fleetman exec [options] -- <command>
#
# Arguments:
#   <command>  Shell command to run on each server (required, after --)
#
# Options:
#   -e <env>     Target environment: dev, test, or prod (default: all)
#   -h, --help   Show this help
#
# Examples:
#   fleetman exec -- "df -h"
#   fleetman exec -e prod -- uptime
#   fleetman exec -e dev -- "systemctl status docker"
##

_LIB="$(dirname "${BASH_SOURCE[0]}")/../lib"
# shellcheck source=scripts/lib/vars.sh
source "$_LIB/vars.sh"
# shellcheck source=scripts/lib/display.sh
source "$_LIB/display.sh"
# shellcheck source=scripts/lib/auth.sh
source "$_LIB/auth.sh"
# shellcheck source=scripts/lib/config.sh
source "$_LIB/config.sh"

cmd_exec() {
    local ENV_FILTER=""
    local OPTIND=1
    local _opt
    while getopts ":e:" _opt "$@"; do
        case "$_opt" in
            e) ENV_FILTER="$OPTARG" ;;
            :) err "Option -$OPTARG requires an argument"; exit 1 ;;
            \?) err "Unknown option: -$OPTARG"; exit 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    # Consume optional -- separator
    if [[ "${1:-}" == "--" ]]; then
        shift
    fi

    local COMMAND="${1:-}"
    if [[ -z "$COMMAND" ]]; then
        err "A command is required"
        echo "Usage: fleetman exec [options] -- <command>"
        exit 1
    fi

    check_sshpass
    check_config_file
    parse_env "$ENV_FILTER"
    ask_password

    section "Exec: \"$COMMAND\" [$(env_label)]"

    local failure_count=0
    local _rc=0
    while IFS= read -r server <&3; do
        echo ""
        if [ "$server" = "$MASTER_HOST" ] || \
           [ "$(short_name "$server")" = "$(short_name "$MASTER_HOST")" ]; then
            echo -e "${BLUE}── $(short_name "$server") (local) ──────────────────────────────${NC}"
            bash -c "$COMMAND" || _rc=$?
        else
            echo -e "${BLUE}── $(short_name "$server") ──────────────────────────────────────${NC}"
            ssh_cmd "$server" "$COMMAND" || _rc=$?
        fi
        if [ "$_rc" -ne 0 ]; then
            failure_count=$(( failure_count + 1 ))
            _rc=0
        fi
    done 3< <(
        if [ -n "$ENV" ]; then
            jq -r --arg env "$ENV" '.servers[$env] | .[]' "$CONFIG_FILE"
        else
            jq -r '.servers[] | .[]' "$CONFIG_FILE"
        fi
    )

    echo ""
    if [ "$failure_count" -gt 0 ]; then
        err "$failure_count server(s) returned a non-zero exit code"
        return 1
    fi
}
