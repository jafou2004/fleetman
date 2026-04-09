#!/usr/bin/env bats
# Unit tests for scripts/commands/pod/ssh.sh

load '../../../test_helper/common'

setup() {
    load_common

    # Mocks before source (will be overwritten when libs are re-sourced)
    select_menu() { SELECTED_IDX=0; }
    ssh_cmd()     { echo "SSH_CMD:$*"; return "${SSH_RC:-0}"; }
    ask_password() { PASSWORD="testpass"; B64_PASS="dGVzdHBhc3M="; }
    check_sshpass() { return 0; }
    export -f select_menu ssh_cmd ask_password check_sshpass

    source "$SCRIPTS_DIR/commands/pod/ssh.sh"

    # Re-mock after source (libs have been re-sourced)
    select_menu() { SELECTED_IDX=0; }
    ssh_cmd()     { echo "SSH_CMD:$*"; return "${SSH_RC:-0}"; }
    ask_password() { PASSWORD="testpass"; B64_PASS="dGVzdHBhc3M="; }
    check_sshpass() { return 0; }

    # Pods directory for local tests
    mkdir -p "$BATS_TEST_TMPDIR/pods/api"
    mkdir -p "$BATS_TEST_TMPDIR/pods/worker"
    export PODS_DIR="$BATS_TEST_TMPDIR/pods"
}

# ── connect (local server) ───────────────────────────────────────────────────

@test "connect: local server with pod → ok 'Local server' + exit 0" {
    export MASTER_HOST="dev1.fleet.test"
    run connect "dev1.fleet.test" "api"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Local server"* ]]
}

@test "connect: local server without pod → ok 'Local server' + exit 0" {
    export MASTER_HOST="dev1.fleet.test"
    run connect "dev1.fleet.test" ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"Local server"* ]]
}

@test "connect: local server with pod → message mentions the pod" {
    export MASTER_HOST="dev1.fleet.test"
    run connect "dev1.fleet.test" "api"
    [[ "$output" == *"api"* ]]
}

# ── connect (remote server) ──────────────────────────────────────────────────

@test "connect: remote server with pod → ssh_cmd -t called with correct path" {
    export MASTER_HOST="__not_local__"
    run connect "dev1.fleet.test" "api"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SSH_CMD:-t dev1.fleet.test"* ]]
    [[ "$output" == *"$PODS_DIR/api"* ]]
}

@test "connect: remote server without pod → ssh_cmd called without -t" {
    export MASTER_HOST="__not_local__"
    run connect "dev1.fleet.test" ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"SSH_CMD:dev1.fleet.test"* ]]
    [[ "$output" != *"SSH_CMD:-t"* ]]
}

@test "connect: remote server with pod → ok message uses short name" {
    export MASTER_HOST="__not_local__"
    run connect "dev1.fleet.test" "api"
    # The ok() message uses short_name() → "dev1", not the FQDN
    [[ "$output" == *"Connecting to dev1"* ]]
}

# ── connect_to_server ─────────────────────────────────────────────────────────

@test "connect_to_server: 1 pod → connect called with the pod" {
    export MASTER_HOST="__not_local__"
    declare -gA server_pods
    server_pods=( ["dev1.fleet.test"]="api" )
    connect() { echo "CONNECT:$1:$2"; }
    run connect_to_server "dev1.fleet.test"
    [[ "$output" == *"CONNECT:dev1.fleet.test:api"* ]]
}

@test "connect_to_server: multiple pods → connect called without pod (empty pod)" {
    export MASTER_HOST="__not_local__"
    declare -gA server_pods
    server_pods=( ["dev1.fleet.test"]="api worker" )
    connect() { echo "CONNECT:$1:$2"; }
    run connect_to_server "dev1.fleet.test"
    [[ "$output" == *"CONNECT:dev1.fleet.test:"* ]]
    # empty pod = no pod after the last ':'
    [[ "$output" != *"CONNECT:dev1.fleet.test:api"* ]]
}

# ── cmd_pod_ssh — validation ──────────────────────────────────────────────────

@test "cmd_pod_ssh: sans -p → exit 1 + 'search term is required'" {
    run cmd_pod_ssh
    [ "$status" -eq 1 ]
    [[ "$output" == *"search term is required"* ]]
}

@test "cmd_pod_ssh: pods.json absent → exit 1" {
    rm -f "$PODS_FILE"
    run cmd_pod_ssh -p api
    [ "$status" -eq 1 ]
}

@test "cmd_pod_ssh: -e invalide → exit 1 + 'invalid environment'" {
    run cmd_pod_ssh -p api -e nosuchenv
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid environment"* ]]
}

