#!/bin/bash

##
# Manage Docker Compose pods across the fleet.
#
# Usage: fleetman pod [subcommand] [options]
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

_CMD_DIR="$(dirname "${BASH_SOURCE[0]}")/pod"

cmd_pod() {
    check_config_file

    section "Pod"

    local _COMMANDS_DIR
    _COMMANDS_DIR="$(dirname "${BASH_SOURCE[0]}")"

    _cli_dispatch_submenu "$_CMD_DIR" "$_COMMANDS_DIR"
}
