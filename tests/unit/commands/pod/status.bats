#!/usr/bin/env bats
# Unit tests for scripts/commands/pod/status.sh

load '../../../test_helper/common'

setup() {
    load_common

    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"

    # Mock sudo: removes -S and executes the rest
    cat > "$BATS_TEST_TMPDIR/bin/sudo" << 'EOF'
#!/bin/bash
shift
exec "$@"
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/sudo"

    # Mock docker: returns JSON according to $DOCKER_PS_OUTPUT, code according to $DOCKER_RC
    cat > "$BATS_TEST_TMPDIR/bin/docker" << 'EOF'
#!/bin/bash
if [ "${1:-}" = "compose" ] && [ "${2:-}" = "ps" ]; then
    printf '%s' "${DOCKER_PS_OUTPUT:-}"
    exit "${DOCKER_RC:-0}"
fi
exit "${DOCKER_RC:-0}"
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/docker"

    # Mocks before source
    ssh_cmd()             { printf '%s' "${SSH_CMD_OUTPUT:-}"; return "${SSH_CMD_RC:-0}"; }
    ask_password()        { PASSWORD="testpass"; B64_PASS="dGVzdHBhc3M="; }
    check_sshpass()       { return 0; }
    check_config_file()   { return 0; }
    parse_env()           { ENV="${1:-}"; }
    select_menu()         { SELECTED_IDX=0; }
    find_and_select_pod() { SELECTED_POD="${MOCK_POD:-api}"; label="${MOCK_LABEL:-ALL}"; }
    collect_pod_servers() { pod_servers=("dev1.example.com"); _all=false; }
    export -f ssh_cmd ask_password check_sshpass check_config_file parse_env \
              select_menu find_and_select_pod collect_pod_servers

    source "$SCRIPTS_DIR/commands/pod/status.sh"

    # Re-mock after source (libs have been re-sourced)
    ssh_cmd()             { printf '%s' "${SSH_CMD_OUTPUT:-}"; return "${SSH_CMD_RC:-0}"; }
    ask_password()        { PASSWORD="testpass"; B64_PASS="dGVzdHBhc3M="; }
    check_sshpass()       { return 0; }
    check_config_file()   { return 0; }
    parse_env()           { ENV="${1:-}"; }
    select_menu()         { SELECTED_IDX=0; }
    find_and_select_pod() { SELECTED_POD="${MOCK_POD:-api}"; label="${MOCK_LABEL:-ALL}"; }
    collect_pod_servers() { pod_servers=("dev1.example.com"); _all=false; }

    MASTER_HOST="local.example.com"
    SELECTED_POD="api"
    PODS_DIR="$BATS_TEST_TMPDIR/pods"
    mkdir -p "$BATS_TEST_TMPDIR/pods/api"
    B64_PASS="dGVzdHBhc3M="
    _STATUS_ROWS=()
}

# ── render_status_table ────────────────────────────────────────────────────────

@test "render_status_table: displays column headers" {
    _STATUS_ROWS=("ROW:web$(printf '\t')running$(printf '\t')$(printf '\t')2 hours$(printf '\t')")
    run render_status_table
    [ "$status" -eq 0 ]
    [[ "$output" == *"SERVICE"* ]]
    [[ "$output" == *"STATUS"* ]]
    [[ "$output" == *"UPTIME"* ]]
    [[ "$output" == *"PORTS"* ]]
}

@test "render_status_table: service running → icon ✓ and text running" {
    _STATUS_ROWS=("ROW:web$(printf '\t')running$(printf '\t')$(printf '\t')2 hours$(printf '\t')")
    run render_status_table
    [ "$status" -eq 0 ]
    [[ "$output" == *"✓ running"* ]]
}

@test "render_status_table: service running+healthy → text running (healthy)" {
    _STATUS_ROWS=("ROW:web$(printf '\t')running$(printf '\t')healthy$(printf '\t')2 hours$(printf '\t')")
    run render_status_table
    [[ "$output" == *"running (healthy)"* ]]
}

@test "render_status_table: service running+unhealthy → icon ⚠ and running (unhealthy)" {
    _STATUS_ROWS=("ROW:web$(printf '\t')running$(printf '\t')unhealthy$(printf '\t')2 hours$(printf '\t')")
    run render_status_table
    [[ "$output" == *"⚠ running (unhealthy)"* ]]
}

