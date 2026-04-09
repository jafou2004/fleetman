#!/bin/bash

##
# Runs a command with sudo, using the stored fleet password if available.
# Falls back to an interactive password prompt if no fleet key is found.
#
# Usage: fleetman sudo -- <command> [args...]
#
# Options:
#   -h, --help   Show this help
#
# Examples:
#   fleetman sudo -- systemctl restart docker
#   fleetman sudo -- apt update
##

_LIB="$(dirname "${BASH_SOURCE[0]}")/../lib"
# shellcheck source=scripts/lib/vars.sh
source "$_LIB/vars.sh"
# shellcheck source=scripts/lib/display.sh
source "$_LIB/display.sh"
# shellcheck source=scripts/lib/auth.sh
source "$_LIB/auth.sh"

cmd_sudo() {
    local OPTIND=1
    while getopts ":" _opt "$@"; do
        case "$_opt" in
            :) err "Option -$OPTARG requires an argument"; exit 1 ;;
            \?) err "Unknown option: -$OPTARG"; exit 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    # Consume optional -- separator (standard end-of-options marker;
    # also required by the CLI dispatcher which stops arg scanning at any flag)
    if [[ "${1:-}" == "--" ]]; then
        shift
    fi

    if [[ $# -eq 0 ]]; then
        err "No command provided"
        exit 1
    fi

    ask_password
    # Note: no 2>/dev/null — unlike sudo_run(), we want
    # stderr of the wrapped command to remain visible for the user.
    echo "$PASSWORD" | sudo -S "$@"
}
