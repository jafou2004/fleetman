#!/usr/bin/env bats
# Unit tests for scripts/commands/port/check.sh

load '../../../test_helper/common'

setup() {
    load_common
    source "$SCRIPTS_DIR/lib/ports.sh"
    source "$SCRIPTS_DIR/commands/port/check.sh"
}

# ── Guards ────────────────────────────────────────────────────────────────────

@test "cmd_port_check: config.json absent → exit 1" {
    rm -f "$CONFIG_FILE"
    run cmd_port_check 8000
    [ "$status" -eq 1 ]
}

@test "cmd_port_check: services.json absent → exit 1 + error" {
    rm -f "$HOME/.data/services.json"
    run cmd_port_check 8000
    [ "$status" -eq 1 ]
    [[ "$output" == *"services.json not found"* ]]
}

@test "cmd_port_check: no arguments → exit 1 + usage hint" {
    run cmd_port_check
    [ "$status" -eq 1 ]
    [[ "$output" == *"port number"* ]]
}

@test "cmd_port_check: unknown option → exit 1" {
    run cmd_port_check -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "cmd_port_check: non-integer argument → exit 1 + 'Invalid port'" {
    run cmd_port_check abc
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid port"* ]]
}

# ── Free port ─────────────────────────────────────────────────────────────────

@test "cmd_port_check: free port → ✓ and exit 0" {
    run cmd_port_check 8000
    [ "$status" -eq 0 ]
    [[ "$output" == *"✓"* ]]
    [[ "$output" == *"free"* ]]
}

@test "cmd_port_check: free port → port number in output" {
    run cmd_port_check 8000
    [ "$status" -eq 0 ]
    [[ "$output" == *"8000"* ]]
}

# ── Used port ─────────────────────────────────────────────────────────────────

@test "cmd_port_check: used port → ✗ and exit 1" {
    run cmd_port_check 8080
    [ "$status" -eq 1 ]
    [[ "$output" == *"✗"* ]]
}

@test "cmd_port_check: used port → shows pod and service" {
    run cmd_port_check 8080
    [ "$status" -eq 1 ]
    [[ "$output" == *"api / web"* ]]
}

@test "cmd_port_check: used port → shows env in brackets" {
    run cmd_port_check 8080
    [ "$status" -eq 1 ]
    [[ "$output" == *"[dev]"* ]]
}

@test "cmd_port_check: used port → shows short server names" {
    run cmd_port_check 8080
    [ "$status" -eq 1 ]
    # dev1 and dev2 both host api/web on port 8080
    [[ "$output" == *"dev1"* ]]
    [[ "$output" == *"dev2"* ]]
    # full FQDN should not appear
    [[ "$output" != *".fleet.test"* ]]
}

@test "cmd_port_check: used port 9000 → shows only dev and test envs" {
    run cmd_port_check 9000
    [ "$status" -eq 1 ]
    [[ "$output" == *"[dev]"* ]]
    [[ "$output" == *"[test]"* ]]
    # prod has no port 9000
    [[ "$output" != *"[prod]"* ]]
}

# ── Multiple ports ────────────────────────────────────────────────────────────

@test "cmd_port_check: one free one used → exit 1" {
    run cmd_port_check 8000 8080
    [ "$status" -eq 1 ]
}

@test "cmd_port_check: one free one used → both shown in output" {
    run cmd_port_check 8000 8080
    [ "$status" -eq 1 ]
    [[ "$output" == *"✓"* ]]
    [[ "$output" == *"✗"* ]]
    [[ "$output" == *"8000"* ]]
    [[ "$output" == *"8080"* ]]
}

@test "cmd_port_check: all free → exit 0" {
    run cmd_port_check 8000 8001 8002
    [ "$status" -eq 0 ]
}

@test "cmd_port_check: multiple used ports → details shown for all" {
    run cmd_port_check 8080 9000
    [ "$status" -eq 1 ]
    # 8080 detail
    [[ "$output" == *"api / web"* ]]
    # 9000 detail
    [[ "$output" == *"api / db"* ]]
    # both show env
    [[ "$output" == *"[dev]"* ]]
}

@test "cmd_port_check: port 8081 → shows all three envs" {
    run cmd_port_check 8081
    [ "$status" -eq 1 ]
    # worker/app is deployed in dev, test, and prod
    [[ "$output" == *"worker / app"* ]]
    [[ "$output" == *"[dev]"* ]]
    [[ "$output" == *"[test]"* ]]
    [[ "$output" == *"[prod]"* ]]
}
