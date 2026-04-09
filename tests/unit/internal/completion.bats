#!/usr/bin/env bats
# Unit tests for scripts/internal/completion.sh

load '../../test_helper/common'

setup() {
    load_common
    # Create a fake commands directory
    export TEST_CMD_DIR="$BATS_TEST_TMPDIR/commands"
    mkdir -p "$TEST_CMD_DIR/pod"
    mkdir -p "$TEST_CMD_DIR/config/env"

    # Command with docblock and options
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
cmd_sync() { :; }
EOF

    cat > "$TEST_CMD_DIR/status.sh" << 'EOF'
#!/bin/bash
##
# Show fleet status.
#
# Usage: fleetman status [-e env] [-h]
#
# Options:
#   -e <env>     Filter by environment
#   -h, --help   Show this help
##
cmd_status() { :; }
EOF

    cat > "$TEST_CMD_DIR/pod/pull.sh" << 'EOF'
#!/bin/bash
##
# Pulls a pod image.
#
# Usage: fleetman pod pull [-p pod] [-e env] [-h]
#
# Options:
#   -p <pod>     Pod name
#   -e <env>     Environment filter
#   -h, --help   Show this help
##
cmd_pod_pull() { :; }
EOF

    cat > "$TEST_CMD_DIR/config/env/add.sh" << 'EOF'
#!/bin/bash
##
# @menu Add environment
# @order 1
#
# Add a new environment.
#
# Usage: fleetman config env add [-h]
#
# Options:
#   -h, --help   Show this help
##
cmd_config_env_add() { :; }
EOF

    cat > "$TEST_CMD_DIR/config/env/color.sh" << 'EOF'
#!/bin/bash
##
# @menu Change color
# @order 2
#
# Change environment color.
#
# Usage: fleetman config env color [-h]
#
# Options:
#   -h, --help   Show this help
##
cmd_config_env_color() { :; }
EOF

    # The bin directory must exist BEFORE writing to it
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

    # Create a fake fleetman binary pointing to our TEST_CMD_DIR
    cat > "$BATS_TEST_TMPDIR/bin/fleetman" << EOF
#!/bin/bash
# Fake fleetman binary for completion tests
echo "fleetman"
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/fleetman"

    source "$SCRIPTS_DIR/internal/completion.sh"
}

# ── _fleetman_opts_from_file ───────────────────────────────────────────────────

@test "_fleetman_opts_from_file: extracts flags from a docblock" {
    run _fleetman_opts_from_file "$TEST_CMD_DIR/status.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"-e"* ]]
    [[ "$output" == *"-h"* ]]
}

@test "_fleetman_opts_from_file: extracts multiple flags from docblock of pod/pull.sh" {
    run _fleetman_opts_from_file "$TEST_CMD_DIR/pod/pull.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"-p"* ]]
    [[ "$output" == *"-e"* ]]
    [[ "$output" == *"-h"* ]]
}

@test "_fleetman_opts_from_file: file without docblock → empty output" {
    local tmpfile="$BATS_TEST_TMPDIR/nocmd.sh"
    echo "#!/bin/bash" > "$tmpfile"
    run _fleetman_opts_from_file "$tmpfile"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "_fleetman_opts_from_file: command without options (-h only)" {
    run _fleetman_opts_from_file "$TEST_CMD_DIR/sync.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"-h"* ]]
    [[ "$output" != *"-p"* ]]
}

# ── _fleetman_completions ──────────────────────────────────────────────────────

# Note: _fleetman_completions requires the bash completion environment (COMP_WORDS, etc.)
# A test wrapper is created to simulate that environment.


@test "_fleetman_completions: COMP_WORDS=(fleetman '') → completes with top-level commands" {
    COMP_WORDS=("fleetman" "")
    COMP_CWORD=1
    COMPREPLY=()
    _fleetman_completions
    [[ " ${COMPREPLY[*]} " == *" sync "* ]]
    [[ " ${COMPREPLY[*]} " == *" status "* ]]
    [[ " ${COMPREPLY[*]} " == *" pod "* ]]
}

@test "_fleetman_completions: COMP_WORDS=(fleetman pod '') → completes with pod/ subcommands" {
    COMP_WORDS=("fleetman" "pod" "")
    COMP_CWORD=2
    COMPREPLY=()
    _fleetman_completions
    [[ " ${COMPREPLY[*]} " == *" pull "* ]]
}

@test "_fleetman_completions: prev='-e' → completes with envs from config.json" {
    COMP_WORDS=("fleetman" "status" "-e" "")
    COMP_CWORD=3
    COMPREPLY=()
    _fleetman_completions
    [[ " ${COMPREPLY[*]} " == *" dev "* ]] || \
    [[ " ${COMPREPLY[*]} " == *" test "* ]] || \
    [[ " ${COMPREPLY[*]} " == *" prod "* ]]
}

@test "_fleetman_completions: prev='-p' → completes with pods from pods.json" {
    COMP_WORDS=("fleetman" "pod" "pull" "-p" "")
    COMP_CWORD=4
    COMPREPLY=()
    _fleetman_completions
    [[ " ${COMPREPLY[*]} " == *" api "* ]] || [[ " ${COMPREPLY[*]} " == *" worker "* ]]
}

@test "_fleetman_completions: cur='-' → completes with options from file" {
    COMP_WORDS=("fleetman" "status" "-")
    COMP_CWORD=2
    COMPREPLY=()
    _fleetman_completions
    [[ " ${COMPREPLY[*]} " == *" -e "* ]] || [[ " ${COMPREPLY[*]} " == *" -h "* ]]
}

@test "_fleetman_completions: COMP_WORDS=(fleetman config env '') → completes with add and color" {
    COMP_WORDS=("fleetman" "config" "env" "")
    COMP_CWORD=3
    COMPREPLY=()
    _fleetman_completions
    [[ " ${COMPREPLY[*]} " == *" add "* ]]
    [[ " ${COMPREPLY[*]} " == *" color "* ]]
}

@test "_fleetman_completions: COMP_WORDS=(fleetman config env 'c') → completes to color" {
    COMP_WORDS=("fleetman" "config" "env" "c")
    COMP_CWORD=3
    COMPREPLY=()
    _fleetman_completions
    [[ " ${COMPREPLY[*]} " == *" color "* ]]
    [[ " ${COMPREPLY[*]} " != *" add "* ]]
}

@test "_fleetman_completions: COMP_WORDS=(fleetman config env color '-') → completes with options from color.sh" {
    COMP_WORDS=("fleetman" "config" "env" "color" "-")
    COMP_CWORD=4
    COMPREPLY=()
    _fleetman_completions
    [[ " ${COMPREPLY[*]} " == *" -h "* ]]
}
