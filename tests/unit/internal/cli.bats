#!/usr/bin/env bats
# Unit tests for scripts/internal/cli.sh

load '../../test_helper/common'

setup() {
    load_common
    source "$SCRIPTS_DIR/internal/cli.sh"

    # Create a fake commands directory for tests
    export TEST_CMD_DIR="$BATS_TEST_TMPDIR/commands"
    mkdir -p "$TEST_CMD_DIR/pod"

    # Create a fake command with docblock
    cat > "$TEST_CMD_DIR/sync.sh" << 'EOF'
#!/bin/bash
##
# Synchronizes the fleet.
#
# Usage: fleetman sync [-h]
#
# Options:
#   -h, --help   Show this help
##
cmd_sync() { echo "cmd_sync called with: $*"; }
EOF

    # Create a fake subcommand
    cat > "$TEST_CMD_DIR/pod/pull.sh" << 'EOF'
#!/bin/bash
##
# Pulls a pod image.
#
# Usage: fleetman pod pull [-p pod]
#
# Options:
#   -p <pod>     Pod name
#   -h, --help   Show this help
##
cmd_pod_pull() { echo "cmd_pod_pull called with: $*"; }
EOF
}

# ── _cli_extract_desc ──────────────────────────────────────────────────────────

@test "_cli_extract_desc: extracts the first line of the docblock" {
    run _cli_extract_desc "$TEST_CMD_DIR/sync.sh"
    [ "$status" -eq 0 ]
    [ "$output" = "Synchronizes the fleet." ]
}

@test "_cli_extract_desc: file without docblock → empty output" {
    local tmpfile="$BATS_TEST_TMPDIR/nocmd.sh"
    echo "#!/bin/bash" > "$tmpfile"
    echo "# This is a regular comment, not a docblock" >> "$tmpfile"
    run _cli_extract_desc "$tmpfile"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ── _cli_cmd_help ──────────────────────────────────────────────────────────────

@test "_cli_cmd_help: returns the full docblock content without '# ' prefixes" {
    run _cli_cmd_help "$TEST_CMD_DIR/sync.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Synchronizes the fleet."* ]]
    [[ "$output" == *"Usage: fleetman sync"* ]]
    [[ "$output" == *"-h, --help"* ]]
}

@test "_cli_cmd_help: lone '#' lines become empty lines" {
    run _cli_cmd_help "$TEST_CMD_DIR/sync.sh"
    # Must have empty lines in the output ('#' lines converted)
    [[ "$output" == *$'\n'* ]]
}

@test "_cli_cmd_help: injects subcommand list if a sibling directory exists" {
    mkdir -p "$TEST_CMD_DIR/sync"
    cat > "$TEST_CMD_DIR/sync/sub.sh" << 'EOF'
#!/bin/bash
##
# Does something specific.
##
EOF
    run _cli_cmd_help "$TEST_CMD_DIR/sync.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Available subcommands:"* ]]
    [[ "$output" == *"sub"* ]]
    [[ "$output" == *"Does something specific."* ]]
}

@test "_cli_cmd_help: no subcommands section if no sibling directory" {
    run _cli_cmd_help "$TEST_CMD_DIR/sync.sh"
    [ "$status" -eq 0 ]
    [[ "$output" != *"Available subcommands:"* ]]
}

# ── _cli_try_load ──────────────────────────────────────────────────────────────

@test "_cli_try_load: loads commands/sync.sh → returns 0 and sets _CLI_LOADED_FILE" {
    _CLI_LOADED_FILE=""
    _cli_try_load "$TEST_CMD_DIR" "cmd_sync"
    [ "$?" -eq 0 ]
    [ "$_CLI_LOADED_FILE" = "$TEST_CMD_DIR/sync.sh" ]
}

@test "_cli_try_load: loads commands/pod/pull.sh → returns 0" {
    _CLI_LOADED_FILE=""
    _cli_try_load "$TEST_CMD_DIR" "cmd_pod_pull"
    [ "$?" -eq 0 ]
    [ "$_CLI_LOADED_FILE" = "$TEST_CMD_DIR/pod/pull.sh" ]
}

@test "_cli_try_load: non-existent file → returns 1" {
    run _cli_try_load "$TEST_CMD_DIR" "cmd_nonexistent"
    [ "$status" -eq 1 ]
}

# ── cli_dispatch ───────────────────────────────────────────────────────────────

@test "cli_dispatch: -h → displays help and exit 0" {
    run cli_dispatch "$TEST_CMD_DIR" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"$APP_NAME"* ]]
    [[ "$output" == *"Available commands"* ]]
}

@test "cli_dispatch: no args → displays help and exit 0" {
    run cli_dispatch "$TEST_CMD_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"$APP_NAME"* ]]
}

@test "cli_dispatch: known command 'sync' → calls cmd_sync" {
    run cli_dispatch "$TEST_CMD_DIR" sync
    [ "$status" -eq 0 ]
    [ "$output" = "cmd_sync called with: " ]
}

@test "cli_dispatch: subcommand 'pod pull' → calls cmd_pod_pull" {
    run cli_dispatch "$TEST_CMD_DIR" pod pull
    [ "$status" -eq 0 ]
    [ "$output" = "cmd_pod_pull called with: " ]
}

