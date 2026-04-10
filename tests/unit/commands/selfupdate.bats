#!/usr/bin/env bats
# Unit tests for scripts/commands/selfupdate.sh

load '../../test_helper/common'

# ── helpers ────────────────────────────────────────────────────────────────────

# Creates a mock git binary whose output depends on the subcommand.
# Environment variables control what each sub-command returns:
#   GIT_TAG_POINTS_AT   output of "git tag --points-at HEAD"
#   GIT_TAG_LIST        output of "git tag -l 'v*'"
#   GIT_REV_LIST_COUNT  number returned by "git rev-list HEAD..@{u} --count"
#   GIT_TAG_LIST_PLAIN  output of "git tag -l" (used for grep -qxF in pin check)
#   GIT_REV_PARSE_HEAD  output of "git rev-parse HEAD"
#   GIT_REV_PARSE_UPSTREAM  output of "git rev-parse origin/<branch>"
#   GIT_FETCH_FAIL      if "1", "git fetch origin <branch>" returns 1
_write_git_mock() {
    cat > "$BATS_TEST_TMPDIR/bin/git" << 'GITEOF'
#!/bin/bash
# Minimal git mock — responds to the subcommands used by selfupdate.sh
args=("$@")
# Strip "-C <dir>" prefix if present
if [[ "${args[0]}" == "-C" ]]; then
    args=("${args[@]:2}")
fi
subcmd="${args[0]}"
case "$subcmd" in
    tag)
        if [[ "${args[1]}" == "--points-at" ]]; then
            echo "${GIT_TAG_POINTS_AT:-}"
        elif [[ "${args[1]}" == "-l" && "${args[2]}" == "v[0-9]*"* ]]; then
            echo "${GIT_TAG_LIST:-}"
        else
            # plain "git tag -l" used by grep -qxF in _update_pin
            echo "${GIT_TAG_LIST_PLAIN:-}"
        fi
        ;;
    rev-list)
        echo "${GIT_REV_LIST_COUNT:-0}"
        ;;
    rev-parse)
        if [[ "${args[1]}" == "HEAD" ]]; then
            echo "${GIT_REV_PARSE_HEAD:-abc123}"
        else
            # origin/<branch>
            if [[ "${GIT_FETCH_FAIL:-0}" == "1" ]]; then
                exit 1
            fi
            echo "${GIT_REV_PARSE_UPSTREAM:-def456}"
        fi
        ;;
    symbolic-ref)
        if [[ "${GIT_DETACHED_HEAD:-0}" == "1" ]]; then
            exit 1
        fi
        echo "refs/heads/main"
        ;;
    fetch)
        if [[ "${GIT_FETCH_FAIL:-0}" == "1" && "${args[1]}" == "origin" ]]; then
            exit 1
        fi
        exit 0
        ;;
    checkout)
        if [[ "${GIT_CHECKOUT_FAIL:-0}" == "1" ]]; then
            exit 1
        fi
        exit 0
        ;;
    pull)
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
GITEOF
    chmod +x "$BATS_TEST_TMPDIR/bin/git"
}

setup() {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    load_common
    _write_git_mock
    source "$SCRIPTS_DIR/commands/selfupdate.sh"
}

# ── _update_pin ────────────────────────────────────────────────────────────────

@test "_update_pin: already at pinned version → return 1 + ok message" {
    export GIT_TAG_POINTS_AT="v1.2.3"
    run _update_pin "/fake/pdir" "v1.2.3"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Already at pinned version v1.2.3"* ]]
}

@test "_update_pin: pinned tag not found → return 1 + error message" {
    export GIT_TAG_POINTS_AT=""
    export GIT_TAG_LIST_PLAIN="v1.0.0"
    run _update_pin "/fake/pdir" "v2.0.0"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found in repository tags"* ]]
}

@test "_update_pin: tag found and different → return 0 + ok message" {
    export GIT_TAG_POINTS_AT="v1.0.0"
    export GIT_TAG_LIST_PLAIN="v1.0.0
v1.2.3"
    run _update_pin "/fake/pdir" "v1.2.3"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Moving to pinned version v1.2.3"* ]]
}

