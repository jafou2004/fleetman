#!/usr/bin/env bats
# Integration tests for fleetman config pod (dispatcher + docblock)

load '../test_helper/common'

setup() {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    setup_fixtures
}

@test "fleetman config pod -h: displays the docblock" {
    run bash "$SCRIPTS_DIR/bin/fleetman" config pod -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Manages pods"* ]]
    [[ "$output" == *"Usage"* ]]
}

@test "fleetman config pod --help: displays the docblock" {
    run bash "$SCRIPTS_DIR/bin/fleetman" config pod --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "fleetman config pod -z: unknown option → exit 1 + 'Unknown option'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" config pod -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}
