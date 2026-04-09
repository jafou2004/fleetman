#!/usr/bin/env bats
# Tests unitaires pour scripts/commands/config/env/add.sh

load '../../../../test_helper/common'

setup() {
    load_common
    source "$SCRIPTS_DIR/commands/config/env/add.sh"
    # select_menu requires a TTY — mock: selects index 0 (green).
    select_menu() { SELECTED_IDX=0; }
    # prompt_sync_confirm: mock no-op by default
    prompt_sync_confirm() { :; }
}

# ── check_config_file ──────────────────────────────────────────────────────────

@test "cmd_config_env_add: config.json absent → exit 1 + ⚠" {
    rm -f "$CONFIG_FILE"
    run cmd_config_env_add
    [ "$status" -eq 1 ]
    [[ "$output" == *"⚠"* ]]
}

# ── Option inconnue ────────────────────────────────────────────────────────────

@test "cmd_config_env_add: unknown option → exit 1 + 'Unknown option'" {
    run cmd_config_env_add -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

# ── Display of existing envs ──────────────────────────────────────────────────

@test "cmd_config_env_add: lists existing envs before input" {
    # Fixture has dev, test, prod in .servers
    # We provide 'dev' to trigger the "already exists" error just after input
    run cmd_config_env_add <<< 'dev'
    [[ "$output" == *"dev"* ]]
    [[ "$output" == *"test"* ]]
    [[ "$output" == *"prod"* ]]
}

# ── Uniqueness validation ─────────────────────────────────────────────────────

@test "cmd_config_env_add: env already present → exit 1 + ✗ + 'already exists'" {
    run cmd_config_env_add <<< 'dev'
    [ "$status" -eq 1 ]
    [[ "$output" == *"✗"* ]]
    [[ "$output" == *"already exists"* ]]
}

@test "cmd_config_env_add: env already present (mixed case) → normalizes to lowercase and fails" {
    run cmd_config_env_add <<< 'DEV'
    [ "$status" -eq 1 ]
    [[ "$output" == *"already exists"* ]]
}

# ── Successful addition ───────────────────────────────────────────────────────

@test "cmd_config_env_add: new env → .env_colors and .servers updated" {
    run cmd_config_env_add <<< 'staging'
    [ "$status" -eq 0 ]
    [[ "$output" == *"added"* ]]
    [ "$(jq -r '.env_colors.staging' "$CONFIG_FILE")" = "green" ]
    [ "$(jq '.servers.staging' "$CONFIG_FILE")" = "[]" ]
}

@test "cmd_config_env_add: successful addition → displays ok with name and color" {
    run cmd_config_env_add <<< 'staging'
    [ "$status" -eq 0 ]
    [[ "$output" == *"staging"* ]]
    [[ "$output" == *"green"* ]]
}

# ── Sync prompt ───────────────────────────────────────────────────────────────

@test "cmd_config_env_add: successful addition → prompt_sync_confirm called" {
    local call_file="$BATS_TEST_TMPDIR/sync_calls"
    prompt_sync_confirm() { echo "SYNC" >> "$call_file"; }
    run cmd_config_env_add <<< 'staging'
    [ "$status" -eq 0 ]
    [ -f "$call_file" ]
}

@test "cmd_config_env_add: env exists → prompt_sync_confirm not called" {
    local call_file="$BATS_TEST_TMPDIR/sync_calls"
    prompt_sync_confirm() { echo "SYNC" >> "$call_file"; }
    run cmd_config_env_add <<< 'dev'
    [ "$status" -eq 1 ]
    [ ! -f "$call_file" ]
}
