#!/usr/bin/env bats
# Tests unitaires pour scripts/commands/config/podsignore.sh

load '../../../test_helper/common'

setup() {
    load_common
    source "$SCRIPTS_DIR/commands/config/podsignore.sh"

    # select_menu_multi: mock — no items selected by default
    select_menu_multi() { SELECTED_INDICES=(); }

    # prompt_response: returns "" by default (immediately exits the add loop)
    prompt_response() { echo "${_PROMPT_MOCK_VALUE:-$2}"; }

    # prompt_sync_confirm: mock — does nothing by default
    prompt_sync_confirm() { :; }
}

# ── Guard: config.json absent ─────────────────────────────────────────────────

@test "cmd_config_podsignore: config.json absent → exit 1 + ⚠" {
    rm -f "$CONFIG_FILE"
    run cmd_config_podsignore
    [ "$status" -eq 1 ]
    [[ "$output" == *"⚠"* ]]
}

# ── Display ───────────────────────────────────────────────────────────────────

@test "cmd_config_podsignore: empty list → warn 'No pattern configured'" {
    jq 'del(.pods_ignore)' "$CONFIG_FILE" > "$BATS_TEST_TMPDIR/tmp.json" \
        && mv "$BATS_TEST_TMPDIR/tmp.json" "$CONFIG_FILE"
    run cmd_config_podsignore
    [ "$status" -eq 0 ]
    [[ "$output" == *"⚠"* ]]
    [[ "$output" == *"No pattern"* ]]
}

@test "cmd_config_podsignore: existing patterns → displays with ✓" {
    jq '.pods_ignore = ["^tmp-", "-test$"]' "$CONFIG_FILE" > "$BATS_TEST_TMPDIR/tmp.json" \
        && mv "$BATS_TEST_TMPDIR/tmp.json" "$CONFIG_FILE"
    # stdin: n for the remove prompt
    run cmd_config_podsignore <<< $'n\n'
    [ "$status" -eq 0 ]
    [[ "$output" == *"✓"* ]]
    [[ "$output" == *"^tmp-"* ]]
    [[ "$output" == *"-test"* ]]
}

# ── Remove: guard si liste vide ───────────────────────────────────────────────

@test "cmd_config_podsignore: empty list → select_menu_multi not called" {
    jq 'del(.pods_ignore)' "$CONFIG_FILE" > "$BATS_TEST_TMPDIR/tmp.json" \
        && mv "$BATS_TEST_TMPDIR/tmp.json" "$CONFIG_FILE"
    local call_file="$BATS_TEST_TMPDIR/smm_calls"
    select_menu_multi() { echo "X" >> "$call_file"; SELECTED_INDICES=(); }
    run cmd_config_podsignore
    [ ! -f "$call_file" ]
}

# ── Remove ────────────────────────────────────────────────────────────────────

@test "cmd_config_podsignore: removal of pattern at index 0" {
    jq '.pods_ignore = ["^tmp-", "-test$"]' "$CONFIG_FILE" > "$BATS_TEST_TMPDIR/tmp.json" \
        && mv "$BATS_TEST_TMPDIR/tmp.json" "$CONFIG_FILE"
    select_menu_multi() { SELECTED_INDICES=(0); }
    # stdin: y pour le remove prompt
    run cmd_config_podsignore <<< $'y\n'
    [ "$status" -eq 0 ]
    local remaining
    remaining=$(jq -r '.pods_ignore[]' "$CONFIG_FILE")
    [[ "$remaining" != *"^tmp-"* ]]
    [[ "$remaining" == *"-test"* ]]
}

# ── Add: validation PCRE ──────────────────────────────────────────────────────

