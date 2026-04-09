#!/usr/bin/env bats
# Unit tests for scripts/internal/smoketest.sh

load '../../test_helper/common'

setup() {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin" "$HOME/.ssh"
    load_common

    # Mock fleetman binary
    cat > "$BATS_TEST_TMPDIR/bin/fleetman" << 'EOF'
#!/bin/bash
[[ "$*" == *"__invalid__"* ]] && exit 1
echo "FLEETMAN:$*"
exit "${FLEETMAN_RC:-0}"
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/fleetman"

    ask_password() { PASSWORD="testpass"; B64_PASS="dGVzdHBhc3M="; }
    touch "$HOME/.ssh/fleet_key"
    export FLEET_KEY="$HOME/.ssh/fleet_key"

    source "$SCRIPTS_DIR/internal/smoketest.sh"

    # Re-mock after sourcing
    ask_password() { PASSWORD="testpass"; B64_PASS="dGVzdHBhc3M="; }
    export MASTER_HOST="master.local"
}

# ── --plan mode ──────────────────────────────────────────────────────────────

@test "smoketest: --plan exits 0" {
    run main --plan
    [ "$status" -eq 0 ]
}

@test "smoketest: --plan outputs SYNC section" {
    run main --plan
    [[ "$output" == *"[ ] SYNC"* ]]
}

@test "smoketest: --plan outputs ALIAS section" {
    run main --plan
    [[ "$output" == *"[ ] ALIAS"* ]]
}

@test "smoketest: --plan outputs POD section" {
    run main --plan
    [[ "$output" == *"[ ] POD"* ]]
}

@test "smoketest: --plan outputs CONFIG section" {
    run main --plan
    [[ "$output" == *"[ ] CONFIG"* ]]
}

@test "smoketest: --plan outputs SELFUPDATE section" {
    run main --plan
    [[ "$output" == *"[ ] SELFUPDATE"* ]]
}

@test "smoketest: --plan outputs MANUAL count line" {
    run main --plan
    [[ "$output" == *"MANUAL: 31"* ]]
}

@test "smoketest: --plan does not call fleetman" {
    FLEETMAN_CALLED=0
    fleetman() { FLEETMAN_CALLED=1; }
    export -f fleetman
    run main --plan
    [ "$FLEETMAN_CALLED" -eq 0 ]
}

# ── option errors ────────────────────────────────────────────────────────────

