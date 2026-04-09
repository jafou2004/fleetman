#!/usr/bin/env bats
# Integration tests for scripts/bin/fleetman (entry point).

load '../test_helper/common'

setup() {
    setup_fixtures
    _VERSION="$(cat "$SCRIPTS_DIR/internal/VERSION")"
    source "$SCRIPTS_DIR/lib/vars.sh"
    export SCRIPTS_DIR="$_REAL_SCRIPTS_DIR"
}

@test "fleetman -v: displays the version and exit 0" {
    run bash "$SCRIPTS_DIR/bin/fleetman" -v
    [ "$status" -eq 0 ]
    [ "$output" = "$APP_NAME $_VERSION" ]
}

@test "fleetman --version: displays the version and exit 0" {
    run bash "$SCRIPTS_DIR/bin/fleetman" --version
    [ "$status" -eq 0 ]
    [ "$output" = "$APP_NAME $_VERSION" ]
}
