#!/usr/bin/env bats
# Integration tests for scripts/commands/exec.sh
# Invoked via scripts/bin/fleetman (real entry point).

load '../test_helper/common'

setup() {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin" "$HOME/.ssh"
    setup_fixtures

    # Mock openssl: silent password decryption
    cat > "$BATS_TEST_TMPDIR/bin/openssl" << 'EOF'
#!/bin/bash
printf 'testpassword'
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/openssl"

    # Mock ssh: logs calls, exit code configurable via $SSH_EXIT_CODE
    cat > "$BATS_TEST_TMPDIR/bin/ssh" << 'EOF'
#!/bin/bash
# Filter ssh options (-i key, -o ...) to isolate host + command
args=()
skip_next=0
for arg in "$@"; do
    if [ "$skip_next" -eq 1 ]; then
        skip_next=0
        continue
    fi
    case "$arg" in
        -i|-o|-p) skip_next=1 ;;
        -*)       ;;
        *)        args+=("$arg") ;;
    esac
done
echo "SSH_CALLED:${args[*]}"
exit "${SSH_EXIT_CODE:-0}"
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/ssh"

    # Fleet key + passfile → silent ask_password, check_sshpass no-op
    touch "$HOME/.ssh/fleet_key" "$HOME/.fleet_pass.enc"
    export FLEET_KEY="$HOME/.ssh/fleet_key"
    export FLEET_PASS_FILE="$HOME/.fleet_pass.enc"
}

# ── Help ──────────────────────────────────────────────────────────────────────

@test "fleetman exec -h: displays the docblock (Usage)" {
    run bash "$SCRIPTS_DIR/bin/fleetman" exec -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"exec"* ]]
}

@test "fleetman exec --help: exit 0 and displays the docblock" {
    run bash "$SCRIPTS_DIR/bin/fleetman" exec --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

# ── Validation ────────────────────────────────────────────────────────────────

@test "fleetman exec: no command → exit 1 + error message" {
    run bash "$SCRIPTS_DIR/bin/fleetman" exec
    [ "$status" -eq 1 ]
    [[ "$output" == *"✗"* ]]
    [[ "$output" == *"command is required"* ]]
}

@test "fleetman exec --: no command after -- → exit 1" {
    run bash "$SCRIPTS_DIR/bin/fleetman" exec --
    [ "$status" -eq 1 ]
    [[ "$output" == *"command is required"* ]]
}

@test "fleetman exec: unknown option → exit 1" {
    run bash "$SCRIPTS_DIR/bin/fleetman" exec -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "fleetman exec: invalid -e → exit 1" {
    run bash "$SCRIPTS_DIR/bin/fleetman" exec -e nosuchenv -- uptime
    [ "$status" -eq 1 ]
}

# ── Output format ─────────────────────────────────────────────────────────────

@test "fleetman exec -e test -- echo hi: displays the section header" {
    run bash "$SCRIPTS_DIR/bin/fleetman" exec -e test -- "echo hi"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Exec:"* ]]
    [[ "$output" == *"echo hi"* ]]
    [[ "$output" == *"TEST"* ]]
}

@test "fleetman exec -e test -- echo hi: displays the ── header per server" {
    run bash "$SCRIPTS_DIR/bin/fleetman" exec -e test -- "echo hi"
    [ "$status" -eq 0 ]
    [[ "$output" == *"── test1"* ]]
}

# ── Remote execution ──────────────────────────────────────────────────────────

@test "fleetman exec -e test -- echo hi: ssh called for test1.fleet.test" {
    run bash "$SCRIPTS_DIR/bin/fleetman" exec -e test -- "echo hi"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SSH_CALLED:test1.fleet.test echo hi"* ]]
}

@test "fleetman exec -e dev -- uptime: ssh called for dev1 and dev2" {
    run bash "$SCRIPTS_DIR/bin/fleetman" exec -e dev -- uptime
    [ "$status" -eq 0 ]
    [[ "$output" == *"SSH_CALLED:dev1.fleet.test uptime"* ]]
    [[ "$output" == *"SSH_CALLED:dev2.fleet.test uptime"* ]]
}

# ── Exit code propagation ─────────────────────────────────────────────────────

@test "fleetman exec: ssh succeeds → exit 0" {
    export SSH_EXIT_CODE=0
    run bash "$SCRIPTS_DIR/bin/fleetman" exec -e test -- "echo hi"
    [ "$status" -eq 0 ]
}

@test "fleetman exec: ssh fails → exit 1 + error message" {
    export SSH_EXIT_CODE=1
    run bash "$SCRIPTS_DIR/bin/fleetman" exec -e test -- "echo hi"
    [ "$status" -eq 1 ]
    [[ "$output" == *"✗"* ]]
    [[ "$output" == *"non-zero"* ]]
}