@test "render_status_table: service running+starting → icon ⚠ and running (starting)" {
    _STATUS_ROWS=("ROW:web$(printf '\t')running$(printf '\t')starting$(printf '\t')2 hours$(printf '\t')")
    run render_status_table
    [[ "$output" == *"⚠ running (starting)"* ]]
}

@test "render_status_table: service exited → icon ✗" {
    _STATUS_ROWS=("ROW:worker$(printf '\t')exited(1)$(printf '\t')$(printf '\t')$(printf '\t')")
    run render_status_table
    [[ "$output" == *"✗ exited(1)"* ]]
}

@test "render_status_table: service dead → icon ✗" {
    _STATUS_ROWS=("ROW:worker$(printf '\t')dead$(printf '\t')$(printf '\t')$(printf '\t')")
    run render_status_table
    [[ "$output" == *"✗ dead"* ]]
}

@test "render_status_table: service paused → icon ⚠" {
    _STATUS_ROWS=("ROW:worker$(printf '\t')paused$(printf '\t')$(printf '\t')$(printf '\t')")
    run render_status_table
    [[ "$output" == *"⚠ paused"* ]]
}

@test "render_status_table: empty uptime → displayed as —" {
    _STATUS_ROWS=("ROW:worker$(printf '\t')exited(1)$(printf '\t')$(printf '\t')$(printf '\t')")
    run render_status_table
    [[ "$output" == *"—"* ]]
}

@test "render_status_table: empty ports → displayed as —" {
    _STATUS_ROWS=("ROW:db$(printf '\t')running$(printf '\t')$(printf '\t')2 hours$(printf '\t')")
    run render_status_table
    # The db service line should contain — (empty PORTS column)
    local db_line
    db_line=$(echo "$output" | grep "db")
    [[ "$db_line" == *"—"* ]]
}

@test "render_status_table: non-empty ports → displayed as-is" {
    _STATUS_ROWS=("ROW:web$(printf '\t')running$(printf '\t')$(printf '\t')2 hours$(printf '\t')8080→80, 443→443")
    run render_status_table
    [[ "$output" == *"8080→80"* ]]
    [[ "$output" == *"443→443"* ]]
}

@test "render_status_table: long service name adjusts column width" {
    _STATUS_ROWS=("ROW:very-long-service-name$(printf '\t')running$(printf '\t')$(printf '\t')2 hours$(printf '\t')")
    run render_status_table
    # Full name must appear without truncation
    [[ "$output" == *"very-long-service-name"* ]]
}

# ── _parse_status_rows ────────────────────────────────────────────────────────

@test "_parse_status_rows: parses a running service with port" {
    local json
    json='{"Service":"web","State":"running","Status":"Up 2 hours","Health":"","Publishers":[{"URL":"0.0.0.0","TargetPort":80,"PublishedPort":8080,"Protocol":"tcp"}]}'
    _parse_status_rows "$json"
    [ "${#_STATUS_ROWS[@]}" -eq 1 ]
    [[ "${_STATUS_ROWS[0]}" == *"ROW:web"* ]]
    [[ "${_STATUS_ROWS[0]}" == *"running"* ]]
    [[ "${_STATUS_ROWS[0]}" == *"8080→80"* ]]
}

@test "_parse_status_rows: extracts uptime from Status starting with 'Up '" {
    local json
    json='{"Service":"web","State":"running","Status":"Up 2 hours","Health":"","Publishers":[]}'
    _parse_status_rows "$json"
    [[ "${_STATUS_ROWS[0]}" == *"$(printf '\t')2 hours$(printf '\t')"* ]]
}

@test "_parse_status_rows: empty uptime if Status does not start with 'Up '" {
    local json
    json='{"Service":"worker","State":"exited","Status":"Exited (1) 2 hours ago","Health":"","Publishers":[]}'
    _parse_status_rows "$json"
    local stripped="${_STATUS_ROWS[0]#ROW:}"
    local uptime
    IFS=$'\t' read -r _ _ _ uptime _ <<< "$stripped"
    [ -z "$uptime" ]
}

@test "_parse_status_rows: extracts health state" {
    local json
    json='{"Service":"web","State":"running","Status":"Up 1 hour","Health":"healthy","Publishers":[]}'
    _parse_status_rows "$json"
    [[ "${_STATUS_ROWS[0]}" == *"$(printf '\t')healthy$(printf '\t')"* ]]
}