# ── _update_tags ───────────────────────────────────────────────────────────────

@test "_update_tags: already at latest tag → return 1 + ok message" {
    export GIT_TAG_LIST="v1.0.0"
    export GIT_TAG_POINTS_AT="v1.0.0"
    run _update_tags "/fake/pdir"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Already up to date at v1.0.0"* ]]
}

@test "_update_tags: new tag available → return 0 + ok message" {
    export GIT_TAG_LIST="v1.1.0"
    export GIT_TAG_POINTS_AT="v1.0.0"
    run _update_tags "/fake/pdir"
    [ "$status" -eq 0 ]
    [[ "$output" == *"New version available: v1.1.0"* ]]
}

@test "_update_tags: no tag, no new commits → return 1" {
    export GIT_TAG_LIST=""
    export GIT_REV_LIST_COUNT="0"
    run _update_tags "/fake/pdir"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Already up to date"* ]]
}

@test "_update_tags: no tag, new commits → return 0" {
    export GIT_TAG_LIST=""
    export GIT_REV_LIST_COUNT="3"
    run _update_tags "/fake/pdir"
    [ "$status" -eq 0 ]
}

# ── _update_commits ────────────────────────────────────────────────────────────

@test "_update_commits: 0 new commit → return 1 + ok message" {
    export GIT_REV_LIST_COUNT="0"
    export GIT_DETACHED_HEAD="0"
    run _update_commits "/fake/pdir" "main"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Already up to date"* ]]
}

@test "_update_commits: N new commits → return 0 + ok message" {
    export GIT_REV_LIST_COUNT="5"
    export GIT_DETACHED_HEAD="0"
    run _update_commits "/fake/pdir" "main"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Pulling 5 new commit(s)"* ]]
}

@test "_update_commits: detached HEAD → checkout branch before pull" {
    export GIT_DETACHED_HEAD="1"
    export GIT_REV_LIST_COUNT="2"
    run _update_commits "/fake/pdir" "main"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Detached HEAD"*"main"* ]]
}

@test "_update_commits: detached HEAD + checkout fails → return 1 + error message" {
    export GIT_DETACHED_HEAD="1"
    export GIT_CHECKOUT_FAIL="1"
    run _update_commits "/fake/pdir" "main"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Could not check out branch main"* ]]
}

# ── _update_branch ─────────────────────────────────────────────────────────────

@test "_update_branch: HEAD == origin/branch → return 1 + message ok" {
    export GIT_REV_PARSE_HEAD="abc123"
    export GIT_REV_PARSE_UPSTREAM="abc123"
    export GIT_FETCH_FAIL="0"
    run _update_branch "/fake/pdir" "main"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Already up to date on branch main"* ]]
}

@test "_update_branch: HEAD != origin/branch → return 0 + message ok" {
    export GIT_REV_PARSE_HEAD="abc123"
    export GIT_REV_PARSE_UPSTREAM="def456"
    export GIT_FETCH_FAIL="0"
    export GIT_REV_LIST_COUNT="2"
    run _update_branch "/fake/pdir" "main"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Pulling"*"branch main"* ]]
}

@test "_update_branch: branch not found → return 1 + error message" {
    export GIT_FETCH_FAIL="1"
    run _update_branch "/fake/pdir" "nonexistent"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found on remote"* ]]
}

# ── _selfupdate_local ──────────────────────────────────────────────────────────

@test "_selfupdate_local: pin already at pinned version → return 0, bash not called" {
    export GIT_TAG_POINTS_AT="v1.0.0"
    bash() { echo "$*" >> "$BATS_TEST_TMPDIR/bash_calls.log"; }
    export -f bash
    export SCRIPTS_DIR="$BATS_TEST_TMPDIR/scripts"
    local fake_pdir="$BATS_TEST_TMPDIR/fake-pdir"
    mkdir -p "$fake_pdir/scripts/internal"
    echo "1.0.0" > "$fake_pdir/scripts/internal/VERSION"

    run _selfupdate_local "$fake_pdir" "tags" "v1.0.0" "main"
    [ "$status" -eq 0 ]
    [ ! -f "$BATS_TEST_TMPDIR/bash_calls.log" ]
}

