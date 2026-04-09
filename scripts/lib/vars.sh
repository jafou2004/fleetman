#!/bin/bash

# Global variables — sourced by all lib files and scripts.
[[ -n "${_FLEETMAN_VARS_LOADED:-}" ]] && return 0
_FLEETMAN_VARS_LOADED=1

# ── Application ───────────────────────────────────────────────────────────────

APP_NAME="Fleet Manager"
APP_DESCRIPTION="A CLI tool to manage your fleet of servers and pods."

# ── Colors ────────────────────────────────────────────────────────────────────

GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GREY='\033[1;30m'
BLACK='\033[0;30m'
NC='\033[0m'

# ── Paths ─────────────────────────────────────────────────────────────────────

CONFIG_FILE="$HOME/config.json"

# Data directory and cached file paths
DATA_DIR="$HOME/.data"
FQDN_FILE="$DATA_DIR/fqdn"
GIT_SERVER_FILE="$DATA_DIR/git_server"
PODS_FILE="$DATA_DIR/pods.json"
SERVICES_FILE="$DATA_DIR/services.json"

# Fleet key-based authentication
FLEET_KEY="$HOME/.ssh/fleet_key"
FLEET_PASS_FILE="$HOME/.fleet_pass.enc"

if [[ -s "$FQDN_FILE" ]]; then
    MASTER_HOST=$(< "$FQDN_FILE")
else
    MASTER_HOST=$(hostname -f)
fi
PODS_DIR=$(jq -r '.pods_dir' "$CONFIG_FILE" 2>/dev/null)

# Scripts and user aliases
SCRIPTS_DIR="$HOME/scripts"
USER_ALIASES_FILE="$HOME/.bash_aliases"
