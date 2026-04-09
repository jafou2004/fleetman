#!/usr/bin/env bats
# Unit tests for scripts/commands/config/env/color.sh

load '../../../../test_helper/common'

setup() {
    load_common
    source "$SCRIPTS_DIR/commands/config/env/color.sh"
    select_menu() { SELECTED_IDX=0; }
    # prompt_sync_confirm: no-op mock by default
    prompt_sync_confirm() { :; }
}

# ── check_config_file ──────────────────────────────────────────────────────────

@test "cmd_config_env_color: config.json absent → exit 1 + ⚠" {
    rm -f "$CONFIG_FILE"
    run cmd_config_env_color
    [ "$status" -eq 1 ]
    [[ "$output" == *"⚠"* ]]
}

# ── Unknown option ─────────────────────────────────────────────────────────────

@test "cmd_config_env_color: unknown option → exit 1 + 'Unknown option'" {
    run cmd_config_env_color -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

# ── Menu 1 labels ─────────────────────────────────────────────────────────────

@test "cmd_config_env_color: menu 1 displays env names (dev, test, prod)" {
    _call_count=0
    select_menu() {
        _call_count=$(( _call_count + 1 ))
        SELECTED_IDX=0
        if [ "$_call_count" -eq 1 ]; then
            local -n _lbl=$1
            for lbl in "${_lbl[@]}"; do echo "LABEL:$lbl"; done
        fi
    }
    run cmd_config_env_color
    [[ "$output" == *"dev"* ]]
    [[ "$output" == *"test"* ]]
    [[ "$output" == *"prod"* ]]
}

# ── Successful color change ────────────────────────────────────────────────────

@test "cmd_config_env_color: env 0 (dev) color 0 (green) selected → env_colors.dev = green" {
    run cmd_config_env_color
    [ "$status" -eq 0 ]
    [ "$(jq -r '.env_colors.dev' "$CONFIG_FILE")" = "green" ]
}

@test "cmd_config_env_color: env 2 (test) color 2 (red) selected → env_colors.test = red" {
    # jq keys[] sorts alphabetically: dev=0, prod=1, test=2
    _call_count=0
    select_menu() {
        _call_count=$(( _call_count + 1 ))
        if [ "$_call_count" -eq 1 ]; then
            SELECTED_IDX=2   # test (alphabetical index)
        else
            SELECTED_IDX=2   # red (COLOR_NAMES[2])
        fi
    }
    run cmd_config_env_color
    [ "$status" -eq 0 ]
    [ "$(jq -r '.env_colors.test' "$CONFIG_FILE")" = "red" ]
}

@test "cmd_config_env_color: ok message contains env and color" {
    run cmd_config_env_color
    [ "$status" -eq 0 ]
    [[ "$output" == *"dev"* ]]
    [[ "$output" == *"green"* ]]
}

# ── Current color preselection ────────────────────────────────────────────────

@test "cmd_config_env_color: color preselection — test env (yellow = index 1)" {
    # jq keys[] sorts alphabetically: dev=0, prod=1, test=2
    # test → yellow = COLOR_NAMES[1] → expected current_idx = 1
    _call_count=0
    select_menu() {
        _call_count=$(( _call_count + 1 ))
        if [ "$_call_count" -eq 1 ]; then
            SELECTED_IDX=2   # selects "test" (alphabetical index)
        else
            echo "INITIAL_IDX:${2:-0}"
            SELECTED_IDX="${2:-0}"
        fi
    }
    run cmd_config_env_color
    [ "$status" -eq 0 ]
    [[ "$output" == *"INITIAL_IDX:1"* ]]
}

# ── Unchanged color ───────────────────────────────────────────────────────────

@test "cmd_config_env_color: color unchanged → 'Unchanged', config.json not modified, sync not called" {
    # default mock: SELECTED_IDX=0 for both menus → dev (idx 0) + green (idx 0)
    # dev already has green in fixture → unchanged
    local before
    before=$(jq -r '.env_colors.dev' "$CONFIG_FILE")
    local call_file="$BATS_TEST_TMPDIR/sync_calls"
    prompt_sync_confirm() { echo "SYNC" >> "$call_file"; }
    run cmd_config_env_color
    [ "$status" -eq 0 ]
    [[ "$output" == *"Unchanged"* ]]
    [[ "$output" == *"dev"* ]]
    [[ "$output" == *"green"* ]]
    [ "$(jq -r '.env_colors.dev' "$CONFIG_FILE")" = "$before" ]
    [ ! -f "$call_file" ]
}

# ── Sync prompt ───────────────────────────────────────────────────────────────

@test "cmd_config_env_color: color changed → prompt_sync_confirm called" {
    # dev→red: color changed (green→red)
    _call_count=0
    select_menu() {
        _call_count=$(( _call_count + 1 ))
        if [ "$_call_count" -eq 1 ]; then SELECTED_IDX=0; else SELECTED_IDX=2; fi
    }
    local call_file="$BATS_TEST_TMPDIR/sync_calls"
    prompt_sync_confirm() { echo "SYNC" >> "$call_file"; }
    run cmd_config_env_color
    [ "$status" -eq 0 ]
    [ -f "$call_file" ]
}