@test "cmd_config_podsignore: add invalid PCRE pattern → err + exit 1" {
    jq 'del(.pods_ignore)' "$CONFIG_FILE" > "$BATS_TEST_TMPDIR/tmp.json" \
        && mv "$BATS_TEST_TMPDIR/tmp.json" "$CONFIG_FILE"
    # Sequence: "[invalid" (invalid) then "" (end)
    printf '%s\n' '[invalid' '' > "$BATS_TEST_TMPDIR/pr_seq"
    echo "0" > "$BATS_TEST_TMPDIR/pr_idx"
    prompt_response() {
        local _idx
        _idx=$(cat "$BATS_TEST_TMPDIR/pr_idx")
        _idx=$(( _idx + 1 ))
        echo "$_idx" > "$BATS_TEST_TMPDIR/pr_idx"
        sed -n "${_idx}p" "$BATS_TEST_TMPDIR/pr_seq"
    }
    run cmd_config_podsignore
    [ "$status" -eq 1 ]
    [[ "$output" == *"✗"* ]]
    [[ "$output" == *"invalid"* ]]
}

# ── Add: doublon ──────────────────────────────────────────────────────────────

@test "cmd_config_podsignore: add duplicate → warn + config unchanged" {
    jq '.pods_ignore = ["^tmp-"]' "$CONFIG_FILE" > "$BATS_TEST_TMPDIR/tmp.json" \
        && mv "$BATS_TEST_TMPDIR/tmp.json" "$CONFIG_FILE"
    local before
    before=$(md5sum "$CONFIG_FILE" | cut -d' ' -f1)
    # Sequence: "^tmp-" (duplicate) then "" (end)
    printf '%s\n' '^tmp-' '' > "$BATS_TEST_TMPDIR/pr_seq"
    echo "0" > "$BATS_TEST_TMPDIR/pr_idx"
    prompt_response() {
        local _idx
        _idx=$(cat "$BATS_TEST_TMPDIR/pr_idx")
        _idx=$(( _idx + 1 ))
        echo "$_idx" > "$BATS_TEST_TMPDIR/pr_idx"
        sed -n "${_idx}p" "$BATS_TEST_TMPDIR/pr_seq"
    }
    # stdin: n for the remove prompt (non-empty list)
    run cmd_config_podsignore <<< $'n\n'
    [ "$status" -eq 0 ]
    [[ "$output" == *"⚠"* ]]
    [[ "$output" == *"already present"* ]]
    local after
    after=$(md5sum "$CONFIG_FILE" | cut -d' ' -f1)
    [ "$before" == "$after" ]
}

# ── Add: pattern valide ───────────────────────────────────────────────────────

@test "cmd_config_podsignore: add valid pattern → added in config.json" {
    jq 'del(.pods_ignore)' "$CONFIG_FILE" > "$BATS_TEST_TMPDIR/tmp.json" \
        && mv "$BATS_TEST_TMPDIR/tmp.json" "$CONFIG_FILE"
    # Sequence: "^new-" then "" (end)
    printf '%s\n' '^new-' '' > "$BATS_TEST_TMPDIR/pr_seq"
    echo "0" > "$BATS_TEST_TMPDIR/pr_idx"
    prompt_response() {
        local _idx
        _idx=$(cat "$BATS_TEST_TMPDIR/pr_idx")
        _idx=$(( _idx + 1 ))
        echo "$_idx" > "$BATS_TEST_TMPDIR/pr_idx"
        sed -n "${_idx}p" "$BATS_TEST_TMPDIR/pr_seq"
    }
    run cmd_config_podsignore
    [ "$status" -eq 0 ]
    local patterns
    patterns=$(jq -r '.pods_ignore[]' "$CONFIG_FILE")
    [[ "$patterns" == *"^new-"* ]]
}

# ── Add: preview pods.json ────────────────────────────────────────────────────

@test "cmd_config_podsignore: add with match in pods.json → displays matched pods" {
    # pods.json fixture contains "api" and "worker"
    jq 'del(.pods_ignore)' "$CONFIG_FILE" > "$BATS_TEST_TMPDIR/tmp.json" \
        && mv "$BATS_TEST_TMPDIR/tmp.json" "$CONFIG_FILE"
    # Pattern "^api" matches "api" in the fixture pods.json
    printf '%s\n' '^api' '' > "$BATS_TEST_TMPDIR/pr_seq"
    echo "0" > "$BATS_TEST_TMPDIR/pr_idx"
    prompt_response() {
        local _idx
        _idx=$(cat "$BATS_TEST_TMPDIR/pr_idx")
        _idx=$(( _idx + 1 ))
        echo "$_idx" > "$BATS_TEST_TMPDIR/pr_idx"
        sed -n "${_idx}p" "$BATS_TEST_TMPDIR/pr_seq"
    }
    run cmd_config_podsignore
    [ "$status" -eq 0 ]
    [[ "$output" == *"api"* ]]
    [[ "$output" == *"ignored"* ]]
}

