#!/usr/bin/env bats
# Unit tests for scripts/commands/pod/list.sh

load '../../../test_helper/common'

setup() {
    load_common
    source "$SCRIPTS_DIR/commands/pod/list.sh"
}

# ── Invalid options ───────────────────────────────────────────────────────────

@test "cmd_pod_list: -p without argument → exit 1 + error message" {
    run cmd_pod_list -p
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires an argument"* ]]
}

@test "cmd_pod_list: -e without argument → exit 1 + error message" {
    run cmd_pod_list -e
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires an argument"* ]]
}

@test "cmd_pod_list: unknown option → exit 1 + error message" {
    run cmd_pod_list -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

# ── check_pods_file ────────────────────────────────────────────────────────────

@test "check_pods_file: file absent → exit 1 + ✗ message" {
    rm -f "$PODS_FILE"
    run check_pods_file
    [ "$status" -eq 1 ]
    [[ "$output" == *"✗"* ]]
}

@test "check_pods_file: file present → return 0" {
    check_pods_file
}

# ── validate_env_filter ────────────────────────────────────────────────────────

@test "validate_env_filter: ENV_FILTER empty → return 0" {
    ENV_FILTER=""
    validate_env_filter
}

@test "validate_env_filter: valid env → return 0" {
    ENV_FILTER="dev"
    validate_env_filter
}

@test "validate_env_filter: invalid env → exit 1 + 'invalid environment'" {
    ENV_FILTER="nosuchenv"
    run validate_env_filter
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid environment"* ]]
}

@test "validate_env_filter: error message lists valid envs" {
    ENV_FILTER="nosuchenv"
    run validate_env_filter
    [[ "$output" == *"dev"* ]]
    [[ "$output" == *"prod"* ]]
}

@test "cmd_pod_list: -e invalide → exit 1 + 'invalid environment'" {
    run cmd_pod_list -e zzz
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid environment"* ]]
}

# ── Section headers ───────────────────────────────────────────────────────────

@test "cmd_pod_list: without filter → header 'Pods [ALL]'" {
    run cmd_pod_list
    [ "$status" -eq 0 ]
    [[ "$output" == *"Pods [ALL]"* ]]
}

@test "cmd_pod_list: -e dev → header 'Pods [DEV]'" {
    run cmd_pod_list -e dev
    [ "$status" -eq 0 ]
    [[ "$output" == *"Pods [DEV]"* ]]
}

@test "cmd_pod_list: -p api → header 'Search: \"api\" [ALL]'" {
    run cmd_pod_list -p api
    [ "$status" -eq 0 ]
    [[ "$output" == *'Search: "api" [ALL]'* ]]
}

@test "cmd_pod_list: -p api -e dev → header 'Search: \"api\" [DEV]'" {
    run cmd_pod_list -p api -e dev
    [ "$status" -eq 0 ]
    [[ "$output" == *'Search: "api" [DEV]'* ]]
}

# ── Full listing ──────────────────────────────────────────────────────────────

@test "cmd_pod_list: without filter → exit 0" {
    run cmd_pod_list
    [ "$status" -eq 0 ]
}

@test "cmd_pod_list: without filter → displays 3 envs (DEV, TEST, PROD)" {
    run cmd_pod_list
    [[ "$output" == *"DEV"* ]]
    [[ "$output" == *"TEST"* ]]
    [[ "$output" == *"PROD"* ]]
}

@test "cmd_pod_list: without filter → displays short names (not FQDNs)" {
    run cmd_pod_list
    [[ "$output" == *"dev1"* ]]
    [[ "$output" == *"dev2"* ]]
    [[ "$output" == *"test1"* ]]
    [[ "$output" == *"prod1"* ]]
    [[ "$output" == *"prod2"* ]]
    [[ "$output" != *".fleet.test"* ]]
}

@test "cmd_pod_list: without filter → summary '7 pod(s) across 3 environment(s)'" {
    run cmd_pod_list
    [[ "$output" == *"7 pod(s) across 3 environment(s)"* ]]
}

# ── Filter -e ────────────────────────────────────────────────────────────────

@test "cmd_pod_list: -e dev → contains DEV, not TEST or PROD" {
    run cmd_pod_list -e dev
    [[ "$output" == *"DEV"* ]]
    [[ "$output" != *"TEST"* ]]
    [[ "$output" != *"PROD"* ]]
}

@test "cmd_pod_list: -e dev → summary '3 pod(s) across 1 environment(s)'" {
    run cmd_pod_list -e dev
    [[ "$output" == *"3 pod(s) across 1 environment(s)"* ]]
}

# ── Filter -p ────────────────────────────────────────────────────────────────

@test "cmd_pod_list: -p api → contains 'api', not 'worker'" {
    run cmd_pod_list -p api
    [[ "$output" == *"api"* ]]
    [[ "$output" != *"worker"* ]]
}

@test "cmd_pod_list: -p api → summary '4 pod(s) across 3 environment(s)'" {
    run cmd_pod_list -p api
    [[ "$output" == *"4 pod(s) across 3 environment(s)"* ]]
}

@test "cmd_pod_list: -p worker → summary '3 pod(s) across 3 environment(s)'" {
    run cmd_pod_list -p worker
    [[ "$output" == *"3 pod(s) across 3 environment(s)"* ]]
}

@test "cmd_pod_list: -p api -e dev → contains DEV, not PROD" {
    run cmd_pod_list -p api -e dev
    [[ "$output" == *"DEV"* ]]
    [[ "$output" != *"PROD"* ]]
}

@test "cmd_pod_list: -p api -e dev → summary '2 pod(s) across 1 environment(s)'" {
    run cmd_pod_list -p api -e dev
    [[ "$output" == *"2 pod(s) across 1 environment(s)"* ]]
}

# ── No results ───────────────────────────────────────────────────────────────

@test "cmd_pod_list: -p nonexistent → exit 0 + warn 'No results'" {
    run cmd_pod_list -p nonexistent
    [ "$status" -eq 0 ]
    [[ "$output" == *'No results for "nonexistent"'* ]]
}

# ── Direct coverage (without run, for kcov) ──────────────────────────────────

@test "cmd_pod_list: direct call without filter → displays envs (coverage)" {
    cmd_pod_list > "$BATS_TEST_TMPDIR/out.txt"
    grep -q "DEV" "$BATS_TEST_TMPDIR/out.txt"
    grep -q "TEST" "$BATS_TEST_TMPDIR/out.txt"
    grep -q "PROD" "$BATS_TEST_TMPDIR/out.txt"
}

@test "cmd_pod_list: direct call with -p api → displays api (coverage)" {
    cmd_pod_list -p api > "$BATS_TEST_TMPDIR/out.txt"
    grep -q "api" "$BATS_TEST_TMPDIR/out.txt"
}
