#!/bin/bash

##
# @menu List used ports
# @order 2
#
# Lists all external ports in use across the fleet with pod, service, and env detail.
#
# Usage: fleetman port list
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

cmd_port_list() {
    local OPTIND=1
    while getopts ":" _opt "$@"; do
        case "$_opt" in
            \?) err "Unknown option: -$OPTARG"; exit 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    check_config_file
    check_services_file

    local used_json
    used_json=$(_port_collect_used)

    # Environments sorted alphabetically (drives column order)
    local -a envs
    mapfile -t envs < <(jq -r '.servers | keys[]' "$CONFIG_FILE")

    # Unique (port, pod, service) tuples sorted by port
    local rows
    rows=$(printf '%s' "$used_json" | jq -r '
        [ .[] | {port, pod, service} ] | unique |
        sort_by(.port) |
        .[] | [(.port | tostring), .pod, .service] | @tsv
    ')

    # Column widths: PORT=6, POD=12, SERVICE=10, each env=10
    local col_env=10
    local sep_len=$(( 34 + ${#envs[@]} * (col_env + 2) ))

    section "Port list"
    echo ""

    # Header
    printf "  %-6s  %-12s  %-10s" "PORT" "POD" "SERVICE"
    local env
    for env in "${envs[@]}"; do
        printf "  %-${col_env}s" "${env^^}"
    done
    echo ""

    # Separator
    printf "  "
    local i; for (( i=0; i<sep_len; i++ )); do printf '─'; done
    echo ""

    if [ -z "$rows" ]; then
        echo ""
        warn "No ports in use"
        return 0
    fi

    local port pod service
    while IFS=$'\t' read -r port pod service; do
        local env_cells=""
        for env in "${envs[@]}"; do
            local all_srv
            all_srv=$(jq -r --arg p "$pod" '.pods[$p].all_servers // false' "$CONFIG_FILE" 2>/dev/null)

            local cell
            if [ "$all_srv" = "true" ]; then
                local present
                present=$(printf '%s' "$used_json" | jq \
                    --arg e "$env" --arg p "$pod" --arg s "$service" \
                    '[.[] | select(.env == $e and .pod == $p and .service == $s)] | length')
                if [ "$present" -gt 0 ]; then
                    cell="All srvs"
                else
                    cell="—"
                fi
            else
                local servers
                servers=$(printf '%s' "$used_json" | jq -r \
                    --argjson port "$port" \
                    --arg e "$env" --arg p "$pod" --arg s "$service" \
                    '[.[] | select(.port == $port and .env == $e and .pod == $p and .service == $s)
                           | .server | split(".")[0]] | unique | join(", ")')
                cell="${servers:-—}"
            fi
            env_cells+=$(printf "  %-${col_env}s" "$cell")
        done
        printf "  %-6s  %-12s  %-10s%s\n" "$port" "$pod" "$service" "$env_cells"
    done <<< "$rows"

    echo ""
}
