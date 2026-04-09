#!/usr/bin/env bats
# Unit tests for scripts/lib/bashrc.sh

load '../../test_helper/common'

setup() {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    load_common
    source "$SCRIPTS_DIR/lib/bashrc.sh"
    touch "$HOME/.bashrc"
}

# ── generate_fleetman_sh ───────────────────────────────────────────────────────

@test "generate_fleetman_sh: creates ~/.data/fleetman.sh" {
    generate_fleetman_sh
    [ -f "$DATA_DIR/fleetman.sh" ]
}

@test "generate_fleetman_sh: contains PATH export with literal \$HOME" {
    generate_fleetman_sh
    grep -q 'export PATH="\$HOME/scripts/bin:\$PATH"' "$DATA_DIR/fleetman.sh"
}

@test "generate_fleetman_sh: \$HOME is not expanded in the generated file" {
    generate_fleetman_sh
    # The literal symbol $HOME is present
    grep -q '\$HOME' "$DATA_DIR/fleetman.sh"
    # The expanded HOME path (e.g. /tmp/...) is not present at start of value
    ! grep -q "^export PATH=\"$HOME" "$DATA_DIR/fleetman.sh"
}

@test "generate_fleetman_sh: contains sourcing of .bash_aliases" {
    generate_fleetman_sh
    grep -q '\.bash_aliases' "$DATA_DIR/fleetman.sh"
}

@test "generate_fleetman_sh: contains sourcing of completion.sh" {
    generate_fleetman_sh
    grep -q 'completion\.sh' "$DATA_DIR/fleetman.sh"
}

@test "generate_fleetman_sh: welcome.enabled=true (default) → contains welcome.sh" {
    generate_fleetman_sh
    grep -q 'welcome\.sh' "$DATA_DIR/fleetman.sh"
}

@test "generate_fleetman_sh: welcome.enabled=false → no welcome.sh" {
    local updated
    updated=$(jq '.welcome = {"enabled": false}' "$CONFIG_FILE")
    printf '%s\n' "$updated" > "$CONFIG_FILE"
    generate_fleetman_sh
    ! grep -q 'welcome\.sh' "$DATA_DIR/fleetman.sh"
}

@test "generate_fleetman_sh: base_folder defined → emits cd line with SHLVL guard" {
    local updated
    updated=$(jq --arg bf "/opt/mydir" '.base_folder = $bf' "$CONFIG_FILE")
    printf '%s\n' "$updated" > "$CONFIG_FILE"
    generate_fleetman_sh
    grep -q '\[\[ \$SHLVL -eq 1 && -d /opt/mydir \]\] && cd /opt/mydir' "$DATA_DIR/fleetman.sh"
}

@test "generate_fleetman_sh: base_folder absent → no cd line" {
    jq 'del(.base_folder)' "$CONFIG_FILE" > "$BATS_TEST_TMPDIR/tmp.json" \
        && mv "$BATS_TEST_TMPDIR/tmp.json" "$CONFIG_FILE"
    generate_fleetman_sh
    ! grep -q ' && cd ' "$DATA_DIR/fleetman.sh"
}

@test "generate_fleetman_sh: base_folder empty → no cd line" {
    local updated
    updated=$(jq '.base_folder = ""' "$CONFIG_FILE")
    printf '%s\n' "$updated" > "$CONFIG_FILE"
    generate_fleetman_sh
    ! grep -q ' && cd ' "$DATA_DIR/fleetman.sh"
}

@test "generate_fleetman_sh: idempotent — fully rewritten on each call" {
    generate_fleetman_sh
    echo "extra line" >> "$DATA_DIR/fleetman.sh"
    generate_fleetman_sh
    ! grep -q 'extra line' "$DATA_DIR/fleetman.sh"
}

@test "generate_fleetman_sh: creates DATA_DIR if absent" {
    rm -rf "$DATA_DIR"
    generate_fleetman_sh
    [ -f "$DATA_DIR/fleetman.sh" ]
}

# ── write_fleetman_bashrc_block ───────────────────────────────────────────────

@test "write_fleetman_bashrc_block: adds the BEGIN/END FLEETMAN block" {
    write_fleetman_bashrc_block
    grep -q '# BEGIN FLEETMAN' "$HOME/.bashrc"
    grep -q '# END FLEETMAN' "$HOME/.bashrc"
}

@test "write_fleetman_bashrc_block: contains the sourcing line" {
    write_fleetman_bashrc_block
    grep -q '\[\[ -f ~/\.data/fleetman\.sh \]\] && \. ~/\.data/fleetman\.sh' "$HOME/.bashrc"
}

@test "write_fleetman_bashrc_block: returns 0 when block is added" {
    run write_fleetman_bashrc_block
    [ "$status" -eq 0 ]
}

@test "write_fleetman_bashrc_block: returns 1 when block is already present" {
    write_fleetman_bashrc_block
    run write_fleetman_bashrc_block
    [ "$status" -eq 1 ]
}

@test "write_fleetman_bashrc_block: idempotent — does not add the block twice" {
    write_fleetman_bashrc_block
    write_fleetman_bashrc_block || true
    local count
    count=$(grep -c '# BEGIN FLEETMAN' "$HOME/.bashrc")
    [ "$count" -eq 1 ]
}

@test "write_fleetman_bashrc_block: preserves pre-existing content of .bashrc" {
    echo "# existing line" > "$HOME/.bashrc"
    write_fleetman_bashrc_block
    grep -q 'existing line' "$HOME/.bashrc"
}
