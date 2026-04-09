#!/bin/bash

# Display functions — sourced by all scripts.
[[ -n "${_FLEETMAN_DISPLAY_LOADED:-}" ]] && return 0
_FLEETMAN_DISPLAY_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/vars.sh"

# Shortens an FQDN hostname: server1.example.com → server1
short_name() {
    echo "${1%%.*}"
}

# Computes a human-readable title from an FQDN hostname.
# Ex: server1-rec.abc.example.com => "Serveur Server 1 REC"
compute_title() {
    local short env_part name_num base num
    short=$(short_name "$1")
    env_part="${short##*-}"
    name_num="${short%-*}"
    num=$(echo "$name_num" | sed 's/[^0-9]//g')
    base=$(echo "$name_num" | sed 's/[0-9]*$//')
    echo "Serveur ${base^} $num ${env_part^^}" | tr -s ' '
}

# Standardized output functions
ok()      { echo -e "${GREEN}  ✓ $*${NC}"; }
err()     { echo -e "${RED}  ✗ $*${NC}"; }
warn()    { echo -e "${YELLOW}  ⚠ $*${NC}"; }
section() { echo -e "${BLUE}=== $* ===${NC}"; }

# Maps an env color name to its ANSI escape literal.
# Outputs a literal string (e.g. '\033[1;32m') — NOT the actual ESC byte.
# Usage: ENV_FG=$(env_color_ansi <color_name> <fg|bg>)
env_color_ansi() {
    local name="$1" mode="${2:-fg}"
    case "$name" in
        green)  [ "$mode" = bg ] && printf '%s' '\033[37;1;42m' || printf '%s' "${GREEN}" ;;
        yellow) [ "$mode" = bg ] && printf '%s' '\033[30;1;43m' || printf '%s' "${YELLOW}" ;;
        red)    [ "$mode" = bg ] && printf '%s' '\033[37;1;41m' || printf '%s' "${RED}" ;;
        grey)   [ "$mode" = bg ] && printf '%s' '\033[30;1;40m' || printf '%s' "${GREY}" ;;
        blue)   [ "$mode" = bg ] && printf '%s' '\033[37;1;44m' || printf '%s' "${BLUE}" ;;
        purple) [ "$mode" = bg ] && printf '%s' '\033[37;1;45m' || printf '%s' "${PURPLE}" ;;
        cyan)   [ "$mode" = bg ] && printf '%s' '\033[30;1;46m' || printf '%s' "${CYAN}" ;;
        white)  [ "$mode" = bg ] && printf '%s' '\033[30;1;47m' || printf '%s' "${WHITE}" ;;
        black)  [ "$mode" = bg ] && printf '%s' '\033[37;1;48m' || printf '%s' "${WHITE}" ;;
        *)      printf '%s' '\033[0m' ;;
    esac
}
COLOR_NAMES=(green yellow red grey blue purple cyan white black)

# Prints a compact color-coded summary after iterate_servers.
print_summary() {
    local ok_count
    ok_count=$(( success_count - warn_count ))
    local summary=""
    [ "$ok_count" -gt 0 ]      && summary+="${GREEN}${ok_count} ✓${NC}  "
    [ "$warn_count" -gt 0 ]    && summary+="${YELLOW}${warn_count} ⚠${NC}  "
    [ "$failure_count" -gt 0 ] && summary+="${RED}${failure_count} ✗${NC}  "
    echo ""
    [ -n "$summary" ] && echo -e "  ${summary%  }"
}

