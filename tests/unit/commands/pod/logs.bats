#!/usr/bin/env bats
# Unit tests for scripts/commands/pod/logs.sh

load '../../../test_helper/common'

setup() {
    load_common

    # Mocks before source (will be overwritten when libs are re-sourced)
    select_menu()   { SELECTED_IDX=0; }
    ssh_cmd()       { echo "SSH_CMD:$*"; return "${SSH_RC:-0}"; }
    ask_password()  { PASSWORD="testpass"; B64_PASS="dGVzdHBhc3M="; }
    check_sshpass() { return 0; }
    sudo_run()      { echo "SUDO_RUN:$*"; }
    _spin_start()   { :; }
    _spin_stop()    { :; }
    export -f select_menu ssh_cmd ask_password check_sshpass sudo_run _spin_start _spin_stop

    source "$SCRIPTS_DIR/commands/pod/logs.sh"

    # Re-mock after source (libs have been re-sourced)
    select_menu()   { SELECTED_IDX=0; }
    ssh_cmd()       { echo "SSH_CMD:$*"; return "${SSH_RC:-0}"; }
    ask_password()  { PASSWORD="testpass"; B64_PASS="dGVzdHBhc3M="; }
    check_sshpass() { return 0; }
    sudo_run()      { echo "SUDO_RUN:$*"; }
    _spin_start()   { :; }
    _spin_stop()    { :; }

    mkdir -p "$BATS_TEST_TMPDIR/pods/api"
    mkdir -p "$BATS_TEST_TMPDIR/pods/worker"
    export PODS_DIR="$BATS_TEST_TMPDIR/pods"

    # Copy the services.json fixture to DATA_DIR (already created by load_common)
    cp "$FIXTURES_DIR/services.json" "$DATA_DIR/services.json"
}

# ── show_logs — local server ──────────────────────────────────────────────────

@test "show_logs: local server → sudo_run called with pod path, without service" {
    export MASTER_HOST="dev1.fleet.test"
    TAIL_LINES=50
    SERVICE=""
    run show_logs "dev1.fleet.test" "api"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SUDO_RUN"* ]]
    [[ "$output" == *"$PODS_DIR/api/docker-compose.yml"* ]]
    # SERVICE="" → the command ends with "-f" without a service argument
    [[ "$output" =~ ' -f'$ ]]
}

@test "show_logs: local server with SERVICE → sudo_run includes the service" {
    export MASTER_HOST="dev1.fleet.test"
    TAIL_LINES=50
    SERVICE="worker"
    run show_logs "dev1.fleet.test" "api"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SUDO_RUN"* ]]
    [[ "$output" == *"worker"* ]]
}

@test "show_logs: local server with TAIL_LINES=100 → --tail=100 in the command" {
    export MASTER_HOST="dev1.fleet.test"
    TAIL_LINES=100
    SERVICE=""
    run show_logs "dev1.fleet.test" "api"
    [ "$status" -eq 0 ]
    [[ "$output" == *"--tail=100"* ]]
}

# ── show_logs — remote server ─────────────────────────────────────────────────

@test "show_logs: remote server → ssh_cmd -t called with correct server" {
    export MASTER_HOST="__not_local__"
    TAIL_LINES=50
    SERVICE=""
    export B64_PASS="dGVzdHBhc3M="
    run show_logs "dev1.fleet.test" "api"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SSH_CMD:-t dev1.fleet.test"* ]]
}

@test "show_logs: remote server → B64_PASS included in the command" {
    export MASTER_HOST="__not_local__"
    TAIL_LINES=50
    SERVICE=""
    export B64_PASS="dGVzdHBhc3M="
    run show_logs "dev1.fleet.test" "api"
    [ "$status" -eq 0 ]
    [[ "$output" == *"dGVzdHBhc3M="* ]]
}

@test "show_logs: remote server with SERVICE=web → web included in the command" {
    export MASTER_HOST="__not_local__"
    TAIL_LINES=50
    SERVICE="web"
    export B64_PASS="dGVzdHBhc3M="
    run show_logs "dev1.fleet.test" "api"
    [ "$status" -eq 0 ]
    [[ "$output" == *"web"* ]]
}

