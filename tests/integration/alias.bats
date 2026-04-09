#!/usr/bin/env bats
# Integration tests for scripts/commands/alias.sh
# Invoked via scripts/bin/fleetman (real entry point).

load '../test_helper/common'

setup() {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    setup_fixtures
    cp "$FIXTURES_DIR/.bash_aliases" "$HOME/.bash_aliases"
}

# ── Via the fleetman dispatcher ───────────────────────────────────────────────

@test "fleetman alias -h: displays the alias.sh docblock" {
    run bash "$SCRIPTS_DIR/bin/fleetman" alias -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"aliases"* ]]
    [[ "$output" == *"Usage"* ]]
}

@test "fleetman alias --help: exit 0 and displays Usage" {
    run bash "$SCRIPTS_DIR/bin/fleetman" alias --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

# ── No filter ─────────────────────────────────────────────────────────────────

@test "fleetman alias: exit 0, all categories with headings" {
    run bash "$SCRIPTS_DIR/bin/fleetman" alias
    [ "$status" -eq 0 ]
    [[ "$output" == *"Git"* ]]
    [[ "$output" == *"Docker"* ]]
    [[ "$output" == *"Scripts"* ]]
    [[ "$output" == *"###"* ]]
}

# ── Valid filter ──────────────────────────────────────────────────────────────

@test "fleetman alias -c git: exit 0, only the Git category" {
    run bash "$SCRIPTS_DIR/bin/fleetman" alias -c git
    [ "$status" -eq 0 ]
    [[ "$output" == *"gs"* ]]
    [[ "$output" != *"Docker"* ]]
    [[ "$output" != *"###"* ]]
}

@test "fleetman alias -c docker: exit 0, only the Docker category" {
    run bash "$SCRIPTS_DIR/bin/fleetman" alias -c docker
    [ "$status" -eq 0 ]
    [[ "$output" == *"dps"* ]]
    [[ "$output" != *"Git"* ]]
}

# ── Unknown filter ────────────────────────────────────────────────────────────

@test "fleetman alias -c nonexistent: exit 1 + error message" {
    run bash "$SCRIPTS_DIR/bin/fleetman" alias -c zzz_inexistant
    [ "$status" -eq 1 ]
    [[ "$output" == *"✗"* ]]
}

# ── Missing file ──────────────────────────────────────────────────────────────

@test "fleetman alias: missing .bash_aliases file → exit 1" {
    rm -f "$HOME/.bash_aliases"
    run bash "$SCRIPTS_DIR/bin/fleetman" alias
    [ "$status" -eq 1 ]
    [[ "$output" == *"✗"* ]]
}

# ── Empty file ────────────────────────────────────────────────────────────────

@test "fleetman alias: empty file → exit 1 + warning ⚠" {
    printf '' > "$HOME/.bash_aliases"
    run bash "$SCRIPTS_DIR/bin/fleetman" alias
    [ "$status" -eq 1 ]
    [[ "$output" == *"⚠"* ]]
    [[ "$output" != *"✗"* ]]
}

@test "fleetman alias -c git: empty file → warn, not 'No category found'" {
    printf '' > "$HOME/.bash_aliases"
    run bash "$SCRIPTS_DIR/bin/fleetman" alias -c git
    [ "$status" -eq 1 ]
    [[ "$output" == *"⚠"* ]]
    [[ "$output" != *"No category found"* ]]
}
