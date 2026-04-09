#!/usr/bin/env bats
# Unit tests for scripts/commands/config/welcome.sh

load '../../../test_helper/common'

setup() {
    load_common
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"

    # tput requires a TTY — no-op binary mock
    printf '#!/bin/bash\n' > "$BATS_TEST_TMPDIR/bin/tput"
    chmod +x "$BATS_TEST_TMPDIR/bin/tput"

    source "$SCRIPTS_DIR/commands/config/welcome.sh"

    # Mocks redefined after sourcing (idempotency guards prevent re-sourcing)
    render() { echo "RENDER_CALLED"; }
    collect_system_info() { :; }
    prompt_sync_confirm() { :; }

    # Globals used by _wc_handle_key and _wc_do_save
    _envs=("dev" "test" "prod")
    _env_idx=0
    _show_welcome="true"
    _show_pods="true"
    _show_os="true"
    _show_docker="true"
}

# ── Invalid options ────────────────────────────────────────────────────────────

@test "cmd_config_welcome: unknown option → exit 1 + 'Unknown option'" {
    run cmd_config_welcome -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

# ── check_config_file ──────────────────────────────────────────────────────────

@test "cmd_config_welcome: config.json absent → exit 1 + ⚠" {
    rm -f "$CONFIG_FILE"
    run cmd_config_welcome
    [ "$status" -eq 1 ]
    [[ "$output" == *"⚠"* ]]
}

# ── Toggles ───────────────────────────────────────────────────────────────────

@test "_wc_handle_key a (enabled=true) → _show_welcome=false" {
    _show_welcome="true"
    _wc_handle_key a
    [ "$_show_welcome" = "false" ]
}

@test "_wc_handle_key a (enabled=false) → _show_welcome=true" {
    _show_welcome="false"
    _wc_handle_key a
    [ "$_show_welcome" = "true" ]
}

@test "_wc_handle_key p (show_pods=true) → _show_pods=false" {
    _show_pods="true"
    _wc_handle_key p
    [ "$_show_pods" = "false" ]
}

@test "_wc_handle_key o (show_os=true) → _show_os=false" {
    _show_os="true"
    _wc_handle_key o
    [ "$_show_os" = "false" ]
}

@test "_wc_handle_key d (show_docker=true) → _show_docker=false" {
    _show_docker="true"
    _wc_handle_key d
    [ "$_show_docker" = "false" ]
}

# ── Navigation ─────────────────────────────────────────────────────────────────

@test "_wc_handle_key RIGHT → _env_idx incremented to 1" {
    _env_idx=0
    _wc_handle_key RIGHT
    [ "$_env_idx" -eq 1 ]
}

@test "_wc_handle_key RIGHT × 3 (wrap) → _env_idx wraps back to 0" {
    _env_idx=0
    _wc_handle_key RIGHT
    _wc_handle_key RIGHT
    _wc_handle_key RIGHT
    [ "$_env_idx" -eq 0 ]
}

@test "_wc_handle_key LEFT from idx=0 → _env_idx=2 (wrap)" {
    _env_idx=0
    _wc_handle_key LEFT
    [ "$_env_idx" -eq 2 ]
}

@test "_wc_handle_key q → exit code 3" {
    run _wc_handle_key q
    [ "$status" -eq 3 ]
}

# ── Save ───────────────────────────────────────────────────────────────────────

@test "_wc_handle_key x → config.json updated with correct booleans" {
    _show_welcome="false"
    _show_pods="true"
    _show_os="false"
    _show_docker="true"
    run _wc_handle_key x
    [ "$status" -eq 2 ]
    [ "$(jq '.welcome.enabled'     "$CONFIG_FILE")" = "false" ]
    [ "$(jq '.welcome.show_pods'   "$CONFIG_FILE")" = "true"  ]
    [ "$(jq '.welcome.show_os'     "$CONFIG_FILE")" = "false" ]
    [ "$(jq '.welcome.show_docker' "$CONFIG_FILE")" = "true"  ]
}

@test "_wc_handle_key x → prompt_sync_confirm called" {
    local call_file="$BATS_TEST_TMPDIR/sync_calls"
    prompt_sync_confirm() { echo "SYNC" >> "$call_file"; }
    run _wc_handle_key x
    [ "$status" -eq 2 ]
    [ -f "$call_file" ]
}

@test "_wc_handle_key q → config.json not modified" {
    local before
    before=$(cat "$CONFIG_FILE")
    run _wc_handle_key q
    [ "$status" -eq 3 ]
    [ "$(cat "$CONFIG_FILE")" = "$before" ]
}

# ── _wc_cleanup ────────────────────────────────────────────────────────────────

@test "_wc_cleanup: calls tput cnorm" {
    local call_file="$BATS_TEST_TMPDIR/tput_calls"
    printf '#!/bin/bash\necho "$@" >> "%s"\n' "$call_file" > "$BATS_TEST_TMPDIR/bin/tput"
    chmod +x "$BATS_TEST_TMPDIR/bin/tput"
    _wc_cleanup
    grep -q "cnorm" "$call_file"
}

# ── _wc_render_preview ────────────────────────────────────────────────────────

@test "_wc_render_preview: _show_welcome=true → render called" {
    run _wc_render_preview "dev1.fleet.test"
    [[ "$output" == *"RENDER_CALLED"* ]]
}

@test "_wc_render_preview: _show_welcome=false → shows DISABLED box" {
    _show_welcome="false"
    run _wc_render_preview "dev1.fleet.test"
    [[ "$output" == *"Welcome screen DISABLED"* ]]
}

@test "_wc_render_preview: sets HOST as fqdn short name" {
    _wc_render_preview "dev1.fleet.test"
    [ "$HOST" = "dev1" ]
}

@test "_wc_render_preview: sets ENV_NAME from _envs[_env_idx]" {
    _env_idx=1
    _wc_render_preview "test1.fleet.test"
    [ "$ENV_NAME" = "test" ]
}

@test "_wc_render_preview: prints hint line" {
    run _wc_render_preview "dev1.fleet.test"
    [[ "$output" == *"←/→ env"* ]]
}

@test "_wc_render_preview: ASCII_LINES loaded when file exists" {
    printf 'line1\nline2\n' > "$HOME/.data/welcome_dev1.ascii"
    _wc_render_preview "dev1.fleet.test"
    [ "${ASCII_LINES[0]}" = "line1" ]
    [ "${ASCII_LINES[1]}" = "line2" ]
}

@test "_wc_render_preview: ASCII_LINES empty when ascii file absent" {
    rm -f "$HOME/.data/welcome_dev1.ascii"
    _wc_render_preview "dev1.fleet.test"
    [ "${#ASCII_LINES[@]}" -eq 0 ]
}

@test "_wc_render_preview: PODS loaded from pods file for env/host" {
    _wc_render_preview "dev1.fleet.test"
    [ "${PODS[0]}" = "api" ]
    [ "${PODS[1]}" = "worker" ]
}

@test "_wc_render_preview: container_rows contains preview mode text" {
    _wc_render_preview "dev1.fleet.test"
    [[ "${container_rows[0]}" == *"preview mode"* ]]
}

# ── cmd_config_welcome: interactive loop ──────────────────────────────────────

@test "cmd_config_welcome: q key → exits 0" {
    run bash -c "
        export HOME='$HOME'
        export CONFIG_FILE='$CONFIG_FILE'
        export PODS_FILE='$PODS_FILE'
        source '$SCRIPTS_DIR/commands/config/welcome.sh'
        render() { :; }
        collect_system_info() { :; }
        prompt_sync_confirm() { :; }
        cmd_config_welcome <<< 'q'
    "
    [ "$status" -eq 0 ]
}

@test "cmd_config_welcome: x key → exits 0 + shows 'Welcome config saved'" {
    run bash -c "
        export HOME='$HOME'
        export CONFIG_FILE='$CONFIG_FILE'
        export PODS_FILE='$PODS_FILE'
        source '$SCRIPTS_DIR/commands/config/welcome.sh'
        render() { :; }
        collect_system_info() { :; }
        prompt_sync_confirm() { :; }
        cmd_config_welcome <<< 'x'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"Welcome config saved"* ]]
}