# ── _select_service_menu ──────────────────────────────────────────────────────

@test "_select_service_menu: services.json absent → warn + SERVICE reste vide" {
    rm -f "$DATA_DIR/services.json"
    SERVICE=""
    _select_service_menu "dev1.fleet.test" "api" > "$BATS_TEST_TMPDIR/out.txt"
    grep -q "missing" "$BATS_TEST_TMPDIR/out.txt"
    [ -z "$SERVICE" ]
}

@test "_select_service_menu: 1 service → SERVICE assigned directly without menu" {
    select_menu() { echo "X" >> "$BATS_TEST_TMPDIR/menu_calls"; SELECTED_IDX=0; }
    SERVICE=""
    # dev2.fleet.test/api has 1 service only: "web"
    _select_service_menu "dev2.fleet.test" "api" > /dev/null
    [ "$SERVICE" = "web" ]
    local count
    count=$(wc -l < "$BATS_TEST_TMPDIR/menu_calls" 2>/dev/null || echo 0)
    [ "$count" -eq 0 ]
}

@test "_select_service_menu: N services → select_menu called + SERVICE assigned" {
    local _call=0
    select_menu() {
        echo "X" >> "$BATS_TEST_TMPDIR/menu_calls"
        SELECTED_IDX=0
    }
    SERVICE=""
    # dev1.fleet.test/api has 2 services: "db" and "web" (sorted → idx 0 = "db")
    _select_service_menu "dev1.fleet.test" "api" > /dev/null
    local count
    count=$(wc -l < "$BATS_TEST_TMPDIR/menu_calls" 2>/dev/null || echo 0)
    [ "$count" -ge 1 ]
    [ "$SERVICE" = "db" ]
}

@test "_select_service_menu: N services, SELECTED_IDX=1 → SERVICE = second entry" {
    select_menu() { SELECTED_IDX=1; }
    SERVICE=""
    # dev1.fleet.test/api → sorted: "db"(0), "web"(1)
    _select_service_menu "dev1.fleet.test" "api" > /dev/null
    [ "$SERVICE" = "web" ]
}

@test "_select_service_menu: serveur absent dans services.json → warn + SERVICE reste vide" {
    SERVICE=""
    _select_service_menu "unknown.fleet.test" "api" > "$BATS_TEST_TMPDIR/out.txt"
    grep -q "not found" "$BATS_TEST_TMPDIR/out.txt"
    [ -z "$SERVICE" ]
}

@test "_select_service_menu: pod absent dans services.json → warn + SERVICE reste vide" {
    SERVICE=""
    _select_service_menu "dev1.fleet.test" "nosuchpod" > "$BATS_TEST_TMPDIR/out.txt"
    grep -q "No service" "$BATS_TEST_TMPDIR/out.txt"
    [ -z "$SERVICE" ]
}

# ── connect_to_server ─────────────────────────────────────────────────────────

@test "connect_to_server: 1 pod → show_logs called with correct server and pod" {
    export MASTER_HOST="__not_local__"
    SELECT_SERVICE=false
    show_logs() { echo "SHOW_LOGS:$1:$2"; }
    declare -gA server_pods
    server_pods=( ["dev1.fleet.test"]="api" )
    run connect_to_server "dev1.fleet.test"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SHOW_LOGS:dev1.fleet.test:api"* ]]
}

@test "connect_to_server: 1 pod → select_menu not called" {
    export MASTER_HOST="__not_local__"
    SELECT_SERVICE=false
    show_logs() { echo "SHOW_LOGS:$1:$2"; }
    declare -gA server_pods
    server_pods=( ["dev1.fleet.test"]="api" )
    select_menu() { echo "X" >> "$BATS_TEST_TMPDIR/menu_calls"; SELECTED_IDX=0; }
    run connect_to_server "dev1.fleet.test"
    local count
    count=$(wc -l < "$BATS_TEST_TMPDIR/menu_calls" 2>/dev/null || echo 0)
    [ "$count" -eq 0 ]
}

