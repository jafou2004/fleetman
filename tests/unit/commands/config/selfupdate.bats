#!/usr/bin/env bats
# Tests unitaires pour scripts/commands/config/selfupdate.sh

load '../../../test_helper/common'

# Writes the git mock to $BATS_TEST_TMPDIR/bin/git
# Control variables:
#   GIT_LS_REMOTE_BRANCHES  branch names separated by \n (e.g. "main\ndevelop")
#   GIT_LS_REMOTE_TAGS      tag names separated by \n (e.g. "v1.0.0\nv1.1.0")
#   GIT_LS_REMOTE_FAIL      if "1", git ls-remote returns exit 1
_write_git_mock() {
    cat > "$BATS_TEST_TMPDIR/bin/git" << 'GITEOF'
#!/bin/bash
if [[ "${GIT_LS_REMOTE_FAIL:-0}" == "1" ]]; then exit 1; fi
case "${1:-}" in
    ls-remote)
        if [[ "${2:-}" == "--heads" ]]; then
            while IFS= read -r branch; do
                [[ -z "$branch" ]] && continue
                printf 'abc123\trefs/heads/%s\n' "$branch"
            done <<< "${GIT_LS_REMOTE_BRANCHES:-}"
        else
            while IFS= read -r tag; do
                [[ -z "$tag" ]] && continue
                printf 'abc123\trefs/tags/%s\n' "$tag"
                printf 'def456\trefs/tags/%s^{}\n' "$tag"
            done <<< "${GIT_LS_REMOTE_TAGS:-}"
        fi ;;
    remote)
        echo "https://github.com/example/fleetman.git" ;;
    *) exit 0 ;;
esac
GITEOF
    chmod +x "$BATS_TEST_TMPDIR/bin/git"
}

setup() {
    load_common
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    _write_git_mock
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    # Default values so menus use select_menu (not fallback prompt)
    export GIT_LS_REMOTE_BRANCHES=$'main\ndevelop'
    export GIT_LS_REMOTE_TAGS=$'v1.1.0\nv1.0.0'
    source "$SCRIPTS_DIR/commands/config/selfupdate.sh"
    prompt_sync_confirm() { :; }
    select_menu() { SELECTED_IDX=0; }
}

# ── _su_fetch_branches ─────────────────────────────────────────────────────────

@test "_su_fetch_branches: returns names without refs/heads/ prefix" {
    export GIT_LS_REMOTE_BRANCHES=$'main\ndevelop'
    run _su_fetch_branches "https://example.com/repo.git"
    [ "$status" -eq 0 ]
    [[ "$output" == *"main"* ]]
    [[ "$output" == *"develop"* ]]
    [[ "$output" != *"refs/heads/"* ]]
}

@test "_su_fetch_branches: git ls-remote fails → exit 1" {
    export GIT_LS_REMOTE_FAIL=1
    run _su_fetch_branches "https://example.com/repo.git"
    [ "$status" -eq 1 ]
}

# ── _su_fetch_tags ─────────────────────────────────────────────────────────────

@test "_su_fetch_tags: returns semver tags without refs/tags/ prefix" {
    export GIT_LS_REMOTE_TAGS=$'v1.2.0\nv1.1.0\nv1.0.0'
    run _su_fetch_tags "https://example.com/repo.git"
    [ "$status" -eq 0 ]
    [[ "$output" == *"v1.2.0"* ]]
    [[ "$output" != *"refs/tags/"* ]]
}

@test "_su_fetch_tags: filters ^{} annotations" {
    export GIT_LS_REMOTE_TAGS=$'v1.0.0'
    run _su_fetch_tags "https://example.com/repo.git"
    [ "$status" -eq 0 ]
    [[ "$output" != *"^{}"* ]]
}

@test "_su_fetch_tags: filters non-semver tags" {
    export GIT_LS_REMOTE_TAGS=$'v1.0.0\nlatest\nnightly'
    run _su_fetch_tags "https://example.com/repo.git"
    [ "$status" -eq 0 ]
    [[ "$output" == *"v1.0.0"* ]]
    [[ "$output" != *"latest"* ]]
    [[ "$output" != *"nightly"* ]]
}

@test "_su_fetch_tags: sorts in descending order (most recent first)" {
    export GIT_LS_REMOTE_TAGS=$'v1.0.0\nv1.2.0\nv1.1.0'
    run _su_fetch_tags "https://example.com/repo.git"
    [ "$status" -eq 0 ]
    first=$(echo "$output" | head -1)
    [ "$first" = "v1.2.0" ]
}

@test "_su_fetch_tags: limits to 20 results maximum" {
    local tags=""
    for i in $(seq 1 25); do tags+="v1.0.${i}\n"; done
    export GIT_LS_REMOTE_TAGS
    GIT_LS_REMOTE_TAGS=$(printf '%b' "$tags")
    run _su_fetch_tags "https://example.com/repo.git"
    [ "$status" -eq 0 ]
    count=$(echo "$output" | grep -c 'v1\.0\.' || true)
    [ "$count" -le 20 ]
}

