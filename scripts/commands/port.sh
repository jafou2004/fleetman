#!/bin/bash

##
# Manage fleet port assignments.
#
# Usage: fleetman port [subcommand] [options]
#
# Options:
#   -h, --help   Show this help
##

_LIB="$(dirname "${BASH_SOURCE[0]}")/../lib"
# shellcheck source=scripts/lib/vars.sh
source "$_LIB/vars.sh"
# shellcheck source=scripts/lib/display.sh
source "$_LIB/display.sh"
# shellcheck source=scripts/lib/config.sh
source "$_LIB/config.sh"
# shellcheck source=scripts/lib/ui.sh
source "$_LIB/ui.sh"

_CMD_DIR="$(dirname "${BASH_SOURCE[0]}")/port"

cmd_port() {
    check_config_file

    section "Port"

    local _COMMANDS_DIR
    _COMMANDS_DIR="$(dirname "${BASH_SOURCE[0]}")"

    _cli_dispatch_submenu "$_CMD_DIR" "$_COMMANDS_DIR"
}
