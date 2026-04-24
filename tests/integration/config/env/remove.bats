#!/usr/bin/env bats
# Integration tests for scripts/commands/config/env/remove.sh

load '../../../test_helper/common'

setup() {
    setup_fixtures
}

@test "fleetman config env remove -h: exit 0 + Usage" {
    run bash "$SCRIPTS_DIR/bin/fleetman" config env remove -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"remove"* ]]
}

@test "fleetman config env remove --help: exit 0 + Usage" {
    run bash "$SCRIPTS_DIR/bin/fleetman" config env remove --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "fleetman config env remove -z: exit 1 + Unknown option" {
    run bash "$SCRIPTS_DIR/bin/fleetman" config env remove -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "fleetman config env remove: missing config.json → exit 1 + ⚠" {
    rm -f "$CONFIG_FILE"
    run bash "$SCRIPTS_DIR/bin/fleetman" config env remove
    [ "$status" -eq 1 ]
    [[ "$output" == *"⚠"* ]]
}

@test "fleetman config env remove -e invalid: exit 1" {
    run bash "$SCRIPTS_DIR/bin/fleetman" config env remove -e nosuchenv
    [ "$status" -eq 1 ]
    [[ "$output" == *"nosuchenv"* ]]
}
