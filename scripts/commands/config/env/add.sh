#!/bin/bash

##
# @menu Add environment
# @order 1
#
# Adds a new environment to config.json (env_colors and servers).
#
# Usage: fleetman config env add
#
# Options:
#   -h, --help   Show this help
##

_LIB="$(dirname "${BASH_SOURCE[0]}")/../../../lib"
# shellcheck source=scripts/lib/vars.sh
source "$_LIB/vars.sh"
# shellcheck source=scripts/lib/display.sh
source "$_LIB/display.sh"
# shellcheck source=scripts/lib/config.sh
source "$_LIB/config.sh"
# shellcheck source=scripts/lib/ui.sh
source "$_LIB/ui.sh"

_list_envs() {
    local env color bg
    while IFS= read -r env; do
        color=$(jq -r --arg e "$env" '.env_colors[$e] // "white"' "$CONFIG_FILE" 2>/dev/null)
        bg=$(env_color_ansi "$color" bg)
        printf "  ${bg}%s${NC} (%s)\n" "$env" "$color"
    done < <(jq -r '.servers | keys[]' "$CONFIG_FILE" 2>/dev/null)
}

cmd_config_env_add() {
    local OPTIND=1
    while getopts ":" _opt "$@"; do
        case "$_opt" in
            \?) err "Unknown option: -$OPTARG"; exit 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    check_config_file

    section "Configuration — add environments"

    printf "List of current environments:\n"
    _list_envs
    echo ""

    local new_env
    new_env=$(prompt_response "New environment name")
    new_env="${new_env,,}"

    if jq -e --arg e "$new_env" '.servers | has($e)' "$CONFIG_FILE" > /dev/null 2>&1; then
        err "Environment '$new_env' already exists"
        exit 1
    fi

    local -a display_labels=()
    local c fg
    for c in "${COLOR_NAMES[@]}"; do
        bg=$(env_color_ansi "$c" bg)
        display_labels+=("$(printf "${bg}%s${NC}" "$c")")
    done
    printf "Choose the associated color:\n"
    select_menu display_labels
    local chosen_color="${COLOR_NAMES[$SELECTED_IDX]}"

    local tmp
    tmp=$(mktemp)
    if ! jq --arg e "$new_env" --arg c "$chosen_color" \
        '.env_colors[$e] = $c | .servers[$e] = []' \
        "$CONFIG_FILE" > "$tmp" || ! mv "$tmp" "$CONFIG_FILE"; then
        rm -f "$tmp"
        err "Failed to write config"
        exit 1
    fi

    ok "Environment '$new_env' added (color: $chosen_color)"

    prompt_sync_confirm
}
