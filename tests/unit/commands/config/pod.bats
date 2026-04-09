#!/usr/bin/env bats
# Tests unitaires pour scripts/commands/config/pod.sh

load '../../../test_helper/common'

setup() {
    load_common
    source "$SCRIPTS_DIR/commands/config/pod.sh"

    select_menu() { SELECTED_IDX=0; }
    select_menu_multi() { SELECTED_INDICES=(); }
    prompt_response() { echo "${_PROMPT_MOCK_VALUE:-$2}"; }
    prompt_sync_confirm() { :; }
}

# ── Guards ─────────────────────────────────────────────────────────────────────

@test "cmd_config_pod: config.json absent → exit 1 + ⚠" {
    rm -f "$CONFIG_FILE"
    run cmd_config_pod
    [ "$status" -eq 1 ]
    [[ "$output" == *"⚠"* ]]
}

@test "cmd_config_pod: unknown option → exit 1 + 'Unknown option'" {
    run cmd_config_pod -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

# ── Navigation ─────────────────────────────────────────────────────────────────

@test "cmd_config_pod: Quit → return 0" {
    # Fixture has 1 pod "api" → menu: [api(0), "── Add(1)", "Quit(2)"]
    select_menu() { SELECTED_IDX=2; }
    run cmd_config_pod
    [ "$status" -eq 0 ]
}

@test "cmd_config_pod: .pods empty → warn 'No pod configured'" {
    jq '.pods = {}' "$CONFIG_FILE" > "$BATS_TEST_TMPDIR/tmp.json" \
        && mv "$BATS_TEST_TMPDIR/tmp.json" "$CONFIG_FILE"
    # Menu without pods: ["── Add(0)", "Quit(1)"]
    select_menu() { SELECTED_IDX=1; }
    run cmd_config_pod
    [ "$status" -eq 0 ]
    [[ "$output" == *"No pod"* ]]
}

# ── _pod_display_all ───────────────────────────────────────────────────────────

@test "_pod_display_all: displays pods with their counters" {
    run _pod_display_all
    [ "$status" -eq 0 ]
    [[ "$output" == *"api"* ]]
    [[ "$output" == *"env_vars"* ]]
    [[ "$output" == *"env_templates"* ]]
}

@test "_pod_display_all: .pods empty → no output" {
    jq '.pods = {}' "$CONFIG_FILE" > "$BATS_TEST_TMPDIR/tmp.json" \
        && mv "$BATS_TEST_TMPDIR/tmp.json" "$CONFIG_FILE"
    run _pod_display_all
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ── _pod_add ───────────────────────────────────────────────────────────────────

@test "_pod_add: pods.json present → selects unconfigured pod + creates entry" {
    # Fixture: pods.json has "api" and "worker"; .pods only has "api"
    # Available: ["worker"] → SELECTED_IDX=0 → "worker"
    select_menu() { SELECTED_IDX=0; }
    changed=false
    _pod_add
    [ "$(jq -r '.pods | has("worker")' "$CONFIG_FILE")" = "true" ]
    [ "$(jq '.pods.worker.env_vars | length' "$CONFIG_FILE")" -eq 0 ]
    [ "$(jq '.pods.worker.env_templates | length' "$CONFIG_FILE")" -eq 0 ]
}

@test "_pod_add: pods.json present → changed=true" {
    select_menu() { SELECTED_IDX=0; }
    changed=false
    _pod_add
    [ "$changed" = "true" ]
}

@test "_pod_add: all pods already configured → warn + config unchanged" {
    jq '.pods.worker = {"env_vars": [], "env_templates": {}}' "$CONFIG_FILE" \
        > "$BATS_TEST_TMPDIR/tmp.json" && mv "$BATS_TEST_TMPDIR/tmp.json" "$CONFIG_FILE"
    local before
    before=$(md5sum "$CONFIG_FILE" | cut -d' ' -f1)
    run _pod_add
    [ "$status" -eq 0 ]
    [[ "$output" == *"already configured"* ]]
    local after
    after=$(md5sum "$CONFIG_FILE" | cut -d' ' -f1)
    [ "$before" = "$after" ]
}

@test "_pod_add: pods.json absent → free input → pod created" {
    rm -f "$PODS_FILE"
    _PROMPT_MOCK_VALUE="newpod"
    _pod_add
    [ "$(jq -r '.pods | has("newpod")' "$CONFIG_FILE")" = "true" ]
}

@test "_pod_add: pods.json absent + pod already in .pods → warn + config unchanged" {
    rm -f "$PODS_FILE"
    _PROMPT_MOCK_VALUE="api"
    local before
    before=$(md5sum "$CONFIG_FILE" | cut -d' ' -f1)
    run _pod_add
    [ "$status" -eq 0 ]
    [[ "$output" == *"already configured"* ]]
    local after
    after=$(md5sum "$CONFIG_FILE" | cut -d' ' -f1)
    [ "$before" = "$after" ]
}

# ── _pod_remove ────────────────────────────────────────────────────────────────

@test "_pod_remove: confirmed → pod removed from config.json" {
    run _pod_remove "api" <<< "y"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.pods | has("api")' "$CONFIG_FILE")" = "false" ]
}

@test "_pod_remove: cancelled → config unchanged + 'Cancelled'" {
    local before
    before=$(md5sum "$CONFIG_FILE" | cut -d' ' -f1)
    run _pod_remove "api" <<< "n"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cancelled"* ]]
    local after
    after=$(md5sum "$CONFIG_FILE" | cut -d' ' -f1)
    [ "$before" = "$after" ]
}

# ── _pod_manage_envvars ────────────────────────────────────────────────────────

@test "_pod_manage_envvars: displays existing variables" {
    # stdin "n" for the remove prompt
    run _pod_manage_envvars "api" <<< $'n\n'
    [ "$status" -eq 0 ]
    [[ "$output" == *"API_VERSION"* ]]
}

@test "_pod_manage_envvars: env_vars empty → warn 'No variable'" {
    jq '.pods.api.env_vars = []' "$CONFIG_FILE" > "$BATS_TEST_TMPDIR/tmp.json" \
        && mv "$BATS_TEST_TMPDIR/tmp.json" "$CONFIG_FILE"
    run _pod_manage_envvars "api"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No variable"* ]]
}

@test "_pod_manage_envvars: add valid variable → added in config.json" {
    printf '%s\n' 'NEW_VAR' '' > "$BATS_TEST_TMPDIR/pr_seq"
    echo "0" > "$BATS_TEST_TMPDIR/pr_idx"
    prompt_response() {
        local _idx
        _idx=$(cat "$BATS_TEST_TMPDIR/pr_idx")
        _idx=$(( _idx + 1 ))
        echo "$_idx" > "$BATS_TEST_TMPDIR/pr_idx"
        sed -n "${_idx}p" "$BATS_TEST_TMPDIR/pr_seq"
    }
    run _pod_manage_envvars "api" <<< $'n\n'
    [ "$status" -eq 0 ]
    [ "$(jq -r '.pods.api.env_vars | contains(["NEW_VAR"])' "$CONFIG_FILE")" = "true" ]
}

@test "_pod_manage_envvars: add duplicate variable → warn + config unchanged" {
    local before
    before=$(md5sum "$CONFIG_FILE" | cut -d' ' -f1)
    printf '%s\n' 'API_VERSION' '' > "$BATS_TEST_TMPDIR/pr_seq"
    echo "0" > "$BATS_TEST_TMPDIR/pr_idx"
    prompt_response() {
        local _idx
        _idx=$(cat "$BATS_TEST_TMPDIR/pr_idx")
        _idx=$(( _idx + 1 ))
        echo "$_idx" > "$BATS_TEST_TMPDIR/pr_idx"
        sed -n "${_idx}p" "$BATS_TEST_TMPDIR/pr_seq"
    }
    run _pod_manage_envvars "api" <<< $'n\n'
    [ "$status" -eq 0 ]
    [[ "$output" == *"already present"* ]]
    local after
    after=$(md5sum "$CONFIG_FILE" | cut -d' ' -f1)
    [ "$before" = "$after" ]
}

@test "_pod_manage_envvars: add variable present in env_templates → err + exit 1" {
    # fixture: api.env_templates has "API_TITLE"
    printf '%s\n' 'API_TITLE' '' > "$BATS_TEST_TMPDIR/pr_seq"
    echo "0" > "$BATS_TEST_TMPDIR/pr_idx"
    prompt_response() {
        local _idx
        _idx=$(cat "$BATS_TEST_TMPDIR/pr_idx")
        _idx=$(( _idx + 1 ))
        echo "$_idx" > "$BATS_TEST_TMPDIR/pr_idx"
        sed -n "${_idx}p" "$BATS_TEST_TMPDIR/pr_seq"
    }
    run _pod_manage_envvars "api" <<< $'n\n'
    [ "$status" -eq 1 ]
    [[ "$output" == *"env_templates"* ]]
}

@test "_pod_manage_envvars: remove variable → removed from config.json" {
    # fixture: api.env_vars = ["API_VERSION"] → index 0
    select_menu_multi() { SELECTED_INDICES=(0); }
    run _pod_manage_envvars "api" <<< $'y\n'
    [ "$status" -eq 0 ]
    [ "$(jq '.pods.api.env_vars | length' "$CONFIG_FILE")" -eq 0 ]
}

# ── _pod_show_tokens ───────────────────────────────────────────────────────────

@test "_pod_show_tokens: displays built-in tokens" {
    run _pod_show_tokens
    [ "$status" -eq 0 ]
    [[ "$output" == *"{hostname}"* ]]
    [[ "$output" == *"{name}"* ]]
    [[ "$output" == *"{env}"* ]]
}

@test "_pod_show_tokens: displays template_vars names" {
    run _pod_show_tokens
    [ "$status" -eq 0 ]
    [[ "$output" == *"company"* ]]
    [[ "$output" == *"region"* ]]
}

# ── _pod_manage_templates ──────────────────────────────────────────────────────

@test "_pod_manage_templates: displays existing templates" {
    # Menu with templates: [Add(0) Edit(1) Remove(2) Back(3)] → Back=3
    select_menu() { SELECTED_IDX=3; }
    run _pod_manage_templates "api"
    [ "$status" -eq 0 ]
    [[ "$output" == *"API_TITLE"* ]]
    [[ "$output" == *"API_HOST"* ]]
}

@test "_pod_manage_templates: env_templates empty → warn 'No template'" {
    jq '.pods.api.env_templates = {}' "$CONFIG_FILE" > "$BATS_TEST_TMPDIR/tmp.json" \
        && mv "$BATS_TEST_TMPDIR/tmp.json" "$CONFIG_FILE"
    # Menu without templates: [Add(0) Back(1)] → Back=1
    select_menu() { SELECTED_IDX=1; }
    run _pod_manage_templates "api"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No template"* ]]
}

@test "_pod_manage_templates: Add valid → entry created in config.json" {
    # [Add(0) Edit(1) Remove(2) Back(3)] → Add=0
    select_menu() { SELECTED_IDX=0; }
    printf '%s\n' 'NEW_TPL' '{hostname}-new' > "$BATS_TEST_TMPDIR/pr_seq"
    echo "0" > "$BATS_TEST_TMPDIR/pr_idx"
    prompt_response() {
        local _idx
        _idx=$(cat "$BATS_TEST_TMPDIR/pr_idx")
        _idx=$(( _idx + 1 ))
        echo "$_idx" > "$BATS_TEST_TMPDIR/pr_idx"
        sed -n "${_idx}p" "$BATS_TEST_TMPDIR/pr_seq"
    }
    _pod_manage_templates "api"
    [ "$(jq -r '.pods.api.env_templates | has("NEW_TPL")' "$CONFIG_FILE")" = "true" ]
    [ "$(jq -r '.pods.api.env_templates.NEW_TPL' "$CONFIG_FILE")" = "{hostname}-new" ]
}

@test "_pod_manage_templates: Add present in env_vars → err + exit 1" {
    # api.env_vars = ["API_VERSION"]
    select_menu() { SELECTED_IDX=0; }
    _PROMPT_MOCK_VALUE="API_VERSION"
    run _pod_manage_templates "api"
    [ "$status" -eq 1 ]
    [[ "$output" == *"env_vars"* ]]
}

@test "_pod_manage_templates: Add duplicate → warn + config unchanged" {
    select_menu() { SELECTED_IDX=0; }
    _PROMPT_MOCK_VALUE="API_TITLE"
    local before
    before=$(md5sum "$CONFIG_FILE" | cut -d' ' -f1)
    run _pod_manage_templates "api"
    [ "$status" -eq 0 ]
    [[ "$output" == *"already present"* ]]
    local after
    after=$(md5sum "$CONFIG_FILE" | cut -d' ' -f1)
    [ "$before" = "$after" ]
}

@test "_pod_manage_templates: Edit → value updated" {
    # Call 1 (action menu) → Edit(1), call 2 (key selection) → index 0
    # Sorted keys: [API_COMPANY(0), API_HOST(1), API_TITLE(2)]
    local _call=0
    select_menu() {
        _call=$(( _call + 1 ))
        if [ "$_call" -eq 1 ]; then SELECTED_IDX=1; else SELECTED_IDX=0; fi
    }
    _PROMPT_MOCK_VALUE="new-value"
    _pod_manage_templates "api"
    [ "$(jq -r '.pods.api.env_templates.API_COMPANY' "$CONFIG_FILE")" = "new-value" ]
}

@test "_pod_manage_templates: Remove → entry removed" {
    # [Add(0) Edit(1) Remove(2) Back(3)] → Remove=2
    select_menu() { SELECTED_IDX=2; }
    # Sorted keys: API_COMPANY(0) → selected
    select_menu_multi() { SELECTED_INDICES=(0); }
    run _pod_manage_templates "api" <<< "y"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.pods.api.env_templates | has("API_COMPANY")' "$CONFIG_FILE")" = "false" ]
}

# ── Sync ───────────────────────────────────────────────────────────────────────

@test "cmd_config_pod: no change → prompt_sync_confirm not called" {
    local sync_file="$BATS_TEST_TMPDIR/sync_calls"
    prompt_sync_confirm() { echo "SYNC" >> "$sync_file"; }
    # Fixture: 1 pod "api" → menu: [api(0), "── Add(1)", "Quit(2)"]
    select_menu() { SELECTED_IDX=2; }
    run cmd_config_pod
    [ ! -f "$sync_file" ]
}

@test "cmd_config_pod: after removal → prompt_sync_confirm called" {
    local sync_file="$BATS_TEST_TMPDIR/sync_calls"
    prompt_sync_confirm() { echo "SYNC" >> "$sync_file"; }
    # Call 1 (outer loop): api at index 0
    # Call 2 (inner sub-menu): "Remove this pod" at index 2
    # _pod_remove reads "y" from stdin
    # Call 3 (outer loop, api removed): ["── Add(0)", "Quit(1)"] → Quit=1
    local _call=0
    select_menu() {
        _call=$(( _call + 1 ))
        case "$_call" in
            1) SELECTED_IDX=0 ;;
            2) SELECTED_IDX=2 ;;
            3) SELECTED_IDX=1 ;;
        esac
    }
    run cmd_config_pod <<< "y"
    [ "$status" -eq 0 ]
    [ -f "$sync_file" ]
}
