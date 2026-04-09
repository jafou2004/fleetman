#!/bin/bash

##
# @menu Environments
# @order 5
#
# Manage fleet environments (env_colors and servers entries).
#
# Usage: fleetman config env [subcommand]
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

_CMD_DIR="$(dirname "${BASH_SOURCE[0]}")/env"

cmd_config_env() {
    check_config_file

    section "Configuration — environments"

    local _COMMANDS_DIR
    _COMMANDS_DIR="$(dirname "$(dirname "${BASH_SOURCE[0]}")")"

    _cli_dispatch_submenu "$_CMD_DIR" "$_COMMANDS_DIR"
}