@test "_su_fetch_tags: git ls-remote fails → exit 1" {
    export GIT_LS_REMOTE_FAIL=1
    run _su_fetch_tags "https://example.com/repo.git"
    [ "$status" -eq 1 ]
}

# ── Invalid options ───────────────────────────────────────────────────────────

@test "cmd_config_selfupdate: unknown option → exit 1 + 'Unknown option'" {
    run cmd_config_selfupdate -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

# ── check_config_file ──────────────────────────────────────────────────────────

@test "cmd_config_selfupdate: config.json absent → exit 1 + ⚠" {
    rm -f "$CONFIG_FILE"
    run cmd_config_selfupdate
    [ "$status" -eq 1 ]
    [[ "$output" == *"⚠"* ]]
}

# ── Summary displayed ─────────────────────────────────────────────────────────

@test "cmd_config_selfupdate: displays current values (track, branch, pin, repo)" {
    run cmd_config_selfupdate
    [ "$status" -eq 0 ]
    [[ "$output" == *"track"* ]]
    [[ "$output" == *"branch"* ]]
}

# ── Track selection ───────────────────────────────────────────────────────────

@test "cmd_config_selfupdate: track unchanged (tags, idx=0), pin idx=0 → 'Unchanged'" {
    # setup() exposes GIT_LS_REMOTE_TAGS → tags available → select_menu for pin
    # select_menu mock always returns SELECTED_IDX=0
    # track=tags(0), pin=(no pin=idx 0) → unchanged (fixture: pin="")
    run cmd_config_selfupdate
    [ "$status" -eq 0 ]
    [[ "$output" == *"Unchanged"* ]]
}

@test "cmd_config_selfupdate: track tags→commits (idx=1) → config.json updated" {
    # setup() exposes GIT_LS_REMOTE_TAGS → select_menu for pin (no prompt)
    _call_count=0
    select_menu() {
        _call_count=$(( _call_count + 1 ))
        if [ "$_call_count" -eq 1 ]; then
            SELECTED_IDX=1   # commits
        else
            SELECTED_IDX=0   # (aucun pin)
        fi
    }
    run cmd_config_selfupdate
    [ "$status" -eq 0 ]
    [ "$(jq -r '.selfupdate.track' "$CONFIG_FILE")" = "commits" ]
}

@test "cmd_config_selfupdate: track=branch, branches available → branch selected from list" {
    export GIT_LS_REMOTE_BRANCHES=$'main\ndevelop'
    _call_count=0
    select_menu() {
        _call_count=$(( _call_count + 1 ))
        if [ "$_call_count" -eq 1 ]; then
            SELECTED_IDX=2   # branch (index dans _track_values)
        elif [ "$_call_count" -eq 2 ]; then
            SELECTED_IDX=0   # main (first in the list)
        else
            SELECTED_IDX=0   # (no pin)
        fi
    }
    run cmd_config_selfupdate
    [ "$status" -eq 0 ]
    [ "$(jq -r '.selfupdate.track' "$CONFIG_FILE")" = "branch" ]
    [ "$(jq -r '.selfupdate.branch' "$CONFIG_FILE")" = "main" ]
}

@test "cmd_config_selfupdate: track=branch, branch idx=1 → selfupdate.branch updated" {
    export GIT_LS_REMOTE_BRANCHES=$'main\ndevelop'
    _call_count=0
    select_menu() {
        _call_count=$(( _call_count + 1 ))
        if [ "$_call_count" -eq 1 ]; then
            SELECTED_IDX=2   # branch
        elif [ "$_call_count" -eq 2 ]; then
            SELECTED_IDX=1   # develop
        else
            SELECTED_IDX=0   # (no pin)
        fi
    }
    run cmd_config_selfupdate
    [ "$status" -eq 0 ]
    [ "$(jq -r '.selfupdate.branch' "$CONFIG_FILE")" = "develop" ]
}

@test "cmd_config_selfupdate: track=branch, git ls-remote fails → warn + fallback prompt" {
    export GIT_LS_REMOTE_FAIL=1
    _call_count=0
    select_menu() {
        _call_count=$(( _call_count + 1 ))
        if [ "$_call_count" -eq 1 ]; then SELECTED_IDX=2; else SELECTED_IDX=0; fi
    }
    # prompt_response will return "mybranch" via stdin
    prompt_response() { echo "mybranch"; }
    run cmd_config_selfupdate
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cannot reach"* ]]
    [ "$(jq -r '.selfupdate.branch' "$CONFIG_FILE")" = "mybranch" ]
}

@test "cmd_config_selfupdate: repo_url absent → warn 'repo_url missing' + fallback prompt" {
    jq 'del(.repo_url)' "$CONFIG_FILE" > "$BATS_TEST_TMPDIR/t.json" \
        && mv "$BATS_TEST_TMPDIR/t.json" "$CONFIG_FILE"
    _call_count=0
    select_menu() {
        _call_count=$(( _call_count + 1 ))
        if [ "$_call_count" -eq 1 ]; then SELECTED_IDX=2; else SELECTED_IDX=0; fi
    }
    prompt_response() { echo "main"; }
    run cmd_config_selfupdate
    [ "$status" -eq 0 ]
    [[ "$output" == *"repo_url missing"* ]]
}

# ── Pin selection ─────────────────────────────────────────────────────────────

@test "cmd_config_selfupdate: idx=0 (no pin) → selfupdate.pin = ''" {
    export GIT_LS_REMOTE_TAGS=$'v1.1.0\nv1.0.0'
    _call_count=0
    select_menu() {
        _call_count=$(( _call_count + 1 ))
        SELECTED_IDX=0   # tags (track) then (no pin)
    }
    run cmd_config_selfupdate
    [ "$status" -eq 0 ]
    [ "$(jq -r '.selfupdate.pin' "$CONFIG_FILE")" = "" ]
}

@test "cmd_config_selfupdate: idx=1 → selfupdate.pin = first tag (most recent)" {
    export GIT_LS_REMOTE_TAGS=$'v1.0.0\nv1.1.0'
    _call_count=0
    select_menu() {
        _call_count=$(( _call_count + 1 ))
        if [ "$_call_count" -eq 1 ]; then
            SELECTED_IDX=0   # tags (track unchanged)
        else
            SELECTED_IDX=1   # first tag = v1.1.0 (sorted desc)
        fi
    }
    run cmd_config_selfupdate
    [ "$status" -eq 0 ]
    [ "$(jq -r '.selfupdate.pin' "$CONFIG_FILE")" = "v1.1.0" ]
}

@test "cmd_config_selfupdate: git ls-remote tags fails → fallback prompt pin" {
    export GIT_LS_REMOTE_FAIL=1
    prompt_response() { echo "v1.0.0"; }
    run cmd_config_selfupdate
    [ "$status" -eq 0 ]
    [ "$(jq -r '.selfupdate.pin' "$CONFIG_FILE")" = "v1.0.0" ]
}

@test "cmd_config_selfupdate: empty pin via prompt, track unchanged → 'Unchanged'" {
    export GIT_LS_REMOTE_FAIL=1
    # GIT_LS_REMOTE_FAIL=1 → both fetches fail → prompt_response for pin
    # track select_menu returns idx=0 (tags, unchanged), prompt_response returns ""
    # new_track=tags, new_branch=main, new_pin="" → all unchanged
    prompt_response() { echo ""; }
    run cmd_config_selfupdate
    [ "$status" -eq 0 ]
    [[ "$output" == *"Unchanged"* ]]
}

# ── Writing config.json ───────────────────────────────────────────────────────

@test "cmd_config_selfupdate: change → prompt_sync_confirm called" {
    local call_file="$BATS_TEST_TMPDIR/sync_calls"
    prompt_sync_confirm() { echo "SYNC" >> "$call_file"; }
    _call_count=0
    select_menu() {
        _call_count=$(( _call_count + 1 ))
        if [ "$_call_count" -eq 1 ]; then SELECTED_IDX=1; else SELECTED_IDX=0; fi
    }
    run cmd_config_selfupdate
    [ "$status" -eq 0 ]
    [ -f "$call_file" ]
}

@test "cmd_config_selfupdate: unchanged → prompt_sync_confirm not called" {
    local call_file="$BATS_TEST_TMPDIR/sync_calls"
    prompt_sync_confirm() { echo "SYNC" >> "$call_file"; }
    run cmd_config_selfupdate
    [ "$status" -eq 0 ]
    [ ! -f "$call_file" ]
}

@test "cmd_config_selfupdate: jq write fails → exit 1 + ✗" {
    # Make parent directory of config.json non-writable to block mv
    local _cfg_dir
    _cfg_dir=$(dirname "$CONFIG_FILE")
    chmod 555 "$_cfg_dir"
    _call_count=0
    select_menu() {
        _call_count=$(( _call_count + 1 ))
        if [ "$_call_count" -eq 1 ]; then SELECTED_IDX=1; else SELECTED_IDX=0; fi
    }
    run cmd_config_selfupdate
    chmod 755 "$_cfg_dir"
    [ "$status" -eq 1 ]
    [[ "$output" == *"✗"* ]]
}

@test "cmd_config_selfupdate: change → displays 'selfupdate: track=...'" {
    _call_count=0
    select_menu() {
        _call_count=$(( _call_count + 1 ))
        if [ "$_call_count" -eq 1 ]; then SELECTED_IDX=1; else SELECTED_IDX=0; fi
    }
    run cmd_config_selfupdate
    [ "$status" -eq 0 ]
    [[ "$output" == *"selfupdate:"* ]]
    [[ "$output" == *"track=commits"* ]]
}
