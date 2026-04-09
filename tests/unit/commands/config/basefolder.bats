#!/usr/bin/env bats
# Unit tests for scripts/commands/config/basefolder.sh

load '../../../test_helper/common'

setup() {
    load_common
    source "$SCRIPTS_DIR/commands/config/basefolder.sh"
    prompt_sync_confirm() { :; }
}

# ── Unknown option ────────────────────────────────────────────────────────────

@test "cmd_config_basefolder: unknown option → exit 1 + 'Unknown option'" {
    run cmd_config_basefolder -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

# ── config.json absent ────────────────────────────────────────────────────────

@test "cmd_config_basefolder: config.json absent → exit 1 + ⚠" {
    rm -f "$CONFIG_FILE"
    run cmd_config_basefolder <<< ''
    [ "$status" -eq 1 ]
    [[ "$output" == *"⚠"* ]]
}

# ── Unchanged value ──────────────────────────────────────────────────────────

@test "cmd_config_basefolder: Enter without current value → 'Unchanged'" {
    jq 'del(.base_folder)' "$CONFIG_FILE" > "$BATS_TEST_TMPDIR/t.json" \
        && mv "$BATS_TEST_TMPDIR/t.json" "$CONFIG_FILE"
    run cmd_config_basefolder <<< ''
    [ "$status" -eq 0 ]
    [[ "$output" == *"Unchanged"* ]]
}

@test "cmd_config_basefolder: Enter with current value → 'Unchanged'" {
    local updated
    updated=$(jq --arg v "$BATS_TEST_TMPDIR" '.base_folder = $v' "$CONFIG_FILE")
    printf '%s\n' "$updated" > "$CONFIG_FILE"
    run cmd_config_basefolder <<< ''
    [ "$status" -eq 0 ]
    [[ "$output" == *"Unchanged"* ]]
}

# ── Update ────────────────────────────────────────────────────────────────────

@test "cmd_config_basefolder: valid path → written to config.json" {
    run cmd_config_basefolder <<< "$BATS_TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.base_folder' "$CONFIG_FILE")" = "$BATS_TEST_TMPDIR" ]
}

@test "cmd_config_basefolder: valid path → displays 'base_folder: ... → ...'" {
    run cmd_config_basefolder <<< "$BATS_TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"base_folder:"*"→"* ]]
}

@test "cmd_config_basefolder: valid path → prompt_sync_confirm called" {
    local call_file="$BATS_TEST_TMPDIR/sync_calls"
    prompt_sync_confirm() { echo "SYNC" >> "$call_file"; }
    run cmd_config_basefolder <<< "$BATS_TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [ -f "$call_file" ]
}

@test "cmd_config_basefolder: unchanged value → prompt_sync_confirm not called" {
    local updated
    updated=$(jq --arg v "$BATS_TEST_TMPDIR" '.base_folder = $v' "$CONFIG_FILE")
    printf '%s\n' "$updated" > "$CONFIG_FILE"
    local call_file="$BATS_TEST_TMPDIR/sync_calls"
    prompt_sync_confirm() { echo "SYNC" >> "$call_file"; }
    run cmd_config_basefolder <<< ''
    [ "$status" -eq 0 ]
    [ ! -f "$call_file" ]
}

# ── Disable ───────────────────────────────────────────────────────────────────

@test "cmd_config_basefolder: '-' → removes base_folder from config.json" {
    local updated
    updated=$(jq --arg v "$BATS_TEST_TMPDIR" '.base_folder = $v' "$CONFIG_FILE")
    printf '%s\n' "$updated" > "$CONFIG_FILE"
    run cmd_config_basefolder <<< '-'
    [ "$status" -eq 0 ]
    run jq 'has("base_folder")' "$CONFIG_FILE"
    [ "$output" = "false" ]
}

# ── Validation ────────────────────────────────────────────────────────────────

@test "cmd_config_basefolder: non-existent path → exit 1 + 'does not exist'" {
    run cmd_config_basefolder <<< '/nonexistent_xyz_12345'
    [ "$status" -eq 1 ]
    [[ "$output" == *"does not exist"* ]]
}
