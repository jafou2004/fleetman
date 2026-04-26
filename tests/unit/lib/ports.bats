#!/usr/bin/env bats
# Unit tests for scripts/lib/ports.sh

load '../../test_helper/common'

setup() {
    load_common
    source "$SCRIPTS_DIR/lib/ports.sh"
}

# ── check_services_file ───────────────────────────────────────────────────────

@test "check_services_file: exits 1 with error when services.json absent" {
    rm -f "$HOME/.data/services.json"
    run check_services_file
    [ "$status" -eq 1 ]
    [[ "$output" == *"services.json not found"* ]]
    [[ "$output" == *"sync --full"* ]]
}

@test "check_services_file: succeeds when services.json present" {
    run check_services_file
    [ "$status" -eq 0 ]
}

# ── _port_read_range ──────────────────────────────────────────────────────────

@test "_port_read_range: exits 1 when port_range absent in config.json" {
    run _port_read_range
    [ "$status" -eq 1 ]
    [[ "$output" == *"port_range not configured"* ]]
    [[ "$output" == *"config portrange"* ]]
}

@test "_port_read_range: exits 1 when only min is set" {
    jq '. + {"port_range": {"min": 8000}}' "$CONFIG_FILE" \
        > "$BATS_TEST_TMPDIR/t.json" && mv "$BATS_TEST_TMPDIR/t.json" "$CONFIG_FILE"
    run _port_read_range
    [ "$status" -eq 1 ]
    [[ "$output" == *"port_range not configured"* ]]
}

@test "_port_read_range: exits 1 when only max is set" {
    jq '. + {"port_range": {"max": 9000}}' "$CONFIG_FILE" \
        > "$BATS_TEST_TMPDIR/t.json" && mv "$BATS_TEST_TMPDIR/t.json" "$CONFIG_FILE"
    run _port_read_range
    [ "$status" -eq 1 ]
    [[ "$output" == *"port_range not configured"* ]]
}

@test "_port_read_range: sets PORT_MIN and PORT_MAX globals" {
    jq '. + {"port_range": {"min": 8000, "max": 9000}}' "$CONFIG_FILE" \
        > "$BATS_TEST_TMPDIR/t.json" && mv "$BATS_TEST_TMPDIR/t.json" "$CONFIG_FILE"
    _port_read_range
    [ "$PORT_MIN" = "8000" ]
    [ "$PORT_MAX" = "9000" ]
}

# ── _port_collect_used ────────────────────────────────────────────────────────

@test "_port_collect_used: returns a JSON array" {
    result=$(_port_collect_used)
    type=$(printf '%s' "$result" | jq -r 'type')
    [ "$type" = "array" ]
}

@test "_port_collect_used: returns 9 entries for the fixture" {
    count=$(_port_collect_used | jq 'length')
    [ "$count" = "9" ]
}

@test "_port_collect_used: each entry has port, pod, service, env, server" {
    keys=$(_port_collect_used | jq -r '.[0] | keys | sort | join(",")')
    [ "$keys" = "env,pod,port,server,service" ]
}

@test "_port_collect_used: port 8080 appears 4 times (dev1, dev2, test1, prod1)" {
    count=$(_port_collect_used | jq '[.[] | select(.port == 8080)] | length')
    [ "$count" = "4" ]
}

@test "_port_collect_used: port 9000 appears 2 times (dev1, test1)" {
    count=$(_port_collect_used | jq '[.[] | select(.port == 9000)] | length')
    [ "$count" = "2" ]
}

@test "_port_collect_used: entry has correct server FQDN format (contains dot)" {
    srv=$(_port_collect_used | jq -r '[.[] | select(.port == 9000)] | .[0].server')
    [[ "$srv" == *"."* ]]
}

@test "_port_collect_used: PublishedPort=0 entries excluded" {
    echo '{"dev":{"dev1.fleet.test":{"api":[{"Service":"web","Publishers":[{"PublishedPort":0,"TargetPort":80,"Protocol":"tcp"}]}]}}}' \
        > "$HOME/.data/services.json"
    count=$(_port_collect_used | jq 'length')
    [ "$count" = "0" ]
}

@test "_port_collect_used: empty publishers array → empty result" {
    echo '{"dev":{"dev1.fleet.test":{"api":[{"Service":"web","Publishers":[]}]}}}' \
        > "$HOME/.data/services.json"
    result=$(_port_collect_used)
    [ "$(printf '%s' "$result" | jq 'length')" = "0" ]
}
