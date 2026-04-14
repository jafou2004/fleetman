#!/bin/bash

##
# @menu Port range
# @order 13
#
# Sets the port range used by 'fleetman port next/list/check'.
#
# Usage: fleetman config portrange
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
# shellcheck source=scripts/lib/ui.sh
source "$_LIB/ui.sh"

cmd_config_portrange() {
    local OPTIND=1
    while getopts ":" _opt "$@"; do
        case "$_opt" in
            \?) err "Unknown option: -$OPTARG"; exit 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    check_config_file

    local current_min current_max
    current_min=$(jq -r '.port_range.min // ""' "$CONFIG_FILE" 2>/dev/null)
    current_max=$(jq -r '.port_range.max // ""' "$CONFIG_FILE" 2>/dev/null)

    section "Configuration — port range"
    printf "  Current: %s – %s\n" "${current_min:-<not set>}" "${current_max:-<not set>}"
    echo ""

    local new_min new_max
    printf "  Min port [Enter = keep] ? "
    read -r new_min
    [ -z "$new_min" ] && new_min="$current_min"

    printf "  Max port [Enter = keep] ? "
    read -r new_max
    [ -z "$new_max" ] && new_max="$current_max"

    # Validate both are integers
    if [[ ! "$new_min" =~ ^[0-9]+$ ]] || [[ ! "$new_max" =~ ^[0-9]+$ ]]; then
        err "Invalid value: both ports must be integers"
        exit 1
    fi
    if (( new_min < 1024 || new_min > 65535 )); then
        err "Min port must be in [1024, 65535]"
        exit 1
    fi
    if (( new_max < 1024 || new_max > 65535 )); then
        err "Max port must be in [1024, 65535]"
        exit 1
    fi
    if (( new_min >= new_max )); then
        err "Min port must be strictly less than max port"
        exit 1
    fi

    if [ "$new_min" = "$current_min" ] && [ "$new_max" = "$current_max" ]; then
        ok "Unchanged (port_range: ${current_min} – ${current_max})"
        return 0
    fi

    local tmp
    tmp=$(mktemp)
    if ! jq --argjson min "$new_min" --argjson max "$new_max" \
            '.port_range = {"min": $min, "max": $max}' "$CONFIG_FILE" > "$tmp" \
            || ! mv "$tmp" "$CONFIG_FILE"; then
        rm -f "$tmp"
        err "Failed to write config"
        exit 1
    fi

    ok "port_range: ${current_min:-<not set>} – ${current_max:-<not set>} → ${new_min} – ${new_max}"
    prompt_sync_confirm
}
