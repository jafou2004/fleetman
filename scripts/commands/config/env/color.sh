#!/bin/bash

##
# @menu Change environment color
# @order 2
#
# Changes the color of an existing environment in config.json.
#
# Usage: fleetman config env color
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

cmd_config_env_color() {
    local OPTIND=1
    while getopts ":" _opt "$@"; do
        case "$_opt" in
            \?) err "Unknown option: -$OPTARG"; exit 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    check_config_file

    section "Configuration — environment colors"

    # ── Menu 1: environment selection ──────────────────────────────────
    local -a env_names=()
    mapfile -t env_names < <(jq -r '.servers | keys[]' "$CONFIG_FILE")

    local -a env_labels=()
    local e current_color bg
    for e in "${env_names[@]}"; do
        current_color=$(jq -r --arg e "$e" '.env_colors[$e] // "white"' "$CONFIG_FILE")
        bg=$(env_color_ansi "$current_color" bg)
        env_labels+=("$(printf "${bg}%s${NC} (%s)" "$e" "$current_color")")
    done

    printf "Select the environment to modify:\n"
    select_menu env_labels
    local selected_env="${env_names[$SELECTED_IDX]}"

    # ── Menu 2: color selection (preselect current color) ───────
    local existing_color
    existing_color=$(jq -r --arg e "$selected_env" '.env_colors[$e] // "white"' "$CONFIG_FILE")

    local current_idx=0
    local i
    for i in "${!COLOR_NAMES[@]}"; do
        if [[ "${COLOR_NAMES[$i]}" == "$existing_color" ]]; then
            current_idx=$i
            break
        fi
    done

    local -a color_labels=()
    local c
    for c in "${COLOR_NAMES[@]}"; do
        bg=$(env_color_ansi "$c" bg)
        color_labels+=("$(printf "${bg}%s${NC}" "$c")")
    done

    printf "Choose the new associated color:\n"
    select_menu color_labels "$current_idx"
    local chosen_color="${COLOR_NAMES[$SELECTED_IDX]}"

    # ── Check unchanged ────────────────────────────────────────────────
    if [[ "$chosen_color" == "$existing_color" ]]; then
        ok "Unchanged (color of '$selected_env' = $existing_color)"
        return 0
    fi

    # ── Atomic write ─────────────────────────────────────────────────────────
    local tmp
    tmp=$(mktemp)
    if ! jq --arg e "$selected_env" --arg c "$chosen_color" \
        '.env_colors[$e] = $c' "$CONFIG_FILE" > "$tmp" || ! mv "$tmp" "$CONFIG_FILE"; then
        rm -f "$tmp"
        err "Failed to write config"
        exit 1
    fi

    ok "Color of '$selected_env' updated: $chosen_color"

    prompt_sync_confirm
}