@test "connect_to_server: multiple pods → select_menu called" {
    export MASTER_HOST="__not_local__"
    SELECT_SERVICE=false
    show_logs() { echo "SHOW_LOGS:$1:$2"; }
    declare -gA server_pods
    server_pods=( ["dev1.fleet.test"]="api worker" )
    select_menu() { echo "X" >> "$BATS_TEST_TMPDIR/menu_calls"; SELECTED_IDX=0; }
    run connect_to_server "dev1.fleet.test"
    local count
    count=$(wc -l < "$BATS_TEST_TMPDIR/menu_calls" 2>/dev/null || echo 0)
    [ "$count" -ge 1 ]
}

@test "connect_to_server: multiple pods, SELECTED_IDX=1 → show_logs called with worker" {
    export MASTER_HOST="__not_local__"
    SELECT_SERVICE=false
    show_logs() { echo "SHOW_LOGS:$1:$2"; }
    declare -gA server_pods
    server_pods=( ["dev1.fleet.test"]="api worker" )
    select_menu() { SELECTED_IDX=1; }
    run connect_to_server "dev1.fleet.test"
    [[ "$output" == *"SHOW_LOGS:dev1.fleet.test:worker"* ]]
}

@test "connect_to_server: SELECT_SERVICE=true → _select_service_menu called" {
    SELECT_SERVICE=true
    show_logs() { return 0; }
    _select_service_menu() { echo "X" >> "$BATS_TEST_TMPDIR/menu_calls"; }
    declare -gA server_pods
    server_pods=( ["dev1.fleet.test"]="api" )
    run connect_to_server "dev1.fleet.test"
    local count
    count=$(wc -l < "$BATS_TEST_TMPDIR/menu_calls" 2>/dev/null || echo 0)
    [ "$count" -ge 1 ]
}

@test "connect_to_server: SELECT_SERVICE=false → _select_service_menu not called" {
    SELECT_SERVICE=false
    show_logs() { return 0; }
    _select_service_menu() { echo "X" >> "$BATS_TEST_TMPDIR/menu_calls"; }
    declare -gA server_pods
    server_pods=( ["dev1.fleet.test"]="api" )
    run connect_to_server "dev1.fleet.test"
    local count
    count=$(wc -l < "$BATS_TEST_TMPDIR/menu_calls" 2>/dev/null || echo 0)
    [ "$count" -eq 0 ]
}

# ── cmd_pod_logs — validation ─────────────────────────────────────────────────

@test "cmd_pod_logs: sans -p → exit 1 + 'search term is required'" {
    run cmd_pod_logs
    [ "$status" -eq 1 ]
    [[ "$output" == *"search term is required"* ]]
}

@test "cmd_pod_logs: -p sans argument → exit 1 + 'requires an argument'" {
    run cmd_pod_logs -p
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires an argument"* ]]
}

@test "cmd_pod_logs: -e invalide → exit 1 + 'invalid environment'" {
    run cmd_pod_logs -p api -e nosuchenv
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid environment"* ]]
}

@test "cmd_pod_logs: pods.json absent → exit 1" {
    rm -f "$PODS_FILE"
    run cmd_pod_logs -p api
    [ "$status" -eq 1 ]
}

# ── cmd_pod_logs — no results ────────────────────────────────────────────────

@test "cmd_pod_logs: -p nonexistent → exit 0 + warn 'No results'" {
    run cmd_pod_logs -p nonexistent
    [ "$status" -eq 0 ]
    [[ "$output" == *'No results for "nonexistent"'* ]]
}

# ── cmd_pod_logs — single server ─────────────────────────────────────────────

@test "cmd_pod_logs: 1 server → connect_to_server called without server menu" {
    export MASTER_HOST="__not_local__"
    collect_server_pods() {
        declare -gA server_pods=()
        server_order=()
        server_pods["dev2.fleet.test"]="api"
        server_order=("dev2.fleet.test")
    }
    show_logs() { echo "SHOW_LOGS:$1:$2"; }
    select_menu() { echo "X" >> "$BATS_TEST_TMPDIR/menu_calls"; SELECTED_IDX=0; }
    run cmd_pod_logs -p api -e dev
    [[ "$output" == *"SHOW_LOGS:dev2.fleet.test:api"* ]]
    local count
    count=$(wc -l < "$BATS_TEST_TMPDIR/menu_calls" 2>/dev/null || echo 0)
    [ "$count" -eq 0 ]
}

