#!/bin/bash

##
# @menu Base folder
# @order 9
#
# Sets the default working directory on SSH login.
#
# Usage: fleetman config basefolder
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

cmd_config_basefolder() {
    local OPTIND=1
    while getopts ":" _opt "$@"; do
        case "$_opt" in
            \?) err "Unknown option: -$OPTARG"; exit 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    check_config_file

    local current
    current=$(jq -r '.base_folder // ""' "$CONFIG_FILE")

    section "Configuration — base folder"
    printf "  Current: %s\n" "${current:-<not set>}"
    echo ""
    printf "  New base_folder [Enter = keep, '-' = disable] ? "
    local new
    read -r new

    case "$new" in
        "")  new="$current" ;;
        "-") new="" ;;
    esac

    if [ -n "$new" ] && [ ! -d "$new" ]; then
        err "Directory does not exist: $new"
        exit 1
    fi

    if [ "$new" = "$current" ]; then
        ok "Unchanged (base_folder = ${current:-<not set>})"
        return 0
    fi

    local tmp
    tmp=$(mktemp)
    if [ -n "$new" ]; then
        if ! jq --arg v "$new" '.base_folder = $v' "$CONFIG_FILE" > "$tmp" \
                || ! mv "$tmp" "$CONFIG_FILE"; then
            rm -f "$tmp"
            err "Failed to write config"
            exit 1
        fi
    else
        if ! jq 'del(.base_folder)' "$CONFIG_FILE" > "$tmp" \
                || ! mv "$tmp" "$CONFIG_FILE"; then
            rm -f "$tmp"
            err "Failed to write config"
            exit 1
        fi
    fi

    ok "base_folder: ${current:-<not set>} → ${new:-<not set>}"
    prompt_sync_confirm
}
