#!/usr/bin/env bats
# Tests unitaires pour scripts/commands/config/autosync.sh

load '../../../test_helper/common'

setup() {
    load_common
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"

    # Mock crontab: -l lists $CRON_FILE, - writes stdin to $CRON_FILE (atomic)
    cat > "$BATS_TEST_TMPDIR/bin/crontab" << EOF
#!/bin/bash
_CRON_FILE="$BATS_TEST_TMPDIR/crontab.txt"
if [[ "\$1" == "-l" ]]; then
    cat "\$_CRON_FILE" 2>/dev/null || true
else
    _tmp=\$(mktemp)
    cat > "\$_tmp"
    mv "\$_tmp" "\$_CRON_FILE"
fi
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/crontab"

    # Fleet key → bypasse check_sshpass
    touch "$HOME/.ssh/fleet_key"

    source "$SCRIPTS_DIR/commands/config/autosync.sh"

    # Mock ssh_cmd and ask_password after sourcing (idempotency guards prevent re-sourcing of libs)
    # ask_password must be mocked: FLEET_PASS_FILE absent → interactive prompt that would block the test
    ssh_cmd() { return 0; }
    ask_password() { PASSWORD="dummy"; B64_PASS="ZHVtbXk="; }

    # Simulate local git clone
    export FLEETMAN_DIR="$BATS_TEST_TMPDIR/fleetman"
    mkdir -p "$FLEETMAN_DIR/.git"
}

# ── config.json absent ────────────────────────────────────────────────────────

@test "cmd_config_autosync: config.json absent → exit 1 + ⚠" {
    rm -f "$CONFIG_FILE"
    run cmd_config_autosync <<< 'n'
    [ "$status" -eq 1 ]
    [[ "$output" == *"⚠"* ]]
}

# ── option inconnue ───────────────────────────────────────────────────────────

