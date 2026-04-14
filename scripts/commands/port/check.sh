#!/bin/bash

##
# @menu Check port availability
# @order 3
#
# Checks whether one or more ports are free across the entire fleet.
# Exit code 1 if any port is in use (useful for scripting).
#
# Usage: fleetman port check <port> [port...]
#
# Options:
#   -h, --help   Show this help
##

_LIB="$(dirname "${BASH_SOURCE[0]}")/../../lib"
# shellcheck source=scripts/lib/vars.sh
source "$_LIB/vars.sh"
# shellcheck source=scripts/lib/display.sh
source "$_LIB/display.sh"
# shellcheck source=scripts/lib/config.sh
source "$_LIB/config.sh"
# shellcheck source=scripts/lib/ports.sh
source "$_LIB/ports.sh"

cmd_port_check() {
    local OPTIND=1
    while getopts ":" _opt "$@"; do
        case "$_opt" in
            \?) err "Unknown option: -$OPTARG"; exit 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    if [ "$#" -eq 0 ]; then
        err "At least one port number is required"
        echo "  Usage: fleetman port check <port> [port...]"
        exit 1
    fi

    check_config_file
    check_services_file

    local used_json
    used_json=$(_port_collect_used)

    local any_used=0

    local arg
    for arg in "$@"; do
        if [[ ! "$arg" =~ ^[1-9][0-9]*$ ]]; then
            err "Invalid port: $arg (must be a positive integer)"
            exit 1
        fi

        local match_count
        match_count=$(printf '%s' "$used_json" | jq \
            --argjson p "$arg" '[.[] | select(.port == $p)] | length')

        if [ "$match_count" -eq 0 ]; then
            printf "  ${GREEN}✓${NC} %-6s  free\n" "$arg"
        else
            any_used=1
            local detail
            while IFS= read -r line; do
                printf "  ${RED}✗${NC} %-6s  used by %s\n" "$arg" "$line"
            done < <(printf '%s' "$used_json" | jq -r \
                --argjson p "$arg" \
                '[.[] | select(.port == $p)] |
                group_by([.pod, .service]) | .[] |
                {
                    pod: .[0].pod,
                    service: .[0].service,
                    envs: (group_by(.env) | map(
                        "[" + .[0].env + "] " +
                        (map(.server | split(".")[0]) | unique | join(", "))
                    ) | join("  "))
                } |
                .pod + " / " + .service + "  " + .envs')
        fi
    done

    return $any_used
}