@test "_parse_status_rows: IP 0.0.0.0 omitted from ports" {
    local json
    json='{"Service":"web","State":"running","Status":"Up 1 hour","Health":"","Publishers":[{"URL":"0.0.0.0","TargetPort":80,"PublishedPort":8080,"Protocol":"tcp"}]}'
    _parse_status_rows "$json"
    [[ "${_STATUS_ROWS[0]}" != *"0.0.0.0"* ]]
    [[ "${_STATUS_ROWS[0]}" == *"8080→80"* ]]
}

@test "_parse_status_rows: non-0.0.0.0 IP → port displayed without IP" {
    local json
    json='{"Service":"web","State":"running","Status":"Up 1 hour","Health":"","Publishers":[{"URL":"127.0.0.1","TargetPort":80,"PublishedPort":8080,"Protocol":"tcp"}]}'
    _parse_status_rows "$json"
    [[ "${_STATUS_ROWS[0]}" == *"8080→80"* ]]
}

@test "_parse_status_rows: tcp protocol omitted" {
    local json
    json='{"Service":"web","State":"running","Status":"Up 1 hour","Health":"","Publishers":[{"URL":"0.0.0.0","TargetPort":80,"PublishedPort":8080,"Protocol":"tcp"}]}'
    _parse_status_rows "$json"
    [[ "${_STATUS_ROWS[0]}" != *"/tcp"* ]]
}

@test "_parse_status_rows: non-tcp protocol displayed" {
    local json
    json='{"Service":"dns","State":"running","Status":"Up 1 hour","Health":"","Publishers":[{"URL":"0.0.0.0","TargetPort":53,"PublishedPort":5353,"Protocol":"udp"}]}'
    _parse_status_rows "$json"
    [[ "${_STATUS_ROWS[0]}" == *"/udp"* ]]
}

@test "_parse_status_rows: unpublished port (PublishedPort=0) excluded" {
    local json
    json='{"Service":"db","State":"running","Status":"Up 1 hour","Health":"","Publishers":[{"URL":"","TargetPort":5432,"PublishedPort":0,"Protocol":"tcp"}]}'
    _parse_status_rows "$json"
    local stripped="${_STATUS_ROWS[0]#ROW:}"
    local ports
    IFS=$'\t' read -r _ _ _ _ ports <<< "$stripped"
    [ -z "$ports" ]
}

@test "_parse_status_rows: multiple services → multiple entries in _STATUS_ROWS" {
    local json
    json='{"Service":"web","State":"running","Status":"Up 1 hour","Health":"","Publishers":[]}
{"Service":"db","State":"running","Status":"Up 1 hour","Health":"","Publishers":[]}'
    _parse_status_rows "$json"
    [ "${#_STATUS_ROWS[@]}" -eq 2 ]
}

@test "_parse_status_rows: empty lines ignored" {
    _parse_status_rows $'\n\n'
    [ "${#_STATUS_ROWS[@]}" -eq 0 ]
}

# ── show_status — local branch ───────────────────────────────────────────────

@test "show_status local: pod dir absent → return 0 + warn 'not found'" {
    rm -rf "$PODS_DIR/api"
    run show_status "local.example.com"
    [ "$status" -eq 0 ]
    [[ "$output" == *"not found"* ]]
}

@test "show_status local: docker compose fails → return 1 + err 'failed'" {
    export DOCKER_RC=1
    run show_status "local.example.com"
    [ "$status" -eq 1 ]
    [[ "$output" == *"✗"* ]]
    [[ "$output" == *"failed"* ]]
}

@test "show_status local: docker returns empty JSON → warn 'no services found'" {
    export DOCKER_PS_OUTPUT=""
    run show_status "local.example.com"
    [ "$status" -eq 0 ]
    [[ "$output" == *"no services found"* ]]
}

@test "show_status local: docker returns valid JSON → displays table" {
    export DOCKER_PS_OUTPUT='{"Service":"web","State":"running","Status":"Up 1 hour","Health":"","Publishers":[]}'
    run show_status "local.example.com"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SERVICE"* ]]
    [[ "$output" == *"web"* ]]
}

# ── show_status — remote branch ──────────────────────────────────────────────

@test "show_status remote: SSH unreachable → return 1 + err 'unreachable'" {
    SSH_CMD_RC=1
    run show_status "prod1.example.com"
    [ "$status" -eq 1 ]
    [[ "$output" == *"unreachable"* ]]
}

