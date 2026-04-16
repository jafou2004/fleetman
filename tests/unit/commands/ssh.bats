#!/usr/bin/env bats
# Unit tests for scripts/commands/ssh.sh

load '../../test_helper/common'

setup() {
    load_common

    # Mocks before source
    select_menu()    { SELECTED_IDX=0; }
    ssh_cmd()        { echo "SSH_CMD:$*"; return "${SSH_RC:-0}"; }
    ask_password()   { PASSWORD="testpass"; B64_PASS="dGVzdHBhc3M="; }
    check_sshpass()  { return 0; }
    export -f select_menu ssh_cmd ask_password check_sshpass

    source "$SCRIPTS_DIR/commands/ssh.sh"

    # Re-mock after source (libs re-sourced internally)
    select_menu()    { SELECTED_IDX=0; }
    ssh_cmd()        { echo "SSH_CMD:$*"; return "${SSH_RC:-0}"; }
    ask_password()   { PASSWORD="testpass"; B64_PASS="dGVzdHBhc3M="; }
    check_sshpass()  { return 0; }
}

# ── connect_server (local) ────────────────────────────────────────────────────

@test "connect_server: local server → ok 'Local server' + exit 0" {
    export MASTER_HOST="dev1.fleet.test"
    run connect_server "dev1.fleet.test"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Local server"* ]]
}

@test "connect_server: local server → ssh_cmd NOT called" {
    export MASTER_HOST="dev1.fleet.test"
    ssh_cmd() { echo "SSH_CALLED"; }
    run connect_server "dev1.fleet.test"
    [[ "$output" != *"SSH_CALLED"* ]]
}

# ── connect_server (remote) ───────────────────────────────────────────────────

@test "connect_server: remote server → ssh_cmd called with fqdn" {
    export MASTER_HOST="__not_local__"
    run connect_server "dev1.fleet.test"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SSH_CMD:dev1.fleet.test"* ]]
}

@test "connect_server: remote server → ok message uses short name" {
    export MASTER_HOST="__not_local__"
    run connect_server "dev1.fleet.test"
    [[ "$output" == *"Connecting to dev1"* ]]
    [[ "$output" != *"Connecting to dev1.fleet.test"* ]]
}

# ── cmd_ssh — option parsing ──────────────────────────────────────────────────

@test "cmd_ssh: -e without argument → exit 1 + 'requires an argument'" {
    run cmd_ssh -e
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires an argument"* ]]
}

@test "cmd_ssh: unknown flag → exit 1 + 'Unknown option'" {
    run cmd_ssh -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "cmd_ssh: invalid -e → exit 1 + 'invalid environment'" {
    run cmd_ssh -e nosuchenv
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid environment"* ]]
}

# ── cmd_ssh — no results ──────────────────────────────────────────────────────

@test "cmd_ssh: -s nonexistent → exit 0 + warn 'No servers found'" {
    run cmd_ssh -s nonexistent
    [ "$status" -eq 0 ]
    [[ "$output" == *"No servers found"* ]]
}

# ── cmd_ssh — single server ───────────────────────────────────────────────────

@test "cmd_ssh: 1 remote server → connect_server called, no menu" {
    export MASTER_HOST="__not_local__"
    collect_servers() {
        server_list=("dev1.fleet.test")
        declare -gA server_envs=(["dev1.fleet.test"]="dev")
    }
    connect_server() { echo "CONNECT:$1"; }
    run cmd_ssh -e dev -s dev1
    [[ "$output" == *"CONNECT:dev1.fleet.test"* ]]
}

@test "cmd_ssh: 1 local server → check_sshpass NOT called" {
    export MASTER_HOST="dev1.fleet.test"
    collect_servers() {
        server_list=("dev1.fleet.test")
        declare -gA server_envs=(["dev1.fleet.test"]="dev")
    }
    connect_server() { return 0; }
    check_sshpass() { echo "X" >> "$BATS_TEST_TMPDIR/calls"; }
    run cmd_ssh
    local count
    count=$(wc -l < "$BATS_TEST_TMPDIR/calls" 2>/dev/null || echo 0)
    [ "$count" -eq 0 ]
}

@test "cmd_ssh: 1 remote server → check_sshpass called" {
    export MASTER_HOST="__not_local__"
    collect_servers() {
        server_list=("dev1.fleet.test")
        declare -gA server_envs=(["dev1.fleet.test"]="dev")
    }
    connect_server() { return 0; }
    check_sshpass() { echo "X" >> "$BATS_TEST_TMPDIR/calls"; }
    run cmd_ssh
    local count
    count=$(wc -l < "$BATS_TEST_TMPDIR/calls" 2>/dev/null || echo 0)
    [ "$count" -ge 1 ]
}

# ── cmd_ssh — multiple servers ────────────────────────────────────────────────

@test "cmd_ssh: N servers → select_menu called" {
    export MASTER_HOST="__not_local__"
    collect_servers() {
        server_list=("dev1.fleet.test" "dev2.fleet.test")
        declare -gA server_envs=(["dev1.fleet.test"]="dev" ["dev2.fleet.test"]="dev")
    }
    connect_server() { return 0; }
    select_menu() { echo "MENU_CALLED"; SELECTED_IDX=0; }
    run cmd_ssh
    [[ "$output" == *"MENU_CALLED"* ]]
}

@test "cmd_ssh: N servers, selection idx 1 → connect_server called with server_list[1]" {
    export MASTER_HOST="__not_local__"
    collect_servers() {
        server_list=("dev1.fleet.test" "dev2.fleet.test")
        declare -gA server_envs=(["dev1.fleet.test"]="dev" ["dev2.fleet.test"]="dev")
    }
    connect_server() { echo "CONNECT:$1"; }
    select_menu() { SELECTED_IDX=1; }
    run cmd_ssh
    [[ "$output" == *"CONNECT:dev2.fleet.test"* ]]
}

@test "cmd_ssh: section header shows env label" {
    export MASTER_HOST="__not_local__"
    collect_servers() {
        server_list=("dev1.fleet.test" "dev2.fleet.test")
        declare -gA server_envs=(["dev1.fleet.test"]="dev" ["dev2.fleet.test"]="dev")
    }
    connect_server() { return 0; }
    select_menu() { SELECTED_IDX=0; }
    run cmd_ssh -e dev
    [[ "$output" == *"DEV"* ]]
}

@test "cmd_ssh: no filter → section header shows ALL" {
    export MASTER_HOST="__not_local__"
    collect_servers() {
        server_list=("dev1.fleet.test" "prod1.fleet.test")
        declare -gA server_envs=(["dev1.fleet.test"]="dev" ["prod1.fleet.test"]="prod")
    }
    connect_server() { return 0; }
    select_menu() { SELECTED_IDX=0; }
    run cmd_ssh
    [[ "$output" == *"ALL"* ]]
}

# ── Direct call (coverage) ────────────────────────────────────────────────────

@test "cmd_ssh: direct call -s nonexistent → warn (coverage)" {
    ( cmd_ssh -s nonexistent ) > "$BATS_TEST_TMPDIR/out.txt" || true
    grep -q "No servers found" "$BATS_TEST_TMPDIR/out.txt"
}
