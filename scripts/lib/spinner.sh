#!/bin/bash

# Spinner helpers — animated feedback during per-server operations.
[[ -n "${_FLEETMAN_SPINNER_LOADED:-}" ]] && return 0
_FLEETMAN_SPINNER_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/vars.sh"
source "$(dirname "${BASH_SOURCE[0]}")/display.sh"

# Prints a server name on the current line and starts an animated spinner.
# Sets global _SPIN_PID.
# Usage: _spin_start <short_name>
_spin_start() {
    local short="$1"
    local -a SF=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    printf "  %-22s  %s" "$short" "${SF[0]}"
    (
        local i=0
        while true; do
            i=$(( (i + 1) % 10 ))
            printf "\r  %-22s  %s" "$short" "${SF[$i]}"
            sleep 0.12
        done
    ) &
    _SPIN_PID=$!
}

# Stops the spinner and overwrites the line with a colored result.
# Usage: _spin_stop <short_name> <ok|warn|err> <detail>
_spin_stop() {
    local short="$1" status="$2" detail="$3"
    kill "$_SPIN_PID" 2>/dev/null
    wait "$_SPIN_PID" 2>/dev/null
    printf "\r\033[K"
    case "$status" in
        ok)   echo -e "  ${GREEN}✓${NC}  $(printf '%-22s' "$short")  $detail" ;;
        warn) echo -e "  ${YELLOW}⚠${NC}  $(printf '%-22s' "$short")  $detail" ;;
        err)  echo -e "  ${RED}✗${NC}  $(printf '%-22s' "$short")  $detail" ;;
    esac
}
