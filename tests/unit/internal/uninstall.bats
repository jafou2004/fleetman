#!/usr/bin/env bats
# Unit tests for scripts/internal/uninstall.sh

load '../../test_helper/common'

setup() {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin" "$HOME/.ssh"

    # Mock crontab: -l → cat store, - → store stdin
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

    # Mock openssl: decrypt → "testpassword"
    cat > "$BATS_TEST_TMPDIR/bin/openssl" << 'EOF'
#!/bin/bash
mode=""
out_file=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        pkeyutl) shift ;;
        -encrypt) mode="encrypt"; shift ;;
        -decrypt) mode="decrypt"; shift ;;
        -out) out_file="$2"; shift 2 ;;
        *) shift ;;
    esac
done
if [[ "$mode" == "encrypt" && -n "$out_file" ]]; then
    printf 'ENCRYPTED' > "$out_file"; exit 0
elif [[ "$mode" == "decrypt" && -n "$out_file" ]]; then
    printf 'testpassword' > "$out_file"; exit 0
fi
exit 0
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/openssl"

    # fleet_key present → check_sshpass is no-op
    touch "$HOME/.ssh/fleet_key"
    export FLEET_KEY="$HOME/.ssh/fleet_key"

    load_common
    source "$SCRIPTS_DIR/internal/uninstall.sh"

    # Re-mock after sourcing (re-sourced libs overwrite function mocks)
    _spin_start() { :; }
    _spin_stop()  { :; }
    ask_password() { PASSWORD="testpass"; B64_PASS="dGVzdHBhc3M="; }
    ssh_cmd() { echo "$SSH_RESULT"; return "${SSH_RC:-0}"; }

    # MASTER_HOST outside the test fleet → all servers are "remote"
    export MASTER_HOST="master.local"
}

# ── help / options ────────────────────────────────────────────────────────────

