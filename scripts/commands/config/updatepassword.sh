#!/bin/bash

##
# @menu Update password
# @order 12
#
# Rotates the fleet SSH/sudo password: re-encrypts ~/.fleet_pass.enc
# and triggers a quick sync to propagate the updated file to all servers.
#
# Usage: fleetman config updatepassword
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
# shellcheck source=scripts/lib/auth.sh
source "$_LIB/auth.sh"

cmd_config_updatepassword() {
    local OPTIND=1
    while getopts ":" _opt "$@"; do
        case "$_opt" in
            \?) err "Unknown option: -$OPTARG"; exit 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    check_config_file

    section "Configuration — update password"

    if [[ ! -f "$FLEET_KEY" ]]; then
        err "Fleet key not found: $FLEET_KEY — run install.sh first"
        exit 1
    fi
    if [[ ! -f "$FLEET_PASS_FILE" ]]; then
        err "Fleet password file not found: $FLEET_PASS_FILE — run install.sh first"
        exit 1
    fi

    prompt_pass_and_encrypt || exit 1

    ok "Password updated"

    bash "$SCRIPTS_DIR/bin/fleetman" sync -q
}