@test "cmd_config_welcome: welcome.enabled=false → _show_welcome=false in first render" {
    jq '.welcome.enabled = false' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    local state_file="$BATS_TEST_TMPDIR/show_welcome_state"
    run bash -c "
        export HOME='$HOME'
        export CONFIG_FILE='$CONFIG_FILE'
        export PODS_FILE='$PODS_FILE'
        source '$SCRIPTS_DIR/commands/config/welcome.sh'
        collect_system_info() { :; }
        prompt_sync_confirm() { :; }
        _wc_render_preview() { echo \"\$_show_welcome\" > '$state_file'; }
        cmd_config_welcome <<< 'q'
    "
    [ -f "$state_file" ]
    [ "$(cat "$state_file")" = "false" ]
}

@test "cmd_config_welcome: missing welcome section → all flags default to true" {
    jq 'del(.welcome)' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    local state_file="$BATS_TEST_TMPDIR/flags_state"
    run bash -c "
        export HOME='$HOME'
        export CONFIG_FILE='$CONFIG_FILE'
        export PODS_FILE='$PODS_FILE'
        source '$SCRIPTS_DIR/commands/config/welcome.sh'
        collect_system_info() { :; }
        prompt_sync_confirm() { :; }
        _wc_render_preview() { echo \"\$_show_welcome \$_show_pods \$_show_os \$_show_docker\" > '$state_file'; }
        cmd_config_welcome <<< 'q'
    "
    [ -f "$state_file" ]
    [ "$(cat "$state_file")" = "true true true true" ]
}