@test "main: -h → exit 0 + Usage in output" {
    run main -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "main: unknown option → exit 1 + error message" {
    run main -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

# ── _confirm_uninstall ────────────────────────────────────────────────────────

@test "_confirm_uninstall: wrong hostname → exit 1" {
    export MASTER_HOST="server1.fleet.test"
    run _confirm_uninstall <<< $'WRONGNAME\nyes\nUNINSTALL\n'
    [ "$status" -eq 1 ]
    [[ "$output" == *"Confirmation failed"* ]]
}

@test "_confirm_uninstall: 'no' at 2nd question → exit 1" {
    export MASTER_HOST="server1.fleet.test"
    run _confirm_uninstall <<< $'server1\nno\nUNINSTALL\n'
    [ "$status" -eq 1 ]
    [[ "$output" == *"Confirmation failed"* ]]
}

@test "_confirm_uninstall: wrong keyword at 3rd question → exit 1" {
    export MASTER_HOST="server1.fleet.test"
    run _confirm_uninstall <<< $'server1\nyes\nuninstall\n'
    [ "$status" -eq 1 ]
    [[ "$output" == *"Confirmation failed"* ]]
}

@test "_confirm_uninstall: correct sequence → exit 0" {
    export MASTER_HOST="server1.fleet.test"
    run _confirm_uninstall <<< $'server1\nyes\nUNINSTALL\n'
    [ "$status" -eq 0 ]
}

@test "_confirm_uninstall: FQDN → short hostname used" {
    export MASTER_HOST="server1.example.com"
    run _confirm_uninstall <<< $'server1\nyes\nUNINSTALL\n'
    [ "$status" -eq 0 ]
}

# ── uninstall_local: .bashrc ──────────────────────────────────────────────────

@test "uninstall_local: removes .bashrc blocks added by sync" {
    cat > "$HOME/.bashrc" << 'EOF'
# existing content
export PATH="$HOME/.local/bin:$PATH"

# BEGIN FLEETMAN
export PATH="$HOME/scripts/bin:$PATH"
[[ -f ~/.data/fleetman.sh ]] && . ~/.data/fleetman.sh
# END FLEETMAN
EOF
    run uninstall_local
    [ "$status" -eq 0 ]
    # The FLEETMAN block must be absent
    run grep -c '# BEGIN FLEETMAN' "$HOME/.bashrc"
    [ "$output" -eq 0 ]
    run grep -c 'fleetman\.sh' "$HOME/.bashrc"
    [ "$output" -eq 0 ]
    run grep -c 'scripts/bin' "$HOME/.bashrc"
    [ "$output" -eq 0 ]
    # Pre-existing content must remain
    grep -q 'existing content' "$HOME/.bashrc"
}

@test "uninstall_local: removes the BEGIN/END FLEETMAN block from .bashrc" {
    cat > "$HOME/.bashrc" << 'EOF'
# existing content
export PATH="$HOME/.local/bin:$PATH"

# BEGIN FLEETMAN
[[ -f ~/.data/fleetman.sh ]] && . ~/.data/fleetman.sh
# END FLEETMAN
EOF
    run uninstall_local
    [ "$status" -eq 0 ]
    ! grep -q '# BEGIN FLEETMAN' "$HOME/.bashrc"
    ! grep -q 'fleetman\.sh' "$HOME/.bashrc"
    # Pre-existing content preserved
    grep -q 'existing content' "$HOME/.bashrc"
    grep -q '\.local/bin' "$HOME/.bashrc"
}

@test "uninstall_local: .bashrc absent → no error" {
    rm -f "$HOME/.bashrc"
    run uninstall_local
    [ "$status" -eq 0 ]
    [[ "$output" == *".bashrc blocks removed"* ]]
}

# ── uninstall_local: cron ─────────────────────────────────────────────────────

@test "uninstall_local: removes the sync cron entry" {
    local store="$BATS_TEST_TMPDIR/crontab_store"
    printf '0 1 * * * mv ~/.data/sync.log ~/.data/sync.log.1 2>/dev/null; bash ~/scripts/bin/fleetman sync > ~/.data/sync.log 2>&1\n' > "$store"

    run uninstall_local
    [ "$status" -eq 0 ]
    [[ "$output" == *"fleetman cron entries removed"* ]]
    ! grep -qF "bin/fleetman" "$store" 2>/dev/null
}

@test "uninstall_local: removes the selfupdate cron entry (backward compat)" {
    local store="$BATS_TEST_TMPDIR/crontab_store"
    printf '0 1 * * * bash ~/scripts/bin/fleetman selfupdate >> ~/.data/selfupdate.log 2>&1\n' > "$store"

    run uninstall_local
    [ "$status" -eq 0 ]
    [[ "$output" == *"fleetman cron entries removed"* ]]
    ! grep -qF "bin/fleetman selfupdate" "$store" 2>/dev/null
}

@test "uninstall_local: no fleetman cron entry → exit 0" {
    run uninstall_local
    [ "$status" -eq 0 ]
}

@test "uninstall_local: other cron entries preserved" {
    local store="$BATS_TEST_TMPDIR/crontab_store"
    printf '30 2 * * * /usr/bin/backup.sh\n0 1 * * * mv ~/.data/sync.log ~/.data/sync.log.1 2>/dev/null; bash ~/scripts/bin/fleetman sync > ~/.data/sync.log 2>&1\n' > "$store"

    run uninstall_local
    grep -qF "/usr/bin/backup.sh" "$store"
}

# ── uninstall_local: fleet files ─────────────────────────────────────────────

@test "uninstall_local: removes ~/.fleet_pass.enc" {
    touch "$HOME/.fleet_pass.enc"
    run uninstall_local
    [ "$status" -eq 0 ]
    [ ! -f "$HOME/.fleet_pass.enc" ]
}

@test "uninstall_local: removes ~/.ssh/fleet_key and fleet_key.pub" {
    touch "$HOME/.ssh/fleet_key" "$HOME/.ssh/fleet_key.pub"
    run uninstall_local
    [ "$status" -eq 0 ]
    [ ! -f "$HOME/.ssh/fleet_key" ]
    [ ! -f "$HOME/.ssh/fleet_key.pub" ]
}

@test "uninstall_local: removes ~/config.json" {
    run uninstall_local
    [ "$status" -eq 0 ]
    [ ! -f "$HOME/config.json" ]
}

@test "uninstall_local: removes ~/.bash_aliases" {
    touch "$HOME/.bash_aliases"
    run uninstall_local
    [ "$status" -eq 0 ]
    [ ! -f "$HOME/.bash_aliases" ]
}

@test "uninstall_local: removes ~/.data/" {
    mkdir -p "$HOME/.data"
    touch "$HOME/.data/pods.json"
    run uninstall_local
    [ "$status" -eq 0 ]
    [ ! -d "$HOME/.data" ]
}

# ── uninstall_local: ~/scripts ────────────────────────────────────────────────

@test "uninstall_local: ~/scripts symlink → removed" {
    # Recreate the symlink (load_common created it pointing to SCRIPTS_DIR)
    [ -L "$HOME/scripts" ] || ln -s /tmp "$HOME/scripts"
    run uninstall_local
    [ "$status" -eq 0 ]
    [ ! -L "$HOME/scripts" ]
}

@test "uninstall_local: ~/scripts real directory → removed" {
    rm -f "$HOME/scripts"
    mkdir -p "$HOME/scripts/bin"
    run uninstall_local
    [ "$status" -eq 0 ]
    [ ! -d "$HOME/scripts" ]
}

@test "uninstall_local: ~/scripts absent → exit 0" {
    rm -rf "$HOME/scripts"
    run uninstall_local
    [ "$status" -eq 0 ]
}

@test "uninstall_local: returns 0 + displays 'uninstalled'" {
    run uninstall_local
    [ "$status" -eq 0 ]
    [[ "$output" == *"uninstalled"* ]]
}

# ── uninstall_remote ──────────────────────────────────────────────────────────

@test "uninstall_remote: SSH ok + all markers → exit 0 + uninstalled" {
    export SSH_RESULT=$'BASHRC_DONE\nCRON_DONE\nFILES_DONE\nDATA_DONE\nSCRIPTS_DONE'
    export SSH_RC=0
    run uninstall_remote "remote1.fleet.test"
    [ "$status" -eq 0 ]
    [[ "$output" == *"uninstalled"* ]]
}

@test "uninstall_remote: SSH rc≠0 → exit 1 + error" {
    export SSH_RESULT=""
    export SSH_RC=1
    run uninstall_remote "remote1.fleet.test"
    [ "$status" -eq 1 ]
    [[ "$output" == *"failed"* ]]
}

@test "uninstall_remote: SCRIPTS_DONE absent → exit 1" {
    export SSH_RESULT=$'BASHRC_DONE\nCRON_DONE\nFILES_DONE\nDATA_DONE'
    export SSH_RC=0
    run uninstall_remote "remote1.fleet.test"
    [ "$status" -eq 1 ]
    [[ "$output" == *"failed"* ]]
}

@test "uninstall_remote: direct call → ssh_cmd called (kcov coverage)" {
    ssh_cmd() { echo "SSH_DIRECT:$1" >> "$BATS_TEST_TMPDIR/ssh_calls"
                printf 'BASHRC_DONE\nCRON_DONE\nFILES_DONE\nDATA_DONE\nSCRIPTS_DONE\n'; }
    uninstall_remote "test1.fleet.test" > "$BATS_TEST_TMPDIR/out.txt" || true
    grep -q "SSH_DIRECT:test1.fleet.test" "$BATS_TEST_TMPDIR/ssh_calls"
}

# ── _ask_remove_clone ─────────────────────────────────────────────────────────

@test "_ask_remove_clone: no clone → 'not found'" {
    export SSH_RC=1   # SSH scan must return "not found"
    run _ask_remove_clone <<< ''
    [ "$status" -eq 0 ]
    [[ "$output" == *"not found"* ]]
}

@test "_ask_remove_clone: clone present + response 'y' → removed" {
    local pdir="$BATS_TEST_TMPDIR/fleetman"
    mkdir -p "$pdir/.git"
    export FLEETMAN_DIR="$pdir"
    run _ask_remove_clone <<< 'y'
    [ "$status" -eq 0 ]
    [ ! -d "$pdir" ]
    [[ "$output" == *"Removed"* ]]
}

@test "_ask_remove_clone: clone present + response 'n' → kept" {
    local pdir="$BATS_TEST_TMPDIR/fleetman"
    mkdir -p "$pdir/.git"
    export FLEETMAN_DIR="$pdir"
    run _ask_remove_clone <<< 'n'
    [ "$status" -eq 0 ]
    [ -d "$pdir" ]
    [[ "$output" == *"kept"* ]]
}

@test "_ask_remove_clone: clone present + empty response → kept" {
    local pdir="$BATS_TEST_TMPDIR/fleetman"
    mkdir -p "$pdir/.git"
    export FLEETMAN_DIR="$pdir"
    run _ask_remove_clone <<< ''
    [ "$status" -eq 0 ]
    [ -d "$pdir" ]
}

@test "_ask_remove_clone: remote clone found + response 'y' → removed via SSH" {
    ssh_cmd() {
        local _server="$1"; shift
        if [[ "$*" == *"[ -d"* ]]; then
            return 0
        else
            echo "RM_CALL:$_server:$*" >> "$BATS_TEST_TMPDIR/ssh_calls"
            return 0
        fi
    }
    run _ask_remove_clone <<< 'y'
    [ "$status" -eq 0 ]
    [[ "$output" == *"Removed"* ]]
    grep -q "rm -rf" "$BATS_TEST_TMPDIR/ssh_calls"
}

@test "_ask_remove_clone: remote clone found + response 'n' → kept" {
    ssh_cmd() {
        local _server="$1"; shift
        if [[ "$*" == *"[ -d"* ]]; then
            return 0
        fi
        return 0
    }
    run _ask_remove_clone <<< 'n'
    [ "$status" -eq 0 ]
    [[ "$output" == *"kept at"*":"* ]]
}

@test "_ask_remove_clone: no clone (local or remote) → 'not found'" {
    ssh_cmd() { return 1; }
    run _ask_remove_clone <<< ''
    [ "$status" -eq 0 ]
    [[ "$output" == *"not found"* ]]
}

# ── uninstall_local: direct coverage (kcov) ──────────────────────────────────

@test "uninstall_local: direct call → ok 'Uninstalled' (kcov coverage)" {
    uninstall_local > "$BATS_TEST_TMPDIR/out.txt"
    grep -qi "uninstalled" "$BATS_TEST_TMPDIR/out.txt"
}
