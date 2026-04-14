#!/usr/bin/env bats
# Integration tests for fleetman port next

load '../../test_helper/common'

setup() {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    setup_fixtures
    jq '. + {"port_range": {"min": 8000, "max": 9010}}' "$CONFIG_FILE" \
        > "$BATS_TEST_TMPDIR/t.json" && mv "$BATS_TEST_TMPDIR/t.json" "$CONFIG_FILE"
}

@test "fleetman port next -h: displays docblock" {
    run bash "$SCRIPTS_DIR/bin/fleetman" port next -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"port next"* ]]
}

@test "fleetman port next --help: exit 0" {
    run bash "$SCRIPTS_DIR/bin/fleetman" port next --help
    [ "$status" -eq 0 ]
}

@test "fleetman port next -z: unknown option → exit 1" {
    run bash "$SCRIPTS_DIR/bin/fleetman" port next -z
    [ "$status" -eq 1 ]
}

@test "fleetman port next -n 3: returns 3 ports" {
    run bash "$SCRIPTS_DIR/bin/fleetman" port next -n 3
    [ "$status" -eq 0 ]
    count=$(printf '%s\n' "$output" | grep -cE '^\s+[0-9]{4,5}$' || true)
    [ "$count" = "3" ]
}