@test "cmd_pod_logs: ask_password always called" {
    export MASTER_HOST="__not_local__"
    collect_server_pods() {
        declare -gA server_pods=()
        server_order=()
        server_pods["dev2.fleet.test"]="api"
        server_order=("dev2.fleet.test")
    }
    show_logs() { return 0; }
    ask_password() { echo "X" >> "$BATS_TEST_TMPDIR/askpass_calls"; PASSWORD="testpass"; B64_PASS="dGVzdHBhc3M="; }
    run cmd_pod_logs -p api -e dev
    local count
    count=$(wc -l < "$BATS_TEST_TMPDIR/askpass_calls" 2>/dev/null || echo 0)
    [ "$count" -ge 1 ]
}

# ── cmd_pod_logs — multiple servers ──────────────────────────────────────────

@test "cmd_pod_logs: N servers → select_menu called" {
    export MASTER_HOST="__not_local__"
    collect_server_pods() {
        declare -gA server_pods=()
        server_order=()
        server_pods["dev1.fleet.test"]="api"
        server_pods["dev2.fleet.test"]="api"
        server_order=("dev1.fleet.test" "dev2.fleet.test")
    }
    show_logs() { return 0; }
    select_menu() { echo "MENU_CALLED"; SELECTED_IDX=0; }
    run cmd_pod_logs -p api -e dev
    [[ "$output" == *"MENU_CALLED"* ]]
}

@test "cmd_pod_logs: N servers, selection idx 1 → connect_to_server with server_order[1]" {
    export MASTER_HOST="__not_local__"
    collect_server_pods() {
        declare -gA server_pods=()
        server_order=()
        server_pods["dev1.fleet.test"]="api"
        server_pods["dev2.fleet.test"]="api"
        server_order=("dev1.fleet.test" "dev2.fleet.test")
    }
    show_logs() { echo "SHOW_LOGS:$1:$2"; }
    select_menu() { SELECTED_IDX=1; }
    run cmd_pod_logs -p api -e dev
    [[ "$output" == *"SHOW_LOGS:dev2.fleet.test:api"* ]]
}

@test "cmd_pod_logs: header with -e dev → 'DEV' in the output" {
    export MASTER_HOST="__not_local__"
    collect_server_pods() {
        declare -gA server_pods=()
        server_order=()
        server_pods["dev1.fleet.test"]="api"
        server_pods["dev2.fleet.test"]="api"
        server_order=("dev1.fleet.test" "dev2.fleet.test")
    }
    show_logs() { return 0; }
    select_menu() { SELECTED_IDX=0; }
    run cmd_pod_logs -p api -e dev
    [[ "$output" == *"DEV"* ]]
}

@test "cmd_pod_logs: header without -e → 'ALL' in the output" {
    export MASTER_HOST="__not_local__"
    collect_server_pods() {
        declare -gA server_pods=()
        server_order=()
        server_pods["dev1.fleet.test"]="api"
        server_pods["dev2.fleet.test"]="api"
        server_order=("dev1.fleet.test" "dev2.fleet.test")
    }
    show_logs() { return 0; }
    select_menu() { SELECTED_IDX=0; }
    run cmd_pod_logs -p api
    [[ "$output" == *"ALL"* ]]
}

@test "cmd_pod_logs: -n 100 → TAIL_LINES=100 passed to show_logs" {
    export MASTER_HOST="__not_local__"
    collect_server_pods() {
        declare -gA server_pods=()
        server_order=()
        server_pods["dev2.fleet.test"]="api"
        server_order=("dev2.fleet.test")
    }
    show_logs() { echo "TAIL:$TAIL_LINES"; }
    run cmd_pod_logs -p api -n 100
    [[ "$output" == *"TAIL:100"* ]]
}