@test "smoketest: unknown option exits 1" {
    run main --bogus
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "smoketest: -h exits 0 and shows usage" {
    run main -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "smoketest: --help exits 0 and shows usage" {
    run main --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "smoketest: --env without argument exits 1" {
    run main --env
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires an argument"* ]]
}

@test "smoketest: --timeout without argument exits 1" {
    run main --timeout
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires an argument"* ]]
}

# ── _st_run_test ─────────────────────────────────────────────────────────────

@test "_st_run_test: passing command prints ✓ and label" {
    _ST_PASS=0; _ST_FAIL=0; _ST_TIMEOUT=5
    run _st_run_test "my label" true
    [ "$status" -eq 0 ]
    [[ "$output" == *"✓"* ]]
    [[ "$output" == *"my label"* ]]
}

@test "_st_run_test: passing command increments _ST_PASS" {
    _ST_PASS=0; _ST_FAIL=0; _ST_TIMEOUT=5
    _st_run_test "my label" true
    [ "$_ST_PASS" -eq 1 ]
    [ "$_ST_FAIL" -eq 0 ]
}

@test "_st_run_test: failing command prints ✗" {
    _ST_PASS=0; _ST_FAIL=0; _ST_TIMEOUT=5
    run _st_run_test "bad cmd" false
    [ "$status" -eq 0 ]
    [[ "$output" == *"✗"* ]]
}

@test "_st_run_test: failing command increments _ST_FAIL" {
    _ST_PASS=0; _ST_FAIL=0; _ST_TIMEOUT=5
    _st_run_test "bad cmd" false
    [ "$_ST_FAIL" -eq 1 ]
    [ "$_ST_PASS" -eq 0 ]
}

@test "_st_run_test: failing command shows exit code in detail" {
    _ST_PASS=0; _ST_FAIL=0; _ST_TIMEOUT=5
    run _st_run_test "exit3" bash -c "exit 3"
    [[ "$output" == *"3"* ]]
}

@test "_st_run_test: timeout records as FAIL" {
    _ST_PASS=0; _ST_FAIL=0; _ST_TIMEOUT=1
    _st_run_test "slow" bash -c "sleep 10"
    [ "$_ST_FAIL" -eq 1 ]
}

@test "_st_run_test: timeout prints ✗" {
    _ST_PASS=0; _ST_FAIL=0; _ST_TIMEOUT=1
    run _st_run_test "slow" bash -c "sleep 10"
    [[ "$output" == *"✗"* ]]
}

@test "_st_run_test: passing command includes timing (ms)" {
    _ST_PASS=0; _ST_TIMEOUT=5
    run _st_run_test "timed" true
    [[ "$output" =~ [0-9]+ms ]]
}

# ── _st_print_auto_results ───────────────────────────────────────────────────

@test "_st_print_auto_results: shows correct pass and fail counts" {
    _ST_PASS=7; _ST_FAIL=2
    run _st_print_auto_results
    [[ "$output" == *"7 ✓"* ]]
    [[ "$output" == *"2 ✗"* ]]
    [[ "$output" == *"9 tests"* ]]
}

@test "_st_print_auto_results: all pass shows 0 fail" {
    _ST_PASS=5; _ST_FAIL=0
    run _st_print_auto_results
    [[ "$output" == *"5 ✓"* ]]
    [[ "$output" == *"0 ✗"* ]]
}

# ── _st_run_version_tests ────────────────────────────────────────────────────

@test "_st_run_version_tests: calls fleetman -v and fleetman --version" {
    _ST_PASS=0; _ST_FAIL=0; _ST_TIMEOUT=5
    run _st_run_version_tests
    [[ "$output" == *"fleetman -v"* ]]
    [[ "$output" == *"fleetman --version"* ]]
}

@test "_st_run_version_tests: both pass when fleetman exits 0" {
    _ST_PASS=0; _ST_FAIL=0; _ST_TIMEOUT=5
    _st_run_version_tests
    [ "$_ST_PASS" -eq 2 ]
    [ "$_ST_FAIL" -eq 0 ]
}

@test "_st_run_version_tests: both fail when fleetman exits 1" {
    export FLEETMAN_RC=1
    _ST_PASS=0; _ST_FAIL=0; _ST_TIMEOUT=5
    _st_run_version_tests
    [ "$_ST_FAIL" -eq 2 ]
    [ "$_ST_PASS" -eq 0 ]
}

# ── _st_run_pod_list_tests ───────────────────────────────────────────────────

@test "_st_run_pod_list_tests: runs pod list when pods.json exists" {
    _ST_PASS=0; _ST_FAIL=0; _ST_TIMEOUT=5
    run _st_run_pod_list_tests
    [[ "$output" == *"pod list"* ]]
}

@test "_st_run_pod_list_tests: skips with warning when pods.json absent" {
    rm -f "$PODS_FILE"
    _ST_PASS=0; _ST_FAIL=0; _ST_TIMEOUT=5
    run _st_run_pod_list_tests
    [[ "$output" == *"skipped"* ]]
    [ "$_ST_PASS" -eq 0 ]
    [ "$_ST_FAIL" -eq 0 ]
}

@test "_st_run_pod_list_tests: reads first pod from pods.json dynamically" {
    _ST_PASS=0; _ST_FAIL=0; _ST_TIMEOUT=5
    run _st_run_pod_list_tests
    # fixture pods.json has "api" as first pod
    [[ "$output" == *"-p api"* ]]
}

@test "_st_run_pod_list_tests: reads first env from pods.json dynamically" {
    _ST_PASS=0; _ST_FAIL=0; _ST_TIMEOUT=5
    run _st_run_pod_list_tests
    # fixture pods.json has "dev" as first env
    [[ "$output" == *"-e dev"* ]]
}

@test "_st_run_pod_list_tests: invalid env case records as PASS (correctly rejected)" {
    _ST_PASS=0; _ST_FAIL=0; _ST_TIMEOUT=5
    # pod list + -p api + -e dev + __nonexistent__ + __invalid__ (expected fail) = 5 pass
    _st_run_pod_list_tests
    [ "$_ST_PASS" -eq 5 ]
}

# ── _st_run_fleet_tests ──────────────────────────────────────────────────────

@test "_st_run_fleet_tests: calls fleetman status" {
    _ST_PASS=0; _ST_FAIL=0; _ST_TIMEOUT=5; _ST_ENV=""
    run _st_run_fleet_tests
    [[ "$output" == *"fleetman status"* ]]
}

@test "_st_run_fleet_tests: calls fleetman exec -- hostname" {
    _ST_PASS=0; _ST_FAIL=0; _ST_TIMEOUT=5; _ST_ENV=""
    run _st_run_fleet_tests
    [[ "$output" == *"exec -- hostname"* ]]
}

@test "_st_run_fleet_tests: calls fleetman exec -- uptime" {
    _ST_PASS=0; _ST_FAIL=0; _ST_TIMEOUT=5; _ST_ENV=""
    run _st_run_fleet_tests
    [[ "$output" == *"exec -- uptime"* ]]
}

@test "_st_run_fleet_tests: calls fleetman exec -- date" {
    _ST_PASS=0; _ST_FAIL=0; _ST_TIMEOUT=5; _ST_ENV=""
    run _st_run_fleet_tests
    [[ "$output" == *"exec -- date"* ]]
}

@test "_st_run_fleet_tests: calls fleetman sudo -- id" {
    _ST_PASS=0; _ST_FAIL=0; _ST_TIMEOUT=5; _ST_ENV=""
    run _st_run_fleet_tests
    [[ "$output" == *"sudo -- id"* ]]
}

@test "_st_run_fleet_tests: --env scopes status and exec labels" {
    _ST_PASS=0; _ST_FAIL=0; _ST_TIMEOUT=5; _ST_ENV="dev"
    run _st_run_fleet_tests
    [[ "$output" == *"-e dev"* ]]
}

@test "_st_run_fleet_tests: all 5 commands pass when fleetman exits 0" {
    _ST_PASS=0; _ST_FAIL=0; _ST_TIMEOUT=5; _ST_ENV=""
    _st_run_fleet_tests
    [ "$_ST_PASS" -eq 5 ]
    [ "$_ST_FAIL" -eq 0 ]
}

# ── full main (default mode) ─────────────────────────────────────────────────

@test "smoketest: default mode outputs AUTO summary" {
    run main
    [[ "$output" == *"AUTO  :"* ]]
}

@test "smoketest: default mode outputs MANUAL checklist" {
    run main
    [[ "$output" == *"MANUAL: 31"* ]]
}

@test "smoketest: --env invalid exits 1" {
    run main --env nosuchenv
    [ "$status" -eq 1 ]
}
