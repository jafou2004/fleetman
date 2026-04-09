#!/usr/bin/env bats
# Unit tests for scripts/commands/sudo.sh

load '../../test_helper/common'

setup() {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin" "$HOME/.ssh"
    load_common

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

    source "$SCRIPTS_DIR/commands/sudo.sh"
}

# ── Option validation ────────────────────────────────────────────────────────

@test "cmd_sudo: unknown option → exit 1 + error message" {
    run cmd_sudo -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

# ── Prerequisites ────────────────────────────────────────────────────────────

@test "cmd_sudo: no command → exit 1 + error message" {
    run cmd_sudo
    [ "$status" -eq 1 ]
    [[ "$output" == *"No command provided"* ]]
}

# ── With fleet key (silent decryption) ───────────────────────────────────────

@test "cmd_sudo: with key+passfile → sudo -S receives the decrypted password" {
    # Mock openssl: returns the decrypted password
    cat > "$BATS_TEST_TMPDIR/bin/openssl" << 'EOF'
#!/bin/bash
printf 'testpassword'
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/openssl"

    touch "$HOME/.ssh/fleet_key" "$HOME/.fleet_pass.enc"
    export FLEET_KEY="$HOME/.ssh/fleet_key"
    export FLEET_PASS_FILE="$HOME/.fleet_pass.enc"

    run cmd_sudo whoami
    [ "$status" -eq 0 ]
    [[ "$output" == *"HAS_S:1"* ]]
    [[ "$output" == *"PASS:testpassword"* ]]
    [[ "$output" == *"CMD:whoami"* ]]
}

@test "cmd_sudo: with key+passfile → multiple args passed to sudo" {
    cat > "$BATS_TEST_TMPDIR/bin/openssl" << 'EOF'
#!/bin/bash
printf 'testpassword'
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/openssl"

    touch "$HOME/.ssh/fleet_key" "$HOME/.fleet_pass.enc"
    export FLEET_KEY="$HOME/.ssh/fleet_key"
    export FLEET_PASS_FILE="$HOME/.fleet_pass.enc"

    run cmd_sudo systemctl restart docker
    [ "$status" -eq 0 ]
    [[ "$output" == *"CMD:systemctl restart docker"* ]]
}

# ── Without fleet key (interactive prompt) ───────────────────────────────────

@test "cmd_sudo: no key or passfile → interactive prompt, password via stdin" {
    rm -f "$HOME/.ssh/fleet_key" "$HOME/.fleet_pass.enc"
    export FLEET_KEY="$HOME/.ssh/fleet_key"
    export FLEET_PASS_FILE="$HOME/.fleet_pass.enc"

    run cmd_sudo whoami <<< 'interactivepass'
    [ "$status" -eq 0 ]
    [[ "$output" == *"HAS_S:1"* ]]
    [[ "$output" == *"PASS:interactivepass"* ]]
}

# ── Exit code propagation ────────────────────────────────────────────────────

@test "cmd_sudo: sudo succeeds → exit 0 returned" {
    cat > "$BATS_TEST_TMPDIR/bin/openssl" << 'EOF'
#!/bin/bash
printf 'testpassword'
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/openssl"
    touch "$HOME/.ssh/fleet_key" "$HOME/.fleet_pass.enc"
    export FLEET_KEY="$HOME/.ssh/fleet_key"
    export FLEET_PASS_FILE="$HOME/.fleet_pass.enc"
    export SUDO_EXIT_CODE=0

    run cmd_sudo whoami
    [ "$status" -eq 0 ]
}

@test "cmd_sudo: sudo fails → exit code propagated" {
    cat > "$BATS_TEST_TMPDIR/bin/openssl" << 'EOF'
#!/bin/bash
printf 'testpassword'
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/openssl"
    touch "$HOME/.ssh/fleet_key" "$HOME/.fleet_pass.enc"
    export FLEET_KEY="$HOME/.ssh/fleet_key"
    export FLEET_PASS_FILE="$HOME/.fleet_pass.enc"
    export SUDO_EXIT_CODE=3

    run cmd_sudo whoami
    [ "$status" -eq 3 ]
}

# ── Direct coverage (without run, for kcov) ──────────────────────────────────

@test "cmd_sudo: direct call with key → sudo called (sudo line)" {
    cat > "$BATS_TEST_TMPDIR/bin/openssl" << 'EOF'
#!/bin/bash
printf 'testpassword'
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/openssl"
    touch "$HOME/.ssh/fleet_key" "$HOME/.fleet_pass.enc"
    export FLEET_KEY="$HOME/.ssh/fleet_key"
    export FLEET_PASS_FILE="$HOME/.fleet_pass.enc"

    cmd_sudo whoami > "$BATS_TEST_TMPDIR/out.txt"
    grep -q "HAS_S:1" "$BATS_TEST_TMPDIR/out.txt"
    grep -q "PASS:testpassword" "$BATS_TEST_TMPDIR/out.txt"
}
