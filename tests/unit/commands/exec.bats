#!/usr/bin/env bats
# Unit tests for scripts/commands/exec.sh

load '../../test_helper/common'

setup() {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin" "$HOME/.ssh"
    load_common

    # Disable spinner
    _spin_start() { :; }
    _spin_stop()  { :; }

    # Mock ssh_cmd (function): logs calls
    ssh_cmd() { echo "SSH:$*"; }

    # Mock ask_password: avoids any interactive prompt
    ask_password() { PASSWORD="testpass"; B64_PASS="dGVzdHBhc3M="; }

    # fleet_key present → check_sshpass is no-op
    touch "$HOME/.ssh/fleet_key"
    export FLEET_KEY="$HOME/.ssh/fleet_key"

    source "$SCRIPTS_DIR/commands/exec.sh"

    # Re-mock after sourcing (libs re-sourced by exec.sh)
    ssh_cmd()     { echo "SSH:$*"; }
    ask_password() { PASSWORD="testpass"; B64_PASS="dGVzdHBhc3M="; }
    _spin_start() { :; }
    _spin_stop()  { :; }

    # MASTER_HOST points to a host outside the test fleet
    export MASTER_HOST="master.local"
}

# ── Validation ────────────────────────────────────────────────────────────────

@test "cmd_exec: no command → exit 1 + error message" {
    run cmd_exec
    [ "$status" -eq 1 ]
    [[ "$output" == *"command is required"* ]]
}

@test "cmd_exec: with -- without argument → exit 1 + error message" {
    run cmd_exec --
    [ "$status" -eq 1 ]
    [[ "$output" == *"command is required"* ]]
}

@test "cmd_exec: empty command after -- → exit 1 + error message" {
    run cmd_exec -- ""
    [ "$status" -eq 1 ]
    [[ "$output" == *"command is required"* ]]
}

@test "cmd_exec: unknown option → exit 1 + error message" {
    run cmd_exec -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "cmd_exec: option without argument → exit 1 + error message" {
    run cmd_exec -e
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires an argument"* ]]
}

@test "cmd_exec: invalid environment → exit 1" {
    run cmd_exec -e nosuchenv -- uptime
    [ "$status" -eq 1 ]
}

# ── Section header ────────────────────────────────────────────────────────────

@test "cmd_exec: displays the section header with the command" {
    run cmd_exec -e test -- "echo hi"
    [[ "$output" == *"Exec:"* ]]
    [[ "$output" == *"echo hi"* ]]
}

@test "cmd_exec: the section header includes the environment (TEST)" {
    run cmd_exec -e test -- "echo hi"
    [[ "$output" == *"TEST"* ]]
}

@test "cmd_exec: without -e → label is ALL" {
    run cmd_exec -- "echo hi"
    [[ "$output" == *"ALL"* ]]
}

# ── Path remote ───────────────────────────────────────────────────────────────

@test "cmd_exec: -e test → ssh_cmd called for test1.fleet.test" {
    run cmd_exec -e test -- "echo hi"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SSH:test1.fleet.test echo hi"* ]]
}

@test "cmd_exec: -e dev → ssh_cmd called for dev1 and dev2" {
    run cmd_exec -e dev -- "echo hi"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SSH:dev1.fleet.test echo hi"* ]]
    [[ "$output" == *"SSH:dev2.fleet.test echo hi"* ]]
}

@test "cmd_exec: blue header ── displayed for each server" {
    run cmd_exec -e test -- "echo hi"
    [[ "$output" == *"── test1"* ]]
}

# ── Path local ────────────────────────────────────────────────────────────────

@test "cmd_exec: MASTER_HOST = server → local execution (no ssh_cmd)" {
    export MASTER_HOST="test1.fleet.test"
    ssh_cmd() { echo "SSH_CALLED:$*"; }

    run cmd_exec -e test -- "echo local_output"
    [ "$status" -eq 0 ]
    # Command was executed locally
    [[ "$output" == *"local_output"* ]]
    # ssh_cmd was not called
    [[ "$output" != *"SSH_CALLED"* ]]
}

@test "cmd_exec: local execution → header indicates (local)" {
    export MASTER_HOST="test1.fleet.test"
    run cmd_exec -e test -- "echo hi"
    [[ "$output" == *"(local)"* ]]
}

# ── Exit code ─────────────────────────────────────────────────────────────────

@test "cmd_exec: ssh_cmd succeeds → exit 0" {
    ssh_cmd() { return 0; }
    run cmd_exec -e test -- "echo hi"
    [ "$status" -eq 0 ]
}

@test "cmd_exec: ssh_cmd fails → exit 1 + error message" {
    ssh_cmd() { return 1; }
    run cmd_exec -e test -- "echo hi"
    [ "$status" -eq 1 ]
    [[ "$output" == *"✗"* ]]
    [[ "$output" == *"non-zero"* ]]
}

@test "cmd_exec: multiple servers fail → failure_count displayed" {
    ssh_cmd() { return 1; }
    run cmd_exec -e dev -- "echo hi"
    [ "$status" -eq 1 ]
    [[ "$output" == *"2 server(s)"* ]]
}

@test "cmd_exec: local command fails → exit 1" {
    export MASTER_HOST="test1.fleet.test"
    run cmd_exec -e test -- "exit 1"
    [ "$status" -eq 1 ]
}

# ── Direct coverage (without run, for kcov) ──────────────────────────────────

@test "cmd_exec: direct call → ssh_cmd is invoked (coverage)" {
    ssh_cmd() { echo "SSH_DIRECT:$*" >> "$BATS_TEST_TMPDIR/ssh_calls"; }

    cmd_exec -e test -- "echo hi" > "$BATS_TEST_TMPDIR/out.txt" || true
    grep -q "SSH_DIRECT:test1.fleet.test" "$BATS_TEST_TMPDIR/ssh_calls"
}
