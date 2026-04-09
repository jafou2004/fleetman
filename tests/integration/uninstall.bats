#!/usr/bin/env bats
# Integration tests for scripts/internal/uninstall.sh
# Invokes the script directly via bash.

load '../test_helper/common'

setup() {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin" "$HOME/.ssh"
    setup_fixtures

    # Mock openssl: silent password decryption
    cat > "$BATS_TEST_TMPDIR/bin/openssl" << 'EOF'
#!/bin/bash
printf 'testpassword'
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/openssl"

    # Mock crontab : -l → cat store, - → store stdin
    # Note: mktemp+mv avoids the race condition where crontab - truncates the file
    # before crontab -l finishes reading it (bash pipeline commands run concurrently).
    cat > "$BATS_TEST_TMPDIR/bin/crontab" << EOF
#!/bin/bash
CRONTAB_FILE="$BATS_TEST_TMPDIR/crontab_store"
if [[ "\$1" == "-l" ]]; then
    [ -f "\$CRONTAB_FILE" ] && cat "\$CRONTAB_FILE" || true
elif [[ "\$1" == "-" ]]; then
    _tmp="\$(mktemp)"
    cat > "\$_tmp"
    mv "\$_tmp" "\$CRONTAB_FILE"
fi
exit 0
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/crontab"

    # Mock ssh: simulates marker returns based on $UNINSTALL_SSH_MODE
    cat > "$BATS_TEST_TMPDIR/bin/ssh" << 'EOF'
#!/bin/bash
# Filter SSH options (-i key, -o ...) to isolate host + command
args=()
skip_next=0
for arg in "$@"; do
    if [ "$skip_next" -eq 1 ]; then skip_next=0; continue; fi
    case "$arg" in
        -i|-o|-p) skip_next=1 ;;
        -*)       ;;
        *)        args+=("$arg") ;;
    esac
done
# Appel scan : [ -d "pdir/.git" ]
if [[ "$*" == *"[ -d"* ]]; then
    case "${CLONE_SCAN_MODE:-none}" in
        found) exit 0 ;;
        *)     exit 1 ;;
    esac
fi
# Appel rm -rf
if [[ "$*" == *"rm -rf"* ]]; then
    echo "RM_CALL:${args[0]}:$*" >> "${BATS_TEST_TMPDIR}/ssh_calls"
    exit 0
fi
# Appel uninstall : comportement existant
case "${UNINSTALL_SSH_MODE:-ok}" in
    ok)         printf 'BASHRC_DONE\nCRON_DONE\nFILES_DONE\nDATA_DONE\nSCRIPTS_DONE\n' ;;
    fail)       exit 1 ;;
    incomplete) printf 'BASHRC_DONE\nCRON_DONE\n' ;;
esac
exit "${SSH_EXIT_CODE:-0}"
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/ssh"

    # Fleet key + passfile → ask_password silent, check_sshpass no-op
    touch "$HOME/.ssh/fleet_key" "$HOME/.fleet_pass.enc"
    export FLEET_KEY="$HOME/.ssh/fleet_key"
    export FLEET_PASS_FILE="$HOME/.fleet_pass.enc"
}

# ── Help ──────────────────────────────────────────────────────────────────────

@test "uninstall.sh -h: exit 0 + displays Usage" {
    run bash "$SCRIPTS_DIR/internal/uninstall.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"uninstall"* ]]
}

@test "uninstall.sh -h: lists removed items" {
    run bash "$SCRIPTS_DIR/internal/uninstall.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"fleet_key"* ]]
    [[ "$output" == *"config.json"* ]]
    [[ "$output" == *".data/"* ]]
}

# ── Option validation ─────────────────────────────────────────────────────────

