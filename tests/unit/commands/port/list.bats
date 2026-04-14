#!/usr/bin/env bats
# Unit tests for scripts/commands/port/list.sh

load '../../../test_helper/common'

setup() {
    load_common
    source "$SCRIPTS_DIR/lib/ports.sh"
    source "$SCRIPTS_DIR/commands/port/list.sh"
}

# ── Guard: missing files ──────────────────────────────────────────────────────

@test "cmd_port_list: config.json absent → exit 1" {
    rm -f "$CONFIG_FILE"
    run cmd_port_list
    [ "$status" -eq 1 ]
}

@test "cmd_port_list: services.json absent → exit 1 + error message" {
    rm -f "$HOME/.data/services.json"
    run cmd_port_list
    [ "$status" -eq 1 ]
    [[ "$output" == *"services.json not found"* ]]
}

# ── Unknown option ────────────────────────────────────────────────────────────

@test "cmd_port_list: unknown option → exit 1 + 'Unknown option'" {
    run cmd_port_list -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

# ── Empty services ────────────────────────────────────────────────────────────

@test "cmd_port_list: no publishers in services.json → 'No ports in use'" {
    echo '{"dev":{"dev1.fleet.test":{"api":[{"Service":"web","Publishers":[]}]}}}' \
        > "$HOME/.data/services.json"
    run cmd_port_list
    [ "$status" -eq 0 ]
    [[ "$output" == *"No ports in use"* ]]
}

# ── Nominal output ────────────────────────────────────────────────────────────

@test "cmd_port_list: displays PORT POD SERVICE headers" {
    run cmd_port_list
    [ "$status" -eq 0 ]
    [[ "$output" == *"PORT"* ]]
    [[ "$output" == *"POD"* ]]
    [[ "$output" == *"SERVICE"* ]]
}

@test "cmd_port_list: displays environment columns from config.json" {
    run cmd_port_list
    [ "$status" -eq 0 ]
    [[ "$output" == *"DEV"* ]]
    [[ "$output" == *"TEST"* ]]
    [[ "$output" == *"PROD"* ]]
}

@test "cmd_port_list: shows port 8080 with api/web" {
    run cmd_port_list
    [ "$status" -eq 0 ]
    [[ "$output" == *"8080"* ]]
    [[ "$output" == *"api"* ]]
    [[ "$output" == *"web"* ]]
}

@test "cmd_port_list: server shown as short name (no domain)" {
    run cmd_port_list
    [ "$status" -eq 0 ]
    [[ "$output" == *"dev1"* ]]
    [[ "$output" != *"dev1.fleet.test"* ]]
}

@test "cmd_port_list: absent env shows dash" {
    run cmd_port_list
    [ "$status" -eq 0 ]
    # api/db (port 9000) not present in prod → dash in prod column
    [[ "$output" == *"—"* ]]
}

# ── All servers flag ──────────────────────────────────────────────────────────

@test "cmd_port_list: pod with all_servers=true shows 'All srvs'" {
    jq '.pods.api.all_servers = true' "$CONFIG_FILE" \
        > "$BATS_TEST_TMPDIR/t.json" && mv "$BATS_TEST_TMPDIR/t.json" "$CONFIG_FILE"
    run cmd_port_list
    [ "$status" -eq 0 ]
    [[ "$output" == *"All srvs"* ]]
}
