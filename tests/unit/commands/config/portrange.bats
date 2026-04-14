#!/usr/bin/env bats
# Unit tests for scripts/commands/config/portrange.sh

load '../../../test_helper/common'

setup() {
    load_common
    source "$SCRIPTS_DIR/commands/config/portrange.sh"
    prompt_sync_confirm() { :; }
}

# ── Unknown option ────────────────────────────────────────────────────────────

@test "cmd_config_portrange: unknown option → exit 1 + 'Unknown option'" {
    run cmd_config_portrange -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

# ── config.json absent ────────────────────────────────────────────────────────

@test "cmd_config_portrange: config.json absent → exit 1 + ⚠" {
    rm -f "$CONFIG_FILE"
    run cmd_config_portrange <<< $'8000\n9000'
    [ "$status" -eq 1 ]
    [[ "$output" == *"⚠"* ]]
}

# ── Validation ────────────────────────────────────────────────────────────────

@test "cmd_config_portrange: non-integer min → exit 1 + 'Invalid'" {
    run cmd_config_portrange <<< $'abc\n9000'
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid"* ]]
}

@test "cmd_config_portrange: min below 1024 → exit 1 + '1024'" {
    run cmd_config_portrange <<< $'80\n9000'
    [ "$status" -eq 1 ]
    [[ "$output" == *"1024"* ]]
}

@test "cmd_config_portrange: max above 65535 → exit 1 + '65535'" {
    run cmd_config_portrange <<< $'8000\n70000'
    [ "$status" -eq 1 ]
    [[ "$output" == *"65535"* ]]
}

@test "cmd_config_portrange: min >= max → exit 1 + 'strictly less'" {
    run cmd_config_portrange <<< $'9000\n8000'
    [ "$status" -eq 1 ]
    [[ "$output" == *"strictly less"* ]]
}

@test "cmd_config_portrange: min == max → exit 1" {
    run cmd_config_portrange <<< $'8000\n8000'
    [ "$status" -eq 1 ]
}

# ── Unchanged ─────────────────────────────────────────────────────────────────

@test "cmd_config_portrange: same values → 'Unchanged', config unchanged" {
    jq '. + {"port_range": {"min": 8000, "max": 9000}}' "$CONFIG_FILE" \
        > "$BATS_TEST_TMPDIR/t.json" && mv "$BATS_TEST_TMPDIR/t.json" "$CONFIG_FILE"
    run cmd_config_portrange <<< $'8000\n9000'
    [ "$status" -eq 0 ]
    [[ "$output" == *"Unchanged"* ]]
}

@test "cmd_config_portrange: same values → prompt_sync_confirm not called" {
    jq '. + {"port_range": {"min": 8000, "max": 9000}}' "$CONFIG_FILE" \
        > "$BATS_TEST_TMPDIR/t.json" && mv "$BATS_TEST_TMPDIR/t.json" "$CONFIG_FILE"
    local call_file="$BATS_TEST_TMPDIR/sync_calls"
    prompt_sync_confirm() { echo "SYNC" >> "$call_file"; }
    run cmd_config_portrange <<< $'8000\n9000'
    [ "$status" -eq 0 ]
    [ ! -f "$call_file" ]
}

# ── Successful update ─────────────────────────────────────────────────────────

@test "cmd_config_portrange: valid values → written to config.json" {
    run cmd_config_portrange <<< $'8000\n9000'
    [ "$status" -eq 0 ]
    [ "$(jq '.port_range.min' "$CONFIG_FILE")" = "8000" ]
    [ "$(jq '.port_range.max' "$CONFIG_FILE")" = "9000" ]
}

@test "cmd_config_portrange: valid values → displays arrow transition" {
    run cmd_config_portrange <<< $'8000\n9000'
    [ "$status" -eq 0 ]
    [[ "$output" == *"→"* ]]
}

@test "cmd_config_portrange: valid values → prompt_sync_confirm called" {
    local call_file="$BATS_TEST_TMPDIR/sync_calls"
    prompt_sync_confirm() { echo "SYNC" >> "$call_file"; }
    run cmd_config_portrange <<< $'8000\n9000'
    [ "$status" -eq 0 ]
    [ -f "$call_file" ]
}

# ── Enter = keep ──────────────────────────────────────────────────────────────

@test "cmd_config_portrange: Enter keeps existing values" {
    jq '. + {"port_range": {"min": 8000, "max": 9000}}' "$CONFIG_FILE" \
        > "$BATS_TEST_TMPDIR/t.json" && mv "$BATS_TEST_TMPDIR/t.json" "$CONFIG_FILE"
    run cmd_config_portrange <<< $'\n\n'
    [ "$status" -eq 0 ]
    [[ "$output" == *"Unchanged"* ]]
}