@test "_selfupdate_local: pin update performed → migrations and sync called" {
    export GIT_TAG_POINTS_AT="v1.0.0"
    export GIT_TAG_LIST_PLAIN="v1.0.0
v1.2.3"
    bash() { echo "$*" >> "$BATS_TEST_TMPDIR/bash_calls.log"; }
    export -f bash
    export SCRIPTS_DIR="$BATS_TEST_TMPDIR/scripts"
    local fake_pdir="$BATS_TEST_TMPDIR/fake-pdir"
    mkdir -p "$fake_pdir/scripts/internal"
    echo "1.0.0" > "$fake_pdir/scripts/internal/VERSION"

    run _selfupdate_local "$fake_pdir" "tags" "v1.2.3" "main"
    [ "$status" -eq 0 ]
    grep -q "run_migrations.sh" "$BATS_TEST_TMPDIR/bash_calls.log"
    grep -q "fleetman.*sync.*--quick" "$BATS_TEST_TMPDIR/bash_calls.log"
}

@test "_selfupdate_local: tags already up to date → return 0, bash not called" {
    export GIT_TAG_LIST="v1.0.0"
    export GIT_TAG_POINTS_AT="v1.0.0"
    bash() { echo "$*" >> "$BATS_TEST_TMPDIR/bash_calls.log"; }
    export -f bash
    export SCRIPTS_DIR="$BATS_TEST_TMPDIR/scripts"
    local fake_pdir="$BATS_TEST_TMPDIR/fake-pdir"
    mkdir -p "$fake_pdir/scripts/internal"
    echo "1.0.0" > "$fake_pdir/scripts/internal/VERSION"

    run _selfupdate_local "$fake_pdir" "tags" "" "main"
    [ "$status" -eq 0 ]
    [ ! -f "$BATS_TEST_TMPDIR/bash_calls.log" ]
}

@test "_selfupdate_local: tags new version available → migrations and sync called" {
    export GIT_TAG_LIST="v1.1.0"
    export GIT_TAG_POINTS_AT="v1.0.0"
    bash() { echo "$*" >> "$BATS_TEST_TMPDIR/bash_calls.log"; }
    export -f bash
    export SCRIPTS_DIR="$BATS_TEST_TMPDIR/scripts"
    local fake_pdir="$BATS_TEST_TMPDIR/fake-pdir"
    mkdir -p "$fake_pdir/scripts/internal"
    echo "1.0.0" > "$fake_pdir/scripts/internal/VERSION"

    run _selfupdate_local "$fake_pdir" "tags" "" "main"
    [ "$status" -eq 0 ]
    grep -q "run_migrations.sh" "$BATS_TEST_TMPDIR/bash_calls.log"
    grep -q "fleetman.*sync.*--quick" "$BATS_TEST_TMPDIR/bash_calls.log"
}

@test "_selfupdate_local: commits already up to date → return 0, bash not called" {
    export GIT_REV_LIST_COUNT="0"
    export GIT_DETACHED_HEAD="0"
    bash() { echo "$*" >> "$BATS_TEST_TMPDIR/bash_calls.log"; }
    export -f bash
    export SCRIPTS_DIR="$BATS_TEST_TMPDIR/scripts"
    local fake_pdir="$BATS_TEST_TMPDIR/fake-pdir"
    mkdir -p "$fake_pdir/scripts/internal"
    echo "1.0.0" > "$fake_pdir/scripts/internal/VERSION"

    run _selfupdate_local "$fake_pdir" "commits" "" "main"
    [ "$status" -eq 0 ]
    [ ! -f "$BATS_TEST_TMPDIR/bash_calls.log" ]
}