@test "cli_dispatch: unknown command → exit 1" {
    run cli_dispatch "$TEST_CMD_DIR" unknown_command
    [ "$status" -eq 1 ]
    [[ "$output" == *"✗"* ]]
    [[ "$output" == *"unknown_command"* ]]
}

@test "cli_dispatch: 'sync -h' → displays sync.sh docblock and exit 0" {
    run cli_dispatch "$TEST_CMD_DIR" sync -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Synchronizes the fleet."* ]]
    [[ "$output" == *"Usage: fleetman sync"* ]]
}

@test "cli_dispatch: 'pod pull -h' → displays pod/pull.sh docblock" {
    run cli_dispatch "$TEST_CMD_DIR" pod pull -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Pulls a pod image."* ]]
}

@test "cli_dispatch: 'pod -h' → lists subcommands from pod/ directory" {
    run cli_dispatch "$TEST_CMD_DIR" pod -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"pull"* ]]
}

@test "cli_dispatch: passes remaining flags to the command" {
    run cli_dispatch "$TEST_CMD_DIR" sync --flag value
    [ "$status" -eq 0 ]
    [ "$output" = "cmd_sync called with: --flag value" ]
}

# ── _cli_extract_tag ──────────────────────────────────────────────────────────

@test "_cli_extract_tag: extracts @menu from the docblock" {
    local tmpfile="$BATS_TEST_TMPDIR/tagged.sh"
    cat > "$tmpfile" << 'EOF'
##
# @menu My Entry
# @order 3
#
# Description here.
##
EOF
    run _cli_extract_tag "$tmpfile" "menu"
    [ "$status" -eq 0 ]
    [ "$output" = "My Entry" ]
}

@test "_cli_extract_tag: extracts @order from the docblock" {
    local tmpfile="$BATS_TEST_TMPDIR/tagged.sh"
    cat > "$tmpfile" << 'EOF'
##
# @menu My Entry
# @order 3
#
# Description here.
##
EOF
    run _cli_extract_tag "$tmpfile" "order"
    [ "$status" -eq 0 ]
    [ "$output" = "3" ]
}

@test "_cli_extract_tag: tag absent → exit 1 + empty output" {
    run _cli_extract_tag "$TEST_CMD_DIR/sync.sh" "menu"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

# ── _cli_scan_menu_dir ────────────────────────────────────────────────────────

@test "_cli_scan_menu_dir: returns entries sorted by @order" {
    local scandir="$BATS_TEST_TMPDIR/scandir_sort"
    mkdir -p "$scandir"
    cat > "$scandir/b.sh" << 'EOF'
##
# @menu B Entry
# @order 2
#
# B description.
##
EOF
    cat > "$scandir/a.sh" << 'EOF'
##
# @menu A Entry
# @order 1
#
# A description.
##
EOF
    run _cli_scan_menu_dir "$scandir"
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == "1|A Entry|"* ]]
    [[ "${lines[1]}" == "2|B Entry|"* ]]
}

@test "_cli_scan_menu_dir: file without @menu → exit 1 + error message" {
    local scandir="$BATS_TEST_TMPDIR/scandir_nomenu"
    mkdir -p "$scandir"
    cat > "$scandir/bad.sh" << 'EOF'
##
# @order 1
#
# Description.
##
EOF
    run _cli_scan_menu_dir "$scandir"
    [ "$status" -eq 1 ]
    [[ "$output" == *"✗"* ]]
    [[ "$output" == *"@menu"* ]]
}

# ── @tag lines skipped by existing parsers ────────────────────────────────────

@test "_cli_extract_desc: ignores @tag lines and returns the description" {
    local tmpfile="$BATS_TEST_TMPDIR/tagged_desc.sh"
    cat > "$tmpfile" << 'EOF'
##
# @menu My Entry
# @order 1
#
# Real description here.
##
EOF
    run _cli_extract_desc "$tmpfile"
    [ "$status" -eq 0 ]
    [ "$output" = "Real description here." ]
}

@test "_cli_cmd_help: @tag lines do not appear in the output" {
    local tmpfile="$BATS_TEST_TMPDIR/tagged_help.sh"
    cat > "$tmpfile" << 'EOF'
##
# @menu My Entry
# @order 1
#
# Real description here.
#
# Usage: fleetman config foo
##
EOF
    run _cli_cmd_help "$tmpfile"
    [ "$status" -eq 0 ]
    [[ "$output" != *"@menu"* ]]
    [[ "$output" != *"@order"* ]]
    [[ "$output" == *"Real description here."* ]]
}

@test "_cli_scan_menu_dir: file without @order → exit 1 + error message" {
    local scandir="$BATS_TEST_TMPDIR/scandir_noorder"
    mkdir -p "$scandir"
    cat > "$scandir/bad.sh" << 'EOF'
##
# @menu My Entry
#
# Description.
##
EOF
    run _cli_scan_menu_dir "$scandir"
    [ "$status" -eq 1 ]
    [[ "$output" == *"✗"* ]]
    [[ "$output" == *"@order"* ]]
}
