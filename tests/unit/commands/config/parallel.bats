#!/usr/bin/env bats
# Unit tests for scripts/commands/config/parallel.sh

load '../../../test_helper/common'

setup() {
    load_common
    source "$SCRIPTS_DIR/commands/config/parallel.sh"
    # prompt_sync_confirm: no-op mock by default
    prompt_sync_confirm() { :; }
}

# ── Invalid options ────────────────────────────────────────────────────────────

@test "cmd_config_parallel: unknown option → exit 1 + 'Unknown option'" {
    run cmd_config_parallel -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

# ── check_config_file ──────────────────────────────────────────────────────────

@test "cmd_config_parallel: config.json absent → exit 1 + warning" {
    rm -f "$CONFIG_FILE"
    run cmd_config_parallel <<< '4'
    [ "$status" -eq 1 ]
    [[ "$output" == *"⚠"* ]]
}

# ── Unchanged value ────────────────────────────────────────────────────────────

@test "cmd_config_parallel: same value → 'Unchanged', config.json not modified" {
    # fixture has parallel=1; confirm with 1
    local before
    before=$(jq '.parallel' "$CONFIG_FILE")
    run cmd_config_parallel <<< '1'
    [ "$status" -eq 0 ]
    [[ "$output" == *"Unchanged"* ]]
    local after
    after=$(jq '.parallel' "$CONFIG_FILE")
    [ "$before" = "$after" ]
}

# ── Successful update ─────────────────────────────────────────────────────────

@test "cmd_config_parallel: valid new value → config.json updated" {
    run cmd_config_parallel <<< '4'
    [ "$status" -eq 0 ]
    [[ "$output" == *"parallel: 1 → 4"* ]]
    [ "$(jq '.parallel' "$CONFIG_FILE")" = "4" ]
}

@test "cmd_config_parallel: new value → prompt_sync_confirm called" {
    local call_file="$BATS_TEST_TMPDIR/sync_calls"
    prompt_sync_confirm() { echo "SYNC" >> "$call_file"; }
    run cmd_config_parallel <<< '4'
    [ "$status" -eq 0 ]
    [ -f "$call_file" ]
}

@test "cmd_config_parallel: unchanged value → prompt_sync_confirm not called" {
    local call_file="$BATS_TEST_TMPDIR/sync_calls"
    prompt_sync_confirm() { echo "SYNC" >> "$call_file"; }
    run cmd_config_parallel <<< '1'
    [ "$status" -eq 0 ]
    [ ! -f "$call_file" ]
}

# ── Validation ─────────────────────────────────────────────────────────────────

@test "cmd_config_parallel: value 0 → exit 1 + 'Invalid value'" {
    run cmd_config_parallel <<< '0'
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid value"* ]]
}

@test "cmd_config_parallel: non-integer value → exit 1 + 'Invalid value'" {
    run cmd_config_parallel <<< 'abc'
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid value"* ]]
}

@test "cmd_config_parallel: negative value → exit 1 + 'Invalid value'" {
    run cmd_config_parallel <<< '-2'
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid value"* ]]
}

# ── Missing field in config.json ──────────────────────────────────────────────

@test "cmd_config_parallel: .parallel absent → default 1, update possible" {
    jq 'del(.parallel)' "$CONFIG_FILE" > "$BATS_TEST_TMPDIR/tmp.json" \
        && mv "$BATS_TEST_TMPDIR/tmp.json" "$CONFIG_FILE"
    run cmd_config_parallel <<< '4'
    [ "$status" -eq 0 ]
    [[ "$output" == *"parallel: 1 → 4"* ]]
    [ "$(jq '.parallel' "$CONFIG_FILE")" = "4" ]
}