@test "cmd_config_autosync: unknown option → exit 1 + 'Unknown option'" {
    run cmd_config_autosync -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

# ── Local clone detection + status display ────────────────────────────────────

@test "cmd_config_autosync: local clone, cron absent → displays 'inactive'" {
    # No crontab.txt → cron absent
    run cmd_config_autosync <<< 'n'
    [ "$status" -eq 0 ]
    [[ "$output" == *"inactive"* ]]
}

@test "cmd_config_autosync: local clone, cron present 0 1 → displays 'active' + '01:00'" {
    echo "0 1 * * * mv ~/.data/autosync.log ~/.data/autosync.log.1 2>/dev/null; bash ~/scripts/bin/fleetman sync > ~/.data/autosync.log 2>&1" \
        > "$BATS_TEST_TMPDIR/crontab.txt"
    run cmd_config_autosync <<< 'n'
    [ "$status" -eq 0 ]
    [[ "$output" == *"active"* ]]
    [[ "$output" == *"01:00"* ]]
}

@test "cmd_config_autosync: local clone, cron present 30 8 → displays '08:30'" {
    echo "30 8 * * * mv ~/.data/autosync.log ~/.data/autosync.log.1 2>/dev/null; bash ~/scripts/bin/fleetman sync > ~/.data/autosync.log 2>&1" \
        > "$BATS_TEST_TMPDIR/crontab.txt"
    run cmd_config_autosync <<< 'n'
    [ "$status" -eq 0 ]
    [[ "$output" == *"08:30"* ]]
}

# ── No clone found ────────────────────────────────────────────────────────────

@test "cmd_config_autosync: remote clone, git_server absent → exit 1 + 'not cached'" {
    export FLEETMAN_DIR="$BATS_TEST_TMPDIR/no-clone"
    rm -f "$GIT_SERVER_FILE"
    run cmd_config_autosync
    [ "$status" -eq 1 ]
    [[ "$output" == *"not cached"* ]]
}

@test "cmd_config_autosync: remote clone, git_server present but unreachable → exit 1 + 'unreachable'" {
    export FLEETMAN_DIR="$BATS_TEST_TMPDIR/no-clone"
    echo "remote.server.test" > "$GIT_SERVER_FILE"
    ssh_cmd() { return 1; }
    run cmd_config_autosync
    [ "$status" -eq 1 ]
    [[ "$output" == *"unreachable"* ]]
}

# ── Local activation ──────────────────────────────────────────────────────────

@test "cmd_config_autosync: local activation with 02:15 → correct cron line" {
    # Cron absent, we answer Y then 02:15
    run cmd_config_autosync < <(printf 'Y\n02:15\n')
    [ "$status" -eq 0 ]
    [[ "$output" == *"02:15"* ]]
    # _hh="02" (zero-padded from user input "02:15"), _mm="15"
    grep -q "15 02 \* \* \*.*fleetman sync" "$BATS_TEST_TMPDIR/crontab.txt"
}

# ── Local deactivation ────────────────────────────────────────────────────────

@test "cmd_config_autosync: local deactivation → line removed" {
    echo "0 1 * * * mv ~/.data/autosync.log ~/.data/autosync.log.1 2>/dev/null; bash ~/scripts/bin/fleetman sync > ~/.data/autosync.log 2>&1" \
        > "$BATS_TEST_TMPDIR/crontab.txt"
    run cmd_config_autosync <<< 'y'
    [ "$status" -eq 0 ]
    [[ "$output" == *"disabled"* ]]
    run grep "fleetman sync" "$BATS_TEST_TMPDIR/crontab.txt"
    [ "$status" -ne 0 ]
}

# ── Idempotence ───────────────────────────────────────────────────────────────

@test "cmd_config_autosync: same time → 'Unchanged', crontab not touched" {
    echo "0 1 * * * mv ~/.data/autosync.log ~/.data/autosync.log.1 2>/dev/null; bash ~/scripts/bin/fleetman sync > ~/.data/autosync.log 2>&1" \
        > "$BATS_TEST_TMPDIR/crontab.txt"
    local before_mtime
    before_mtime=$(stat -c %Y "$BATS_TEST_TMPDIR/crontab.txt" 2>/dev/null || stat -f %m "$BATS_TEST_TMPDIR/crontab.txt")
    # Cron active, we answer N (no deactivation) then 01:00 (same time)
    run cmd_config_autosync < <(printf 'N\n01:00\n')
    [ "$status" -eq 0 ]
    [[ "$output" == *"Unchanged"* ]]
    local after_mtime
    after_mtime=$(stat -c %Y "$BATS_TEST_TMPDIR/crontab.txt" 2>/dev/null || stat -f %m "$BATS_TEST_TMPDIR/crontab.txt")
    [ "$before_mtime" = "$after_mtime" ]
}

# ── Invalid then valid time ───────────────────────────────────────────────────

@test "cmd_config_autosync: invalid then valid time → success" {
    # Cron absent, we answer Y, then 25:00 (invalid), then 03:00 (valid)
    run cmd_config_autosync < <(printf 'Y\n25:00\n03:00\n')
    [ "$status" -eq 0 ]
    [[ "$output" == *"Invalid"* ]]
    [[ "$output" == *"03:00"* ]]
    # _hh="03" (zero-padded from user input "03:00"), _mm="00"
    grep -q "00 03 \* \* \*.*fleetman sync" "$BATS_TEST_TMPDIR/crontab.txt"
}

# ── Remote clone ──────────────────────────────────────────────────────────────

@test "cmd_config_autosync: remote clone, cron absent → SSH called to verify, read and write" {
    # No local clone
    export FLEETMAN_DIR="$BATS_TEST_TMPDIR/no-clone"
    echo "remote.server.test" > "$GIT_SERVER_FILE"   # required: no SSH scan to find the server

    # Compteur d'appels SSH via fichier tmpdir
    local _ssh_calls_file="$BATS_TEST_TMPDIR/ssh_calls"

    ssh_cmd() {
        local _count
        _count=$(wc -l < "$_ssh_calls_file" 2>/dev/null || echo 0)
        echo "X" >> "$_ssh_calls_file"
        case "$_count" in
            0) return 0 ;;              # call 1: git clone verification → ok
            1) echo "CRON_INACTIVE" ;; # call 2: Phase A read
            2) echo "CRON_UPDATED" ;;  # call 3: Phase B write
        esac
    }

    # ask_password ne doit pas bloquer
    ask_password() { PASSWORD="dummy"; B64_PASS="ZHVtbXk="; }

    run cmd_config_autosync < <(printf 'Y\n02:00\n')
    [ "$status" -eq 0 ]
    [[ "$output" == *"02:00"* ]]
    # Verify that 3 SSH calls were made (git verification + Phase A + Phase B)
    local _call_count
    _call_count=$(wc -l < "$_ssh_calls_file" 2>/dev/null || echo 0)
    [ "$_call_count" -eq 3 ]
}