@test "_selfupdate_local: commits new commits → migrations and sync called" {
    export GIT_REV_LIST_COUNT="3"
    export GIT_DETACHED_HEAD="0"
    bash() { echo "$*" >> "$BATS_TEST_TMPDIR/bash_calls.log"; }
    export -f bash
    export SCRIPTS_DIR="$BATS_TEST_TMPDIR/scripts"
    local fake_pdir="$BATS_TEST_TMPDIR/fake-pdir"
    mkdir -p "$fake_pdir/scripts/internal"
    echo "1.0.0" > "$fake_pdir/scripts/internal/VERSION"

    run _selfupdate_local "$fake_pdir" "commits" "" "main"
    [ "$status" -eq 0 ]
    grep -q "run_migrations.sh" "$BATS_TEST_TMPDIR/bash_calls.log"
    grep -q "fleetman.*sync.*--quick" "$BATS_TEST_TMPDIR/bash_calls.log"
}

@test "_selfupdate_local: branch already up to date → return 0, bash not called" {
    export GIT_REV_PARSE_HEAD="abc123"
    export GIT_REV_PARSE_UPSTREAM="abc123"
    export GIT_FETCH_FAIL="0"
    bash() { echo "$*" >> "$BATS_TEST_TMPDIR/bash_calls.log"; }
    export -f bash
    export SCRIPTS_DIR="$BATS_TEST_TMPDIR/scripts"
    local fake_pdir="$BATS_TEST_TMPDIR/fake-pdir"
    mkdir -p "$fake_pdir/scripts/internal"
    echo "1.0.0" > "$fake_pdir/scripts/internal/VERSION"

    run _selfupdate_local "$fake_pdir" "branch" "" "main"
    [ "$status" -eq 0 ]
    [ ! -f "$BATS_TEST_TMPDIR/bash_calls.log" ]
}

@test "_selfupdate_local: branch new commits → migrations and sync called" {
    export GIT_REV_PARSE_HEAD="abc123"
    export GIT_REV_PARSE_UPSTREAM="def456"
    export GIT_FETCH_FAIL="0"
    export GIT_REV_LIST_COUNT="2"
    bash() { echo "$*" >> "$BATS_TEST_TMPDIR/bash_calls.log"; }
    export -f bash
    export SCRIPTS_DIR="$BATS_TEST_TMPDIR/scripts"
    local fake_pdir="$BATS_TEST_TMPDIR/fake-pdir"
    mkdir -p "$fake_pdir/scripts/internal"
    echo "1.0.0" > "$fake_pdir/scripts/internal/VERSION"

    run _selfupdate_local "$fake_pdir" "branch" "" "main"
    [ "$status" -eq 0 ]
    grep -q "run_migrations.sh" "$BATS_TEST_TMPDIR/bash_calls.log"
    grep -q "fleetman.*sync.*--quick" "$BATS_TEST_TMPDIR/bash_calls.log"
}

# ── _parse_remote_result ───────────────────────────────────────────────────────

@test "_parse_remote_result: UP_TO_DATE → ok message, ssh_cmd not called" {
    ssh_cmd() { echo "$*" >> "$BATS_TEST_TMPDIR/ssh_calls.log"; }
    export -f ssh_cmd
    local remote_out
    remote_out="$(printf 'OLD_VER:1.0.0\nNEW_VER:1.0.0\nUP_TO_DATE:v1.0.0')"

    run _parse_remote_result "$remote_out" "remote.server.test"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Already up to date"* ]]
    [ ! -f "$BATS_TEST_TMPDIR/ssh_calls.log" ]
}

@test "_parse_remote_result: UPDATED → ok message, ssh_cmd called for migrations and sync" {
    ssh_cmd() { echo "$*" >> "$BATS_TEST_TMPDIR/ssh_calls.log"; }
    export -f ssh_cmd
    local remote_out
    remote_out="$(printf 'OLD_VER:1.0.0\nNEW_VER:1.1.0\nUPDATED:2 commit(s)')"

    run _parse_remote_result "$remote_out" "remote.server.test"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Updated"* ]]
    grep -q "run_migrations.sh" "$BATS_TEST_TMPDIR/ssh_calls.log"
    grep -q "fleetman.*sync.*--quick" "$BATS_TEST_TMPDIR/ssh_calls.log"
}