@test "show_status remote: SSH returns ABSENT → return 0 + warn 'not found'" {
    SSH_CMD_OUTPUT="ABSENT"
    SSH_CMD_RC=0
    run show_status "prod1.example.com"
    [ "$status" -eq 0 ]
    [[ "$output" == *"not found"* ]]
}

@test "show_status remote: SSH returns FAILED → return 1 + err 'failed'" {
    SSH_CMD_OUTPUT="FAILED"
    SSH_CMD_RC=0
    run show_status "prod1.example.com"
    [ "$status" -eq 1 ]
    [[ "$output" == *"✗"* ]]
    [[ "$output" == *"failed"* ]]
}

@test "show_status remote: SSH returns empty JSON → warn 'no services found'" {
    SSH_CMD_OUTPUT=""
    SSH_CMD_RC=0
    run show_status "prod1.example.com"
    [ "$status" -eq 0 ]
    [[ "$output" == *"no services found"* ]]
}

@test "show_status remote: SSH returns valid JSON → displays table" {
    SSH_CMD_OUTPUT='{"Service":"api","State":"running","Status":"Up 2 hours","Health":"","Publishers":[]}'
    SSH_CMD_RC=0
    run show_status "prod1.example.com"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SERVICE"* ]]
    [[ "$output" == *"api"* ]]
}

# ── cmd_pod_status — validation ───────────────────────────────────────────────

@test "cmd_pod_status: without -p → exit 1 + 'required'" {
    run cmd_pod_status
    [ "$status" -eq 1 ]
    [[ "$output" == *"required"* ]]
}

@test "cmd_pod_status: -p without argument → exit 1 + 'requires an argument'" {
    run cmd_pod_status -p
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires an argument"* ]]
}

@test "cmd_pod_status: unknown option → exit 1 + 'Unknown option'" {
    run cmd_pod_status -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "cmd_pod_status: find_and_select_pod fails → exit 1" {
    find_and_select_pod() { err "No pod matching"; exit 1; }
    run cmd_pod_status -p nosuch
    [ "$status" -eq 1 ]
}

# ── cmd_pod_status — behavior ────────────────────────────────────────────────

@test "cmd_pod_status: section header contains pod name and label" {
    show_status() { :; }
    run cmd_pod_status -p api
    [[ "$output" == *"pod status: api"* ]]
    [[ "$output" == *"ALL"* ]]
}

@test "cmd_pod_status: displays the target server name" {
    show_status() { :; }
    run cmd_pod_status -p api
    [[ "$output" == *"Server:"* ]]
    [[ "$output" == *"dev1.example.com"* ]]
}

@test "cmd_pod_status: single server → show_status called directly (without menu)" {
    local called=""
    show_status() { called="$1"; }
    collect_pod_servers() { pod_servers=("prod1.example.com"); _all=false; }
    cmd_pod_status -p api
    [ "$called" = "prod1.example.com" ]
}

@test "cmd_pod_status: multiple servers → menu displayed, correct server selected" {
    local menu_called=0
    select_menu() { SELECTED_IDX=1; menu_called=1; }
    collect_pod_servers() { pod_servers=("dev1.example.com" "dev2.example.com"); _all=false; }
    local called=""
    show_status() { called="$1"; }
    cmd_pod_status -p api
    [ "$menu_called" -eq 1 ]
    [ "$called" = "dev2.example.com" ]
}

@test "cmd_pod_status: PASSWORD cleared after execution" {
    show_status() { :; }
    cmd_pod_status -p api
    [ -z "${PASSWORD:-}" ]
}

# ── Direct coverage (without run, for kcov) ──────────────────────────────────

@test "render_status_table: direct call running (coverage)" {
    _STATUS_ROWS=("ROW:web$(printf '\t')running$(printf '\t')$(printf '\t')1 hour$(printf '\t')")
    render_status_table > "$BATS_TEST_TMPDIR/out.txt"
    grep -q "web" "$BATS_TEST_TMPDIR/out.txt"
}

@test "_parse_status_rows: direct call (coverage)" {
    local json='{"Service":"web","State":"running","Status":"Up 1 hour","Health":"","Publishers":[]}'
    _parse_status_rows "$json"
    [ "${#_STATUS_ROWS[@]}" -eq 1 ]
}

@test "show_status local: direct call pod absent (coverage)" {
    rm -rf "$PODS_DIR/api"
    show_status "local.example.com" > "$BATS_TEST_TMPDIR/out.txt" || true
    grep -q "not found" "$BATS_TEST_TMPDIR/out.txt"
}
