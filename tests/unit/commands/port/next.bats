#!/usr/bin/env bats
# Unit tests for scripts/commands/port/next.sh

load '../../../test_helper/common'

setup() {
    load_common
    source "$SCRIPTS_DIR/lib/ports.sh"
    source "$SCRIPTS_DIR/commands/port/next.sh"
    # Add port_range to fixture config
    jq '. + {"port_range": {"min": 8000, "max": 9010}}' "$CONFIG_FILE" \
        > "$BATS_TEST_TMPDIR/t.json" && mv "$BATS_TEST_TMPDIR/t.json" "$CONFIG_FILE"
}

# ── Guards ────────────────────────────────────────────────────────────────────

@test "cmd_port_next: config.json absent → exit 1" {
    rm -f "$CONFIG_FILE"
    run cmd_port_next
    [ "$status" -eq 1 ]
}

@test "cmd_port_next: services.json absent → exit 1 + error" {
    rm -f "$HOME/.data/services.json"
    run cmd_port_next
    [ "$status" -eq 1 ]
    [[ "$output" == *"services.json not found"* ]]
}

@test "cmd_port_next: port_range absent → exit 1 + error" {
    jq 'del(.port_range)' "$CONFIG_FILE" > "$BATS_TEST_TMPDIR/t.json" \
        && mv "$BATS_TEST_TMPDIR/t.json" "$CONFIG_FILE"
    run cmd_port_next
    [ "$status" -eq 1 ]
    [[ "$output" == *"port_range not configured"* ]]
}

# ── Option validation ─────────────────────────────────────────────────────────

@test "cmd_port_next: unknown option → exit 1 + 'Unknown option'" {
    run cmd_port_next -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "cmd_port_next: -n without argument → exit 1" {
    run cmd_port_next -n
    [ "$status" -eq 1 ]
}

@test "cmd_port_next: -n 0 → exit 1 + 'Invalid'" {
    run cmd_port_next -n 0
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid"* ]]
}

@test "cmd_port_next: -n abc → exit 1 + 'Invalid'" {
    run cmd_port_next -n abc
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid"* ]]
}

# ── Nominal ───────────────────────────────────────────────────────────────────

@test "cmd_port_next: returns 5 ports by default" {
    run cmd_port_next
    [ "$status" -eq 0 ]
    count=$(printf '%s\n' "$output" | grep -cE '^\s+[0-9]{4,5}$' || true)
    [ "$count" = "5" ]
}

@test "cmd_port_next: default output starts with 8000 (first free in range)" {
    run cmd_port_next
    [ "$status" -eq 0 ]
    [[ "$output" == *"8000"* ]]
}

@test "cmd_port_next: skips used ports (8080, 8081)" {
    run cmd_port_next -n 10
    [ "$status" -eq 0 ]
    [[ "$output" != *"8080"* ]]
    [[ "$output" != *"8081"* ]]
}

@test "cmd_port_next: -n 3 returns exactly 3 ports" {
    run cmd_port_next -n 3
    [ "$status" -eq 0 ]
    count=$(printf '%s\n' "$output" | grep -cE '^\s+[0-9]{4,5}$' || true)
    [ "$count" = "3" ]
}

@test "cmd_port_next: -n 1 returns exactly 1 port" {
    run cmd_port_next -n 1
    [ "$status" -eq 0 ]
    count=$(printf '%s\n' "$output" | grep -cE '^\s+[0-9]{4,5}$' || true)
    [ "$count" = "1" ]
}

# ── Exhausted range ───────────────────────────────────────────────────────────

@test "cmd_port_next: fewer ports available than requested → warning, exit 0" {
    # Range [8080, 8082] — 8080 and 8081 used, only 8082 free
    jq '.port_range = {"min": 8080, "max": 8082}' "$CONFIG_FILE" \
        > "$BATS_TEST_TMPDIR/t.json" && mv "$BATS_TEST_TMPDIR/t.json" "$CONFIG_FILE"
    run cmd_port_next -n 5
    [ "$status" -eq 0 ]
    [[ "$output" == *"⚠"* ]]
    [[ "$output" == *"8082"* ]]
}

@test "cmd_port_next: no ports available → warning only, exit 0" {
    # Range [8080, 8081] — both ports are used
    jq '.port_range = {"min": 8080, "max": 8081}' "$CONFIG_FILE" \
        > "$BATS_TEST_TMPDIR/t.json" && mv "$BATS_TEST_TMPDIR/t.json" "$CONFIG_FILE"
    run cmd_port_next
    [ "$status" -eq 0 ]
    [[ "$output" == *"⚠"* ]]
}