@test "_parse_remote_result: FAILED → err message, return 1" {
    ssh_cmd() { echo "$*" >> "$BATS_TEST_TMPDIR/ssh_calls.log"; }
    export -f ssh_cmd
    local remote_out
    remote_out="$(printf 'OLD_VER:1.0.0\nNEW_VER:1.0.0\nFAILED:tag not found')"

    run _parse_remote_result "$remote_out" "remote.server.test"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Update failed"* ]]
    [ ! -f "$BATS_TEST_TMPDIR/ssh_calls.log" ]
}

@test "_parse_remote_result: unknown status → err message, return 1" {
    ssh_cmd() { echo "$*" >> "$BATS_TEST_TMPDIR/ssh_calls.log"; }
    export -f ssh_cmd
    local remote_out
    remote_out="$(printf 'OLD_VER:1.0.0\nNEW_VER:1.0.0\nGARBAGE')"

    run _parse_remote_result "$remote_out" "remote.server.test"
    [ "$status" -eq 1 ]
    [[ "$output" == *"failed or produced no status"* ]]
    [ ! -f "$BATS_TEST_TMPDIR/ssh_calls.log" ]
}

# ── cmd_selfupdate: track validation ─────────────────────────────────────────

@test "cmd_selfupdate: unknown option -x → exit 1 + error message" {
    check_sshpass()     { :; }
    check_config_file() { :; }
    ask_password()      { :; }
    run cmd_selfupdate -x
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "cmd_selfupdate: invalid track → exit 1 + error message" {
    local cfg="$BATS_TEST_TMPDIR/bad_config.json"
    jq '.selfupdate.track = "invalid"' "$CONFIG_FILE" > "$cfg"
    export CONFIG_FILE="$cfg"
    check_sshpass()     { :; }
    check_config_file() { :; }
    ask_password()      { :; }
    run cmd_selfupdate
    [ "$status" -eq 1 ]
    [[ "$output" == *"must be"* ]]
}

# ── cmd_selfupdate: Case 2 (git clone distant) ────────────────────────────────

@test "cmd_selfupdate: Case 2, git_server absent, scan finds nothing → warn + exit 1" {
    export FLEETMAN_DIR="$BATS_TEST_TMPDIR/no-clone"
    rm -f "$GIT_SERVER_FILE"
    check_sshpass()     { :; }
    check_config_file() { :; }
    ask_password()      { PASSWORD="dummy"; B64_PASS="ZHVtbXk="; }
    ssh_cmd() { return 1; }
    export -f ssh_cmd
    run cmd_selfupdate
    unset -f ssh_cmd
    [ "$status" -eq 1 ]
    [[ "$output" == *"not cached"* ]]
    [[ "$output" == *"No server"* ]]
}

@test "cmd_selfupdate: Case 2, git_server absent, scan finds server → proceed (no exit 1)" {
    export FLEETMAN_DIR="$BATS_TEST_TMPDIR/no-clone"
    rm -f "$GIT_SERVER_FILE"
    check_sshpass()     { :; }
    check_config_file() { :; }
    ask_password()      { PASSWORD="dummy"; B64_PASS="ZHVtbXk="; }
    local _call=0
    ssh_cmd() {
        _call=$((_call + 1))
        [[ "$_call" -eq 1 ]] && { echo "dev1.fleet.test"; return 0; }
        return 1
    }
    export -f ssh_cmd
    _parse_remote_result() { :; }
    export -f _parse_remote_result
    run cmd_selfupdate
    unset -f ssh_cmd _parse_remote_result
    # Must NOT exit 1 due to missing git_server — may exit 0 or 1 from update logic
    [[ "$output" != *"No server"* ]]
    [[ "$output" == *"not cached"* ]]
}

@test "cmd_selfupdate: Case 2, stale cache, scan finds nothing → warn unreachable + exit 1" {
    export FLEETMAN_DIR="$BATS_TEST_TMPDIR/no-clone"
    echo "remote.server.test" > "$GIT_SERVER_FILE"
    check_sshpass()     { :; }
    check_config_file() { :; }
    ask_password()      { PASSWORD="dummy"; B64_PASS="ZHVtbXk="; }
    ssh_cmd() { return 1; }
    export -f ssh_cmd
    run cmd_selfupdate
    unset -f ssh_cmd
    [ "$status" -eq 1 ]
    [[ "$output" == *"unreachable"* ]]
    [[ "$output" == *"No server"* ]]
}

@test "cmd_selfupdate: Case 2, stale cache, scan finds server → proceed (no exit 1)" {
    export FLEETMAN_DIR="$BATS_TEST_TMPDIR/no-clone"
    echo "old.server.test" > "$GIT_SERVER_FILE"
    check_sshpass()     { :; }
    check_config_file() { :; }
    ask_password()      { PASSWORD="dummy"; B64_PASS="ZHVtbXk="; }
    local _call=0
    ssh_cmd() {
        _call=$((_call + 1))
        # Call 1: cached server check (old.server.test) → fail
        [[ "$_call" -eq 1 ]] && return 1
        # Call 2: scan — first candidate → succeed
        [[ "$_call" -eq 2 ]] && return 0
        return 1
    }
    export -f ssh_cmd
    _parse_remote_result() { :; }
    export -f _parse_remote_result
    run cmd_selfupdate
    unset -f ssh_cmd _parse_remote_result
    [[ "$output" != *"No server"* ]]
    [[ "$output" == *"unreachable"* ]]
}

# ── _find_git_server ──────────────────────────────────────────────────────────

@test "_find_git_server: first server has git clone → return 0, FQDN printed, cache written" {
    ssh_cmd() {
        # Only dev1.fleet.test has a git clone
        [[ "$1" == "dev1.fleet.test" ]] && return 0
        return 1
    }
    export -f ssh_cmd
    rm -f "$GIT_SERVER_FILE"

    run _find_git_server
    [ "$status" -eq 0 ]
    [[ "$output" == *"dev1.fleet.test"* ]]
    [ "$(cat "$GIT_SERVER_FILE")" = "dev1.fleet.test" ]
}

@test "_find_git_server: second server has git clone → return 0, correct FQDN" {
    ssh_cmd() {
        [[ "$1" == "dev2.fleet.test" ]] && return 0
        return 1
    }
    export -f ssh_cmd
    rm -f "$GIT_SERVER_FILE"

    run _find_git_server
    [ "$status" -eq 0 ]
    [[ "$output" == *"dev2.fleet.test"* ]]
}

@test "_find_git_server: no server has git clone → return 1, no output, cache not written" {
    ssh_cmd() { return 1; }
    export -f ssh_cmd
    rm -f "$GIT_SERVER_FILE"

    run _find_git_server
    [ "$status" -eq 1 ]
    [ -z "$output" ]
    [ ! -f "$GIT_SERVER_FILE" ]
}

@test "_find_git_server: stops at first match (does not continue scanning)" {
    local call_log="$BATS_TEST_TMPDIR/ssh_scan.log"
    ssh_cmd() {
        echo "$1" >> "$call_log"
        [[ "$1" == "dev1.fleet.test" ]] && return 0
        return 1
    }
    export -f ssh_cmd
    rm -f "$GIT_SERVER_FILE"

    run _find_git_server
    [ "$status" -eq 0 ]
    # Only dev1.fleet.test should have been probed (it matched immediately)
    [ "$(wc -l < "$call_log")" -eq 1 ]
    grep -q "dev1.fleet.test" "$call_log"
}

@test "_find_git_server: overwrites stale cache with newly found server" {
    echo "old.server.test" > "$GIT_SERVER_FILE"
    ssh_cmd() {
        [[ "$1" == "prod1.fleet.test" ]] && return 0
        return 1
    }
    export -f ssh_cmd

    run _find_git_server
    [ "$status" -eq 0 ]
    [ "$(cat "$GIT_SERVER_FILE")" = "prod1.fleet.test" ]
}
