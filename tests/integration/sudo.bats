#!/usr/bin/env bats
# Integration tests for scripts/commands/sudo.sh
# Invoked via scripts/bin/fleetman (real entry point).

load '../test_helper/common'

setup() {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin" "$HOME/.ssh"
    setup_fixtures

    # Mock sudo: logs args + stdin, exit configurable via $SUDO_EXIT_CODE
    cat > "$BATS_TEST_TMPDIR/bin/sudo" << 'EOF'
#!/bin/bash
has_s=0
filtered=()
for arg in "$@"; do
    [[ "$arg" == "-S" ]] && { has_s=1; continue; }
    filtered+=("$arg")
done
stdin_val=$(cat)
echo "HAS_S:$has_s PASS:$stdin_val CMD:${filtered[*]}"
exit "${SUDO_EXIT_CODE:-0}"
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/sudo"
}

# ── Help ──────────────────────────────────────────────────────────────────────

@test "fleetman sudo -h: displays the docblock" {
    run bash "$SCRIPTS_DIR/bin/fleetman" sudo -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"sudo"* ]]
}

@test "fleetman sudo --help: exit 0 and displays Usage" {
    run bash "$SCRIPTS_DIR/bin/fleetman" sudo --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

# ── Validation ────────────────────────────────────────────────────────────────

@test "fleetman sudo: no command → exit 1 + error message" {
    run bash "$SCRIPTS_DIR/bin/fleetman" sudo
    [ "$status" -eq 1 ]
    [[ "$output" == *"✗"* ]]
    [[ "$output" == *"No command provided"* ]]
}

@test "fleetman sudo: unknown option → exit 1" {
    run bash "$SCRIPTS_DIR/bin/fleetman" sudo -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

# ── With fleet key (silent decryption) ───────────────────────────────────────

@test "fleetman sudo: with key+passfile → sudo -S with decrypted password" {
    cat > "$BATS_TEST_TMPDIR/bin/openssl" << 'EOF'
#!/bin/bash
printf 'testpassword'
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/openssl"
    touch "$HOME/.ssh/fleet_key" "$HOME/.fleet_pass.enc"
    export FLEET_KEY="$HOME/.ssh/fleet_key"
    export FLEET_PASS_FILE="$HOME/.fleet_pass.enc"

    run bash "$SCRIPTS_DIR/bin/fleetman" sudo -- whoami
    [ "$status" -eq 0 ]
    [[ "$output" == *"HAS_S:1"* ]]
    [[ "$output" == *"PASS:testpassword"* ]]
    [[ "$output" == *"CMD:whoami"* ]]
}

# ── Without fleet key (interactive prompt) ────────────────────────────────────

@test "fleetman sudo: without key or passfile → interactive prompt via stdin" {
    rm -f "$HOME/.ssh/fleet_key" "$HOME/.fleet_pass.enc"
    export FLEET_KEY="$HOME/.ssh/fleet_key"
    export FLEET_PASS_FILE="$HOME/.fleet_pass.enc"

    run bash "$SCRIPTS_DIR/bin/fleetman" sudo -- whoami <<< 'interactivepass'
    [ "$status" -eq 0 ]
    [[ "$output" == *"HAS_S:1"* ]]
    [[ "$output" == *"PASS:interactivepass"* ]]
}

# ── Exit code propagation ─────────────────────────────────────────────────────

@test "fleetman sudo: sudo fails → exit code propagated" {
    cat > "$BATS_TEST_TMPDIR/bin/openssl" << 'EOF'
#!/bin/bash
printf 'testpassword'
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/openssl"
    touch "$HOME/.ssh/fleet_key" "$HOME/.fleet_pass.enc"
    export FLEET_KEY="$HOME/.ssh/fleet_key"
    export FLEET_PASS_FILE="$HOME/.fleet_pass.enc"
    export SUDO_EXIT_CODE=3

    run bash "$SCRIPTS_DIR/bin/fleetman" sudo -- whoami
    [ "$status" -eq 3 ]
}
