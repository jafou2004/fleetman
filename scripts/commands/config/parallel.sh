#!/bin/bash

##
# @menu Parallel jobs
# @order 1
#
# Sets the number of parallel SSH jobs used during fleet operations.
#
# Usage: fleetman config parallel
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

cmd_config_parallel() {
    local OPTIND=1
    # No declared flags — leading ":" enables silent mode; \? rejects any unknown option.
    # -h is intercepted by the dispatcher before this function is called.
    while getopts ":" _opt "$@"; do
        case "$_opt" in
            \?) err "Unknown option: -$OPTARG"; exit 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    check_config_file

    local current
    # Use null-check instead of // to avoid jq's falsy-0 gotcha (0 // 1 returns 1).
    current=$(jq 'if .parallel != null then .parallel else 1 end' "$CONFIG_FILE")

    section "Configuration — parallel jobs"

    local new
    new=$(prompt_response "Number of parallel jobs" "$current")

    if [[ ! "$new" =~ ^[1-9][0-9]*$ ]]; then
        err "Invalid value: must be a positive integer"
        exit 1
    fi

    if [[ "$new" == "$current" ]]; then
        ok "Unchanged (parallel = $current)"
        return 0
    fi

    local tmp
    tmp=$(mktemp)
    if ! jq --argjson v "$new" '.parallel = $v' "$CONFIG_FILE" > "$tmp" || ! mv "$tmp" "$CONFIG_FILE"; then
        rm -f "$tmp"
        err "Failed to write config"
        exit 1
    fi

    ok "parallel: $current → $new"
    prompt_sync_confirm
}
