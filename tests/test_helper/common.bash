#!/usr/bin/env bash
# Shared test helpers for unit and integration tests.

# Compute project root robustly: walk up from the test file until we find scripts/
# BATS_TEST_FILENAME is always set by bats to the real absolute path of the test file.
_proj_root="$(dirname "$BATS_TEST_FILENAME")"
while [[ ! -d "$_proj_root/scripts" && "$_proj_root" != "/" ]]; do
    _proj_root="$(dirname "$_proj_root")"
done
_REAL_SCRIPTS_DIR="$_proj_root/scripts"
PROJECT_ROOT="$_proj_root"
export PROJECT_ROOT
FIXTURES_DIR="$_proj_root/tests/fixtures"

# load_common — unit tests: temporary HOME + fixtures + sources all libs.
load_common() {
    export HOME="$BATS_TEST_TMPDIR"
    export CONFIG_FILE="$HOME/config.json"
    export PODS_FILE="$HOME/.data/pods.json"
    mkdir -p "$HOME/.data" "$HOME/.ssh"
    cp "$FIXTURES_DIR/config.json" "$CONFIG_FILE"
    cp "$FIXTURES_DIR/pods.json"   "$PODS_FILE"
    # Create symlink ~/scripts → real scripts/ directory
    # Required because vars.sh defines SCRIPTS_DIR="$HOME/scripts"
    ln -sf "$_REAL_SCRIPTS_DIR" "$HOME/scripts" 2>/dev/null || true
    source "$_REAL_SCRIPTS_DIR/lib/vars.sh"
    source "$_REAL_SCRIPTS_DIR/lib/display.sh"
    source "$_REAL_SCRIPTS_DIR/lib/auth.sh"
    source "$_REAL_SCRIPTS_DIR/lib/config.sh"
    source "$_REAL_SCRIPTS_DIR/lib/ui.sh"
    source "$_REAL_SCRIPTS_DIR/lib/spinner.sh"
    source "$_REAL_SCRIPTS_DIR/lib/iterate.sh"
    source "$_REAL_SCRIPTS_DIR/lib/bashrc.sh"
    # After sourcing vars.sh, SCRIPTS_DIR=$HOME/scripts (symlink to _REAL_SCRIPTS_DIR)
    # Also export SCRIPTS_DIR with the real path for tests that need it
    export SCRIPTS_DIR="$_REAL_SCRIPTS_DIR"
}

# setup_fixtures — integration tests: temporary HOME + fixtures, without sourcing.
setup_fixtures() {
    export HOME="$BATS_TEST_TMPDIR"
    export CONFIG_FILE="$HOME/config.json"
    export PODS_FILE="$HOME/.data/pods.json"
    mkdir -p "$HOME/.data" "$HOME/.ssh"
    cp "$FIXTURES_DIR/config.json" "$CONFIG_FILE"
    cp "$FIXTURES_DIR/pods.json"   "$PODS_FILE"
    export SCRIPTS_DIR="$_REAL_SCRIPTS_DIR"
}