@test "cmd_pod_ssh: -p sans argument → exit 1 + 'requires an argument'" {
    run cmd_pod_ssh -p
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires an argument"* ]]
}

# ── cmd_pod_ssh — no results ─────────────────────────────────────────────────

@test "cmd_pod_ssh: -p nonexistent → exit 0 + warn 'No results'" {
    run cmd_pod_ssh -p nonexistent
    [ "$status" -eq 0 ]
    [[ "$output" == *'No results for "nonexistent"'* ]]
}

# ── cmd_pod_ssh — single server ──────────────────────────────────────────────

@test "cmd_pod_ssh: 1 server, 1 pod → connect_to_server called without menu" {
    export MASTER_HOST="__not_local__"
    collect_server_pods() {
        declare -gA server_pods=()
        server_order=()
        server_pods["dev2.fleet.test"]="api"
        server_order=("dev2.fleet.test")
    }
    connect() { echo "CONNECT:$1:$2"; }
    run cmd_pod_ssh -p api -e dev
    [[ "$output" == *"CONNECT:dev2.fleet.test:api"* ]]
}

@test "cmd_pod_ssh: single remote server → check_sshpass called" {
    export MASTER_HOST="__not_local__"
    collect_server_pods() {
        declare -gA server_pods=()
        server_order=()
        server_pods["dev2.fleet.test"]="api"
        server_order=("dev2.fleet.test")
    }
    connect() { return 0; }
    check_sshpass() { echo "X" >> "$BATS_TEST_TMPDIR/sshpass_calls"; }
    run cmd_pod_ssh -p api -e dev
    local count
    count=$(wc -l < "$BATS_TEST_TMPDIR/sshpass_calls" 2>/dev/null || echo 0)
    [ "$count" -ge 1 ]
}

@test "cmd_pod_ssh: local server only → check_sshpass not called" {
    export MASTER_HOST="dev2.fleet.test"
    collect_server_pods() {
        declare -gA server_pods=()
        server_order=()
        server_pods["dev2.fleet.test"]="api"
        server_order=("dev2.fleet.test")
    }
    connect() { return 0; }
    check_sshpass() { echo "X" >> "$BATS_TEST_TMPDIR/sshpass_calls"; }
    run cmd_pod_ssh -p api -e dev
    local count
    count=$(wc -l < "$BATS_TEST_TMPDIR/sshpass_calls" 2>/dev/null || echo 0)
    [ "$count" -eq 0 ]
}

# ── cmd_pod_ssh — multiple servers ───────────────────────────────────────────

@test "cmd_pod_ssh: N servers → select_menu called" {
    export MASTER_HOST="__not_local__"
    collect_server_pods() {
        declare -gA server_pods=()
        server_order=()
        server_pods["dev1.fleet.test"]="api"
        server_pods["dev2.fleet.test"]="api"
        server_order=("dev1.fleet.test" "dev2.fleet.test")
    }
    connect() { return 0; }
    select_menu() { echo "MENU_CALLED"; SELECTED_IDX=0; }
    run cmd_pod_ssh -p api -e dev
    [[ "$output" == *"MENU_CALLED"* ]]
}

@test "cmd_pod_ssh: N servers, selection idx 1 → connect_to_server with server_order[1]" {
    export MASTER_HOST="__not_local__"
    collect_server_pods() {
        declare -gA server_pods=()
        server_order=()
        server_pods["dev1.fleet.test"]="api"
        server_pods["dev2.fleet.test"]="api"
        server_order=("dev1.fleet.test" "dev2.fleet.test")
    }
    connect() { echo "CONNECT:$1:$2"; }
    select_menu() { SELECTED_IDX=1; }
    run cmd_pod_ssh -p api -e dev
    [[ "$output" == *"CONNECT:dev2.fleet.test:api"* ]]
}

@test "cmd_pod_ssh: header displays the env label" {
    export MASTER_HOST="__not_local__"
    collect_server_pods() {
        declare -gA server_pods=()
        server_order=()
        server_pods["dev1.fleet.test"]="api"
        server_pods["dev2.fleet.test"]="api"
        server_order=("dev1.fleet.test" "dev2.fleet.test")
    }
    connect() { return 0; }
    select_menu() { SELECTED_IDX=0; }
    run cmd_pod_ssh -p api -e dev
    [[ "$output" == *"DEV"* ]]
}

# ── Direct coverage (without run, for kcov) ──────────────────────────────────

@test "cmd_pod_ssh: direct call -p nonexistent → warn (coverage)" {
    # Subshell so that exit 0 does not stop the bats test
    ( cmd_pod_ssh -p nonexistent ) > "$BATS_TEST_TMPDIR/out.txt" || true
    grep -q "No results" "$BATS_TEST_TMPDIR/out.txt"
}