@test "cmd_pod_logs: -s worker → SERVICE=worker passed to show_logs" {
    export MASTER_HOST="__not_local__"
    collect_server_pods() {
        declare -gA server_pods=()
        server_order=()
        server_pods["dev2.fleet.test"]="api"
        server_order=("dev2.fleet.test")
    }
    show_logs() { echo "SERVICE_VAL:$SERVICE"; }
    run cmd_pod_logs -p api -s worker
    [[ "$output" == *"SERVICE_VAL:worker"* ]]
}

# ── cmd_pod_logs — interactive service selection (-s without argument) ────────

@test "cmd_pod_logs: -s without argument → _select_service_menu called" {
    export MASTER_HOST="__not_local__"
    collect_server_pods() {
        declare -gA server_pods=()
        server_order=()
        server_pods["dev2.fleet.test"]="api"
        server_order=("dev2.fleet.test")
    }
    show_logs() { return 0; }
    _select_service_menu() { echo "SERVICE_MENU_CALLED"; }
    run cmd_pod_logs -p api -s
    [[ "$output" == *"SERVICE_MENU_CALLED"* ]]
}

@test "cmd_pod_logs: -s without argument + -p → SELECT_SERVICE active, -p recognized" {
    export MASTER_HOST="__not_local__"
    collect_server_pods() {
        declare -gA server_pods=()
        server_order=()
        server_pods["dev2.fleet.test"]="api"
        server_order=("dev2.fleet.test")
    }
    show_logs() { return 0; }
    _select_service_menu() { echo "SERVICE_MENU_CALLED"; }
    # -s in last position, -p before
    run cmd_pod_logs -p api -s
    [ "$status" -eq 0 ]
    [[ "$output" == *"SERVICE_MENU_CALLED"* ]]
}

@test "cmd_pod_logs: -s worker (with value) → SELECT_SERVICE inactive, SERVICE=worker" {
    export MASTER_HOST="__not_local__"
    collect_server_pods() {
        declare -gA server_pods=()
        server_order=()
        server_pods["dev2.fleet.test"]="api"
        server_order=("dev2.fleet.test")
    }
    _select_service_menu() { echo "SERVICE_MENU_CALLED"; }
    show_logs() { echo "SERVICE_VAL:$SERVICE"; }
    run cmd_pod_logs -p api -s worker
    [[ "$output" != *"SERVICE_MENU_CALLED"* ]]
    [[ "$output" == *"SERVICE_VAL:worker"* ]]
}

@test "cmd_pod_logs: -s without argument + services.json absent → warn displayed" {
    rm -f "$DATA_DIR/services.json"
    export MASTER_HOST="__not_local__"
    collect_server_pods() {
        declare -gA server_pods=()
        server_order=()
        server_pods["dev2.fleet.test"]="api"
        server_order=("dev2.fleet.test")
    }
    show_logs() { return 0; }
    run cmd_pod_logs -p api -s
    [ "$status" -eq 0 ]
    [[ "$output" == *"missing"* ]]
}

# ── Direct coverage (without run, for kcov) ──────────────────────────────────

@test "show_logs local: direct call → local branch coverage" {
    export MASTER_HOST="dev1.fleet.test"
    TAIL_LINES=50
    SERVICE=""
    sudo_run() { echo "SUDO_RUN:$*"; }
    ( show_logs "dev1.fleet.test" "api" ) > "$BATS_TEST_TMPDIR/out.txt" || true
    grep -q "SUDO_RUN" "$BATS_TEST_TMPDIR/out.txt"
}

@test "cmd_pod_logs: direct call -p nonexistent → warn (coverage)" {
    ( cmd_pod_logs -p nonexistent ) > "$BATS_TEST_TMPDIR/out.txt" || true
    grep -q "No results" "$BATS_TEST_TMPDIR/out.txt"
}

@test "_select_service_menu: direct call, 1 service → direct assignment branch coverage" {
    SERVICE=""
    _select_service_menu "dev2.fleet.test" "api" > /dev/null
    [ "$SERVICE" = "web" ]
}
