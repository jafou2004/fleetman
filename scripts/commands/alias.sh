#!/bin/bash

##
# Lists available aliases from ~/.bash_aliases, grouped by category.
# Accepts an optional category filter (prefix match, case-insensitive).
#
# Usage: fleetman alias [-c category]
#
# Options:
#   -c <category>   Category prefix to filter (e.g. git, docker, scripts)
#   -h, --help      Show this help
#
# Examples:
#   fleetman alias
#   fleetman alias -c git
#   fleetman alias -c docker
##

_LIB="$(dirname "${BASH_SOURCE[0]}")/../lib"
# shellcheck source=scripts/lib/vars.sh
source "$_LIB/vars.sh"
# shellcheck source=scripts/lib/display.sh
source "$_LIB/display.sh"

cmd_alias() {
    local OPTIND=1
    local filter=""
    while getopts ":c:" _opt "$@"; do
        case "$_opt" in
            c) filter="${OPTARG,,}" ;;
            :) err "Option -$OPTARG requires an argument"; exit 1 ;;
            \?) err "Unknown option: -$OPTARG"; exit 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    if [[ ! -f "$USER_ALIASES_FILE" ]]; then
        err "Aliases file not found: $USER_ALIASES_FILE"
        exit 1
    fi

    local -a cat_names=()
    local -a cat_data=()
    local current_cat=""
    local current_lines=""

    local -a _lines=()
    mapfile -t _lines < "$USER_ALIASES_FILE"
    local line
    for line in "${_lines[@]}"; do
        if [[ "$line" =~ ^#[[:space:]]+###[[:space:]]+(.+)$ ]]; then
            if [[ -n "$current_cat" && -n "$current_lines" ]]; then
                cat_names+=("$current_cat")
                cat_data+=("$current_lines")
            fi
            current_cat="${BASH_REMATCH[1]}"
            current_lines=""
        elif [[ "$line" =~ ^alias[[:space:]]+([^=]+)=(.+)$ ]]; then
            local name="${BASH_REMATCH[1]}"
            name="${name%" "}"
            local raw="${BASH_REMATCH[2]}"
            local display
            if [[ "$raw" =~ \'[[:space:]]+#[[:space:]](.+)$ ]] || [[ "$raw" =~ \"[[:space:]]+#[[:space:]](.+)$ ]]; then
                display="${BASH_REMATCH[1]}"
            else
                display="${raw#\'}" ; display="${display%\'}"
                display="${display#\"}" ; display="${display%\"}"
            fi
            if [[ -n "$current_lines" ]]; then
                current_lines+=$'\n'
            fi
            current_lines+="${name}"$'\t'"${display}"
        fi
    done

    if [[ -n "$current_cat" && -n "$current_lines" ]]; then
        cat_names+=("$current_cat")
        cat_data+=("$current_lines")
    fi

    local -a matched=()
    local i
    for i in "${!cat_names[@]}"; do
        local cat_lower="${cat_names[$i],,}"
        if [[ -z "$filter" ]] || [[ "$cat_lower" == "${filter}"* ]]; then
            matched+=("$i")
        fi
    done

    if [[ ${#matched[@]} -eq 0 ]]; then
        if [[ ${#cat_names[@]} -eq 0 ]]; then
            warn "No aliases defined yet in $USER_ALIASES_FILE"
        else
            err "No category found for '$filter'"
        fi
        exit 1
    fi

    local show_title=true
    if [[ ${#matched[@]} -eq 1 ]]; then
        show_title=false
    fi

    for i in "${matched[@]}"; do
        if $show_title; then
            echo -e "${GREEN}### ${cat_names[$i]}${NC}"
        fi
        while IFS=$'\t' read -r name value; do
            echo -e "  ${BLUE}${name}${NC} → ${value}"
        done <<< "${cat_data[$i]}"
        if $show_title; then
            echo ""
        fi
    done
}