@test "uninstall.sh: unknown option → exit 1 + error message" {
    run bash "$SCRIPTS_DIR/internal/uninstall.sh" -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

# ── Triple confirmation ───────────────────────────────────────────────────────

@test "uninstall.sh: wrong hostname → exit 1 before acting" {
    # Providing an incorrect hostname: must abort without SSH
    run bash "$SCRIPTS_DIR/internal/uninstall.sh" <<< $'WRONGNAME\nyes\nUNINSTALL\n'
    [ "$status" -eq 1 ]
    [[ "$output" == *"Confirmation failed"* ]]
}

@test "uninstall.sh: 'no' at 2nd confirmation → exit 1" {
    local short
    short=$(hostname -f 2>/dev/null | cut -d. -f1)
    run bash "$SCRIPTS_DIR/internal/uninstall.sh" < <(printf '%s\nno\nUNINSTALL\n' "$short")
    [ "$status" -eq 1 ]
    [[ "$output" == *"Confirmation failed"* ]]
}

# ── Full run (SSH ok) ─────────────────────────────────────────────────────────

@test "uninstall.sh: confirmation ok + SSH ok → exit 0 + summary ✓" {
    local short
    short=$(hostname -f 2>/dev/null | cut -d. -f1)
    export UNINSTALL_SSH_MODE=ok
    run bash "$SCRIPTS_DIR/internal/uninstall.sh" < <(printf '%s\nyes\nUNINSTALL\nn\n' "$short")
    [ "$status" -eq 0 ]
    [[ "$output" == *"✓"* ]]
}

@test "uninstall.sh: confirmation ok + SSH ok → displays 'Uninstalling' header" {
    local short
    short=$(hostname -f 2>/dev/null | cut -d. -f1)
    export UNINSTALL_SSH_MODE=ok
    run bash "$SCRIPTS_DIR/internal/uninstall.sh" < <(printf '%s\nyes\nUNINSTALL\nn\n' "$short")
    [[ "$output" == *"Uninstalling"* ]]
}

# ── Failing SSH run ───────────────────────────────────────────────────────────

@test "uninstall.sh: SSH fails → summary displays ✗" {
    local short
    short=$(hostname -f 2>/dev/null | cut -d. -f1)
    export UNINSTALL_SSH_MODE=fail
    export SSH_EXIT_CODE=1
    run bash "$SCRIPTS_DIR/internal/uninstall.sh" < <(printf '%s\nyes\nUNINSTALL\nn\n' "$short")
    [[ "$output" == *"✗"* ]]
}

@test "uninstall.sh: incomplete SSH (SCRIPTS_DONE absent) → ✗ in summary" {
    local short
    short=$(hostname -f 2>/dev/null | cut -d. -f1)
    export UNINSTALL_SSH_MODE=incomplete
    run bash "$SCRIPTS_DIR/internal/uninstall.sh" < <(printf '%s\nyes\nUNINSTALL\nn\n' "$short")
    [[ "$output" == *"✗"* ]]
}

# ── Git clone ─────────────────────────────────────────────────────────────────

@test "uninstall.sh: offers to remove git clone if present" {
    local pdir="$BATS_TEST_TMPDIR/fleetman_clone"
    mkdir -p "$pdir/.git"
    export FLEETMAN_DIR="$pdir"
    local short
    short=$(hostname -f 2>/dev/null | cut -d. -f1)
    export UNINSTALL_SSH_MODE=ok
    # Answer 'n' to keep the clone
    run bash "$SCRIPTS_DIR/internal/uninstall.sh" < <(printf '%s\nyes\nUNINSTALL\nn\n' "$short")
    [[ "$output" == *"Git clone found"* ]]
    [ -d "$pdir" ]
}

@test "uninstall.sh: remote clone detected → displays server:pdir (response n)" {
    local short
    short=$(hostname -f 2>/dev/null | cut -d. -f1)
    export UNINSTALL_SSH_MODE=ok
    export CLONE_SCAN_MODE=found
    run bash "$SCRIPTS_DIR/internal/uninstall.sh" \
        < <(printf '%s\nyes\nUNINSTALL\nn\n' "$short")
    [ "$status" -eq 0 ]
    [[ "$output" == *"Git clone found at"* ]]
    [[ "$output" == *":"* ]]
}

@test "uninstall.sh: remote clone + response y → ssh rm -rf called" {
    local short
    short=$(hostname -f 2>/dev/null | cut -d. -f1)
    export UNINSTALL_SSH_MODE=ok
    export CLONE_SCAN_MODE=found
    run bash "$SCRIPTS_DIR/internal/uninstall.sh" \
        < <(printf '%s\nyes\nUNINSTALL\ny\n' "$short")
    [ "$status" -eq 0 ]
    grep -q "rm -rf" "$BATS_TEST_TMPDIR/ssh_calls"
}