@test "cmd_config_podsignore: add without match in pods.json → 'No pod'" {
    jq 'del(.pods_ignore)' "$CONFIG_FILE" > "$BATS_TEST_TMPDIR/tmp.json" \
        && mv "$BATS_TEST_TMPDIR/tmp.json" "$CONFIG_FILE"
    # Pattern "^zzz" matches nothing in the fixture
    printf '%s\n' '^zzz' '' > "$BATS_TEST_TMPDIR/pr_seq"
    echo "0" > "$BATS_TEST_TMPDIR/pr_idx"
    prompt_response() {
        local _idx
        _idx=$(cat "$BATS_TEST_TMPDIR/pr_idx")
        _idx=$(( _idx + 1 ))
        echo "$_idx" > "$BATS_TEST_TMPDIR/pr_idx"
        sed -n "${_idx}p" "$BATS_TEST_TMPDIR/pr_seq"
    }
    run cmd_config_podsignore
    [ "$status" -eq 0 ]
    [[ "$output" == *"No pod"* ]]
}

@test "cmd_config_podsignore: pods.json absent → pas de preview, pas d'erreur" {
    jq 'del(.pods_ignore)' "$CONFIG_FILE" > "$BATS_TEST_TMPDIR/tmp.json" \
        && mv "$BATS_TEST_TMPDIR/tmp.json" "$CONFIG_FILE"
    rm -f "$PODS_FILE"
    printf '%s\n' '^tmp-' '' > "$BATS_TEST_TMPDIR/pr_seq"
    echo "0" > "$BATS_TEST_TMPDIR/pr_idx"
    prompt_response() {
        local _idx
        _idx=$(cat "$BATS_TEST_TMPDIR/pr_idx")
        _idx=$(( _idx + 1 ))
        echo "$_idx" > "$BATS_TEST_TMPDIR/pr_idx"
        sed -n "${_idx}p" "$BATS_TEST_TMPDIR/pr_seq"
    }
    run cmd_config_podsignore
    [ "$status" -eq 0 ]
    [[ "$output" != *"✗"* ]]
}

# ── Sync confirm ──────────────────────────────────────────────────────────────

@test "cmd_config_podsignore: no change → prompt_sync_confirm not called" {
    jq 'del(.pods_ignore)' "$CONFIG_FILE" > "$BATS_TEST_TMPDIR/tmp.json" \
        && mv "$BATS_TEST_TMPDIR/tmp.json" "$CONFIG_FILE"
    local sync_file="$BATS_TEST_TMPDIR/sync_calls"
    prompt_sync_confirm() { echo "SYNC" >> "$sync_file"; }
    run cmd_config_podsignore
    [ ! -f "$sync_file" ]
}

@test "cmd_config_podsignore: add pattern → prompt_sync_confirm called" {
    jq 'del(.pods_ignore)' "$CONFIG_FILE" > "$BATS_TEST_TMPDIR/tmp.json" \
        && mv "$BATS_TEST_TMPDIR/tmp.json" "$CONFIG_FILE"
    local sync_file="$BATS_TEST_TMPDIR/sync_calls"
    prompt_sync_confirm() { echo "SYNC" >> "$sync_file"; }
    printf '%s\n' '^new-' '' > "$BATS_TEST_TMPDIR/pr_seq"
    echo "0" > "$BATS_TEST_TMPDIR/pr_idx"
    prompt_response() {
        local _idx
        _idx=$(cat "$BATS_TEST_TMPDIR/pr_idx")
        _idx=$(( _idx + 1 ))
        echo "$_idx" > "$BATS_TEST_TMPDIR/pr_idx"
        sed -n "${_idx}p" "$BATS_TEST_TMPDIR/pr_seq"
    }
    run cmd_config_podsignore
    [ "$status" -eq 0 ]
    [ -f "$sync_file" ]
}
