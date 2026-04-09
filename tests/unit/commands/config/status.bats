#!/usr/bin/env bats
# Unit tests for scripts/commands/config/status.sh

load '../../../test_helper/common'

setup() {
    load_common
    source "$SCRIPTS_DIR/commands/config/status.sh"

    # select_menu_multi: mock — no items selected by default
    select_menu_multi() { SELECTED_INDICES=(); }

    # prompt_response: if _PROMPT_MOCK_VALUE is set, return it; otherwise return $2 (simulates Enter)
    prompt_response() { echo "${_PROMPT_MOCK_VALUE:-$2}"; }

    # prompt_sync_confirm: mock — do nothing by default
    prompt_sync_confirm() { :; }
}

# ── Guard: config.json absent ─────────────────────────────────────────────────

@test "cmd_config_status: config.json absent → exit 1 + ⚠" {
    rm -f "$CONFIG_FILE"
    run cmd_config_status
    [ "$status" -eq 1 ]
    [[ "$output" == *"⚠"* ]]
}

# ── Display: containers list ──────────────────────────────────────────────────

@test "cmd_config_status: empty list → warn 'No container tracked'" {
    jq 'del(.status_checks.containers)' "$CONFIG_FILE" > "$BATS_TEST_TMPDIR/tmp.json" \
        && mv "$BATS_TEST_TMPDIR/tmp.json" "$CONFIG_FILE"
    run cmd_config_status
    [[ "$output" == *"⚠"* ]]
    [[ "$output" == *"No container"* ]]
}

@test "cmd_config_status: non-empty list → ok for each container" {
    run cmd_config_status
    [[ "$output" == *"nginx"* ]]
    [[ "$output" == *"app"* ]]
    [[ "$output" == *"✓"* ]]
}

@test "cmd_config_status: empty list → select_menu_multi not called" {
    jq 'del(.status_checks.containers)' "$CONFIG_FILE" > "$BATS_TEST_TMPDIR/tmp.json" \
        && mv "$BATS_TEST_TMPDIR/tmp.json" "$CONFIG_FILE"
    local call_file="$BATS_TEST_TMPDIR/smm_calls"
    select_menu_multi() { echo "X" >> "$call_file"; SELECTED_INDICES=(); }
    run cmd_config_status
    [ ! -f "$call_file" ]
}

# ── Remove step ───────────────────────────────────────────────────────────────

@test "cmd_config_status: removal of a container (index 0)" {
    # select_menu_multi selects index 0 (nginx)
    select_menu_multi() { SELECTED_INDICES=(0); }
    # stdin: remove=y, then the function ends (no more reads yet)
    run cmd_config_status <<< $'y\n'
    [ "$status" -eq 0 ]
    local remaining
    remaining=$(jq -r '.status_checks.containers[]' "$CONFIG_FILE")
    [[ "$remaining" != *"nginx"* ]]
    [[ "$remaining" == *"app"* ]]
}

@test "cmd_config_status: removal of all containers" {
    # select_menu_multi selects indexes 0 and 1
    select_menu_multi() { SELECTED_INDICES=(0 1); }
    run cmd_config_status <<< $'y\n'
    [ "$status" -eq 0 ]
    local count
    count=$(jq '.status_checks.containers | length' "$CONFIG_FILE")
    [ "$count" -eq 0 ]
}

# ── Add step ──────────────────────────────────────────────────────────────────

@test "cmd_config_status: adding containers → present in config.json" {
    # stdin: remove=n, add="nginx2 app2"
    run cmd_config_status <<< $'n\nnginx2 app2\n'
    [ "$status" -eq 0 ]
    local containers
    containers=$(jq -r '.status_checks.containers[]' "$CONFIG_FILE")
    [[ "$containers" == *"nginx2"* ]]
    [[ "$containers" == *"app2"* ]]
}

@test "cmd_config_status: adding duplicate → warn + file unchanged" {
    # "nginx" is already in the fixture
    local before
    before=$(md5sum "$CONFIG_FILE" | cut -d' ' -f1)
    run cmd_config_status <<< $'n\nnginx\n'
    [ "$status" -eq 0 ]
    [[ "$output" == *"⚠"* ]]
    [[ "$output" == *"ignored"* ]]
    local after
    after=$(md5sum "$CONFIG_FILE" | cut -d' ' -f1)
    [ "$before" == "$after" ]
}

# ── WUD port step ─────────────────────────────────────────────────────────────

@test "cmd_config_status: WUD unchanged → 'Unchanged', file not modified" {
    # _PROMPT_MOCK_VALUE unset → mock returns $2 = current value (3000)
    # Fixture: wud_port=3000 → new_wud="3000" == current_wud="3000" → unchanged
    local before
    before=$(md5sum "$CONFIG_FILE" | cut -d' ' -f1)
    run cmd_config_status <<< $'n\n\n'
    [ "$status" -eq 0 ]
    [[ "$output" == *"Unchanged"* ]]
    local after
    after=$(md5sum "$CONFIG_FILE" | cut -d' ' -f1)
    [ "$before" == "$after" ]
}

@test "cmd_config_status: WUD changed → updated in config.json" {
    # Fixture: wud_port=3000; mock returns 8080 → changed
    _PROMPT_MOCK_VALUE=8080
    run cmd_config_status <<< $'n\n\n'
    [ "$status" -eq 0 ]
    local wud
    wud=$(jq '.status_checks.wud_port' "$CONFIG_FILE")
    [ "$wud" -eq 8080 ]
}

@test "cmd_config_status: WUD set to 0 → key present at 0" {
    # 0 means "disabled" but the key is NOT deleted
    _PROMPT_MOCK_VALUE=0
    run cmd_config_status <<< $'n\n\n'
    [ "$status" -eq 0 ]
    local wud
    wud=$(jq '.status_checks.wud_port' "$CONFIG_FILE")
    [ "$wud" -eq 0 ]
}

@test "cmd_config_status: WUD non-entier → exit 1 + 'Invalid value'" {
    _PROMPT_MOCK_VALUE=abc
    run cmd_config_status <<< $'n\n\n'
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid value"* ]]
}

# ── Sync step ─────────────────────────────────────────────────────────────────

@test "cmd_config_status: no changes → prompt_sync_confirm not called" {
    # No changes: _PROMPT_MOCK_VALUE unset (WUD unchanged), n for remove, empty add
    local sync_file="$BATS_TEST_TMPDIR/sync_calls"
    prompt_sync_confirm() { echo "SYNC" >> "$sync_file"; }
    run cmd_config_status <<< $'n\n\n'
    [ ! -f "$sync_file" ]
}

@test "cmd_config_status: WUD changed → prompt_sync_confirm called" {
    # Change WUD → changed=true → sync confirm called
    local sync_file="$BATS_TEST_TMPDIR/sync_calls"
    prompt_sync_confirm() { echo "SYNC" >> "$sync_file"; }
    _PROMPT_MOCK_VALUE=8080
    run cmd_config_status <<< $'n\n\n'
    [ "$status" -eq 0 ]
    [ -f "$sync_file" ]
    [[ "$(cat "$sync_file")" == *"SYNC"* ]]
}

@test "cmd_config_status: adding container → prompt_sync_confirm called" {
    # Add a container → changed=true → sync confirm called
    local sync_file="$BATS_TEST_TMPDIR/sync_calls"
    prompt_sync_confirm() { echo "SYNC" >> "$sync_file"; }
    run cmd_config_status <<< $'n\nnewcontainer\n'
    [ "$status" -eq 0 ]
    [ -f "$sync_file" ]
}
