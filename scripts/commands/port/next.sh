#!/bin/bash

##
# @menu Next available ports
# @order 1
#
# Lists the next available external ports in the configured range.
#
# Usage: fleetman port next [-n <count>]
#
# Options:
#   -n <count>   Number of ports to return (default: 5)
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

cmd_port_next() {
    local COUNT=5 OPTIND=1

    while getopts ":n:" _opt "$@"; do
        case "$_opt" in
            n) COUNT="$OPTARG" ;;
            :) err "Option -$_opt requires an argument"; exit 1 ;;
            \?) err "Unknown option: -$OPTARG"; exit 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    if [[ ! "$COUNT" =~ ^[1-9][0-9]*$ ]]; then
        err "Invalid value for -n: must be a positive integer"
        exit 1
    fi

    check_config_file
    check_services_file
    _port_read_range

    local used_ports
    used_ports=$(_port_collect_used | jq '[.[].port] | unique | sort')

    local -a result=()
    local port
    for (( port=PORT_MIN; port<=PORT_MAX && ${#result[@]}<COUNT; port++ )); do
        local in_use
        in_use=$(printf '%s' "$used_ports" | jq --argjson p "$port" 'map(. == $p) | any')
        if [ "$in_use" = "false" ]; then
            result+=("$port")
        fi
    done

    section "Next available ports in range [${PORT_MIN}–${PORT_MAX}]"
    echo ""

    if [ "${#result[@]}" -eq 0 ]; then
        warn "No available ports in range [${PORT_MIN}–${PORT_MAX}]"
        return 0
    fi

    for port in "${result[@]}"; do
        printf "  %s\n" "$port"
    done

    if [ "${#result[@]}" -lt "$COUNT" ]; then
        echo ""
        warn "Only ${#result[@]} port(s) available in range [${PORT_MIN}–${PORT_MAX}] (${COUNT} requested)"
    fi

    echo ""
}
