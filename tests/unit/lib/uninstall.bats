#!/usr/bin/env bats
# Unit tests for scripts/lib/uninstall.sh

load '../../test_helper/common'

setup() {
    load_common
    source "$SCRIPTS_DIR/lib/uninstall.sh"
    # Silence tput (no TTY in tests)
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    printf '#!/bin/bash\n' > "$BATS_TEST_TMPDIR/bin/tput"
    chmod +x "$BATS_TEST_TMPDIR/bin/tput"
    # Crontab mock: reads/writes a file; atomic write to avoid pipeline race
    printf '#!/bin/bash\n_f="%s"\nif [[ "$1" == "-l" ]]; then cat "$_f"; fi\nif [[ "$1" == "-" ]]; then _t=$(mktemp); cat > "$_t"; mv "$_t" "$_f"; fi\n' \
        "$BATS_TEST_TMPDIR/crontab_store" > "$BATS_TEST_TMPDIR/bin/crontab"
    chmod +x "$BATS_TEST_TMPDIR/bin/crontab"
    printf '' > "$BATS_TEST_TMPDIR/crontab_store"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    # .bashrc with a FLEETMAN block
    printf '# existing\n# BEGIN FLEETMAN\nexport PATH="$HOME/scripts/bin:$PATH"\n# END FLEETMAN\n' \
        > "$HOME/.bashrc"
}

# ── uninstall_remote ───────────────────────────────────────────────────────────

@test "uninstall_remote: SSH succeeds with all sentinels → exit 0 + ✓" {
    ssh_cmd() {
        echo "BASHRC_DONE"; echo "CRON_DONE"
        echo "FILES_DONE"; echo "DATA_DONE"; echo "SCRIPTS_DONE"
    }
    export -f ssh_cmd
    run uninstall_remote "srv.fleet.test"
    [ "$status" -eq 0 ]
    [[ "$output" == *"✓"* ]]
}

@test "uninstall_remote: SSH exit code non-zero → exit 1 + ✗" {
    ssh_cmd() { return 1; }
    export -f ssh_cmd
    run uninstall_remote "srv.fleet.test"
    [ "$status" -eq 1 ]
    [[ "$output" == *"✗"* ]]
}

@test "uninstall_remote: SCRIPTS_DONE sentinel absent → exit 1" {
    ssh_cmd() {
        echo "BASHRC_DONE"; echo "CRON_DONE"
        echo "FILES_DONE"; echo "DATA_DONE"
    }
    export -f ssh_cmd
    run uninstall_remote "srv.fleet.test"
    [ "$status" -eq 1 ]
}

# ── uninstall_local ────────────────────────────────────────────────────────────

@test "uninstall_local: removes BEGIN/END FLEETMAN block from .bashrc" {
    uninstall_local
    run grep -c "BEGIN FLEETMAN" "$HOME/.bashrc"
    [ "$output" = "0" ]
}

@test "uninstall_local: removes fleetman crontab entries" {
    printf '0 1 * * * bash ~/scripts/bin/fleetman selfupdate\n' \
        > "$BATS_TEST_TMPDIR/crontab_store"
    uninstall_local
    run grep -c "fleetman" "$BATS_TEST_TMPDIR/crontab_store"
    [ "$output" = "0" ]
}

@test "uninstall_local: no error when files and dirs absent" {
    run uninstall_local
    [ "$status" -eq 0 ]
}

# ── delete_ascii ───────────────────────────────────────────────────────────────

@test "delete_ascii: ASCII file present → deleted + ✓ in output" {
    mkdir -p "$HOME/.data"
    export DATA_DIR="$HOME/.data"
    touch "$HOME/.data/welcome_srv1.ascii"
    run delete_ascii "srv1.fleet.test"
    [ "$status" -eq 0 ]
    [ ! -f "$HOME/.data/welcome_srv1.ascii" ]
    [[ "$output" == *"✓"* ]]
}

@test "delete_ascii: ASCII file absent → exit 0, no error" {
    export DATA_DIR="$HOME/.data"
    run delete_ascii "noserver.fleet.test"
    [ "$status" -eq 0 ]
}
