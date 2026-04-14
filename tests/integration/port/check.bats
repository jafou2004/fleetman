#!/usr/bin/env bats
# Integration tests for fleetman port check

load '../../test_helper/common'

setup() {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    setup_fixtures
}

@test "fleetman port check -h: displays docblock" {
    run bash "$SCRIPTS_DIR/bin/fleetman" port check -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"port check"* ]]
}

@test "fleetman port check --help: exit 0" {
    run bash "$SCRIPTS_DIR/bin/fleetman" port check --help
    [ "$status" -eq 0 ]
}

@test "fleetman port check -z: unknown option → exit 1" {
    run bash "$SCRIPTS_DIR/bin/fleetman" port check -z
    [ "$status" -eq 1 ]
}
