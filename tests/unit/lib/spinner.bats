#!/usr/bin/env bats
# Unit tests for scripts/lib/spinner.sh

load '../../test_helper/common'

setup() {
    load_common
    _SPIN_PID=""
}

teardown() {
    # Kill the spinner if still active after a test
    if [ -n "${_SPIN_PID:-}" ]; then
        kill "$_SPIN_PID" 2>/dev/null
        wait "$_SPIN_PID" 2>/dev/null || true
        _SPIN_PID=""
    fi
}

# ── _spin_start ────────────────────────────────────────────────────────────────

@test "_spin_start: starts a background process and sets _SPIN_PID" {
    _spin_start "myserver"
    sleep 0.2
    [ -n "$_SPIN_PID" ]
    # Verify that the PID is an active process
    kill -0 "$_SPIN_PID" 2>/dev/null
    [ "$?" -eq 0 ]
}

# ── _spin_stop ─────────────────────────────────────────────────────────────────

@test "_spin_stop ok: output contains ✓ and detail" {
    _spin_start "myserver"
    sleep 0.1
    run _spin_stop "myserver" "ok" "deployed"
    [ "$status" -eq 0 ]
    [[ "$output" == *"✓"* ]]
    [[ "$output" == *"deployed"* ]]
    _SPIN_PID=""  # Already killed by _spin_stop
}

@test "_spin_stop warn: output contains ⚠ and detail" {
    _spin_start "myserver"
    sleep 0.1
    run _spin_stop "myserver" "warn" "already up to date"
    [ "$status" -eq 0 ]
    [[ "$output" == *"⚠"* ]]
    [[ "$output" == *"already up to date"* ]]
    _SPIN_PID=""
}

@test "_spin_stop err: output contains ✗ and detail" {
    _spin_start "myserver"
    sleep 0.1
    run _spin_stop "myserver" "err" "connection refused"
    [ "$status" -eq 0 ]
    [[ "$output" == *"✗"* ]]
    [[ "$output" == *"connection refused"* ]]
    _SPIN_PID=""
}

@test "_spin_stop: includes the server name in output" {
    _spin_start "srv42"
    sleep 0.1
    run _spin_stop "srv42" "ok" "done"
    [[ "$output" == *"srv42"* ]]
    _SPIN_PID=""
}
