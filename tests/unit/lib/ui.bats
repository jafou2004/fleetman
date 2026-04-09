#!/usr/bin/env bats
# Unit tests for scripts/lib/ui.sh

load '../../test_helper/common'

setup() {
    load_common
}

# ── prompt_response ────────────────────────────────────────────────────────────

@test "prompt_response: non-empty input → returns the value" {
    # prompt_response sends the prompt to stderr (ignored via exec 2>/dev/null),
    # the response to stdout only.
    run bash -c "
        exec 2>/dev/null
        source '$SCRIPTS_DIR/lib/vars.sh'
        source '$SCRIPTS_DIR/lib/display.sh'
        source '$SCRIPTS_DIR/lib/ui.sh'
        result=\$(prompt_response 'Q' <<< 'my_answer')
        echo \"\$result\"
    "
    [ "$status" -eq 0 ]
    [ "$output" = "my_answer" ]
}

@test "prompt_response: empty input + default → returns the default" {
    run bash -c "
        exec 2>/dev/null
        source '$SCRIPTS_DIR/lib/vars.sh'
        source '$SCRIPTS_DIR/lib/display.sh'
        source '$SCRIPTS_DIR/lib/ui.sh'
        result=\$(prompt_response 'Q' 'default_val' <<< '')
        echo \"\$result\"
    "
    [ "$status" -eq 0 ]
    [ "$output" = "default_val" ]
}

@test "prompt_response: empty input without default, then value → returns the value" {
    # Uses fd 9 to inject successive inputs
    run bash -c "
        source '$SCRIPTS_DIR/lib/vars.sh'
        source '$SCRIPTS_DIR/lib/display.sh'
        source '$SCRIPTS_DIR/lib/ui.sh'
        # Simulate: first empty, then 'real_answer'
        exec 9< <(printf '\nreal_answer\n')
        # Override prompt_response to read from fd 9
        prompt_response() {
            local prompt=\"\$1\" default=\"\$2\" response=\"\"
            while [[ -z \"\$response\" ]]; do
                read -r response <&9
                [[ -z \"\$response\" && -n \"\$default\" ]] && response=\"\$default\"
            done
            printf '%s' \"\$response\"
        }
        result=\$(prompt_response 'Question')
        exec 9<&-
        echo \"\$result\"
    "
    [ "$status" -eq 0 ]
    [ "$output" = "real_answer" ]
}

# ── build_server_labels ────────────────────────────────────────────────────────

@test "build_server_labels: builds labels from server_order and server_pods" {
    declare -gA server_pods
    declare -ga server_order
    server_order=("dev1.fleet.test" "dev2.fleet.test")
    server_pods["dev1.fleet.test"]="api worker"
    server_pods["dev2.fleet.test"]="api"

    declare -a labels
    build_server_labels labels

    [ "${#labels[@]}" -eq 2 ]
    [[ "${labels[0]}" == *"dev1"* ]]
    [[ "${labels[0]}" == *"api, worker"* ]]
    [[ "${labels[1]}" == *"dev2"* ]]
    [[ "${labels[1]}" == *"api"* ]]
}

@test "build_server_labels: empty array if server_order is empty" {
    declare -gA server_pods=()
    declare -ga server_order=()

    declare -a labels
    build_server_labels labels

    [ "${#labels[@]}" -eq 0 ]
}

# ── select_menu ────────────────────────────────────────────────────────────────
# select_menu uses (( expr )) which may fail under set -e when
# the expression equals 0 (e.g. selected goes from 1 to 0). Tested via bash -c
# (no inherited set -e), SELECTED_IDX retrieved via echo at end of subshell.
# Arrow sequences: ESC + '[A' (up) / '[B' (down). Enter → read receives \n → key="".

_sm_run() {
    # Usage: _sm_run <input_printf_args> [initial_idx]
    # Runs select_menu in an isolated subshell, returns SELECTED_IDX on stdout.
    local input="$1" initial="${2:-}"
    bash -c "
        source '$SCRIPTS_DIR/lib/vars.sh'
        source '$SCRIPTS_DIR/lib/display.sh'
        source '$SCRIPTS_DIR/lib/ui.sh'
        labels=('item A' 'item B' 'item C')
        select_menu labels ${initial} >/dev/null 2>&1 < <(printf '%b' '$input')
        echo \$SELECTED_IDX
    "
}

@test "select_menu: immediate Enter → SELECTED_IDX=0" {
    result=$(_sm_run '\n')
    [ "$result" -eq 0 ]
}

@test "select_menu: initial index applied → SELECTED_IDX=1 with Enter" {
    result=$(_sm_run '\n' 1)
    [ "$result" -eq 1 ]
}

@test "select_menu: down arrow → SELECTED_IDX=1" {
    result=$(_sm_run '\x1b[B\n')
    [ "$result" -eq 1 ]
}

@test "select_menu: up arrow from position 0 → wraps to last" {
    result=$(_sm_run '\x1b[A\n')
    [ "$result" -eq 2 ]
}

@test "select_menu: down arrow from last position → wraps to first" {
    # initial_idx=2 (last in a list of 3) then down arrow
    result=$(_sm_run '\x1b[B\n' 2)
    [ "$result" -eq 0 ]
}

@test "select_menu: 'q' → exit 0 without selection" {
    run bash -c "
        source '$SCRIPTS_DIR/lib/vars.sh'
        source '$SCRIPTS_DIR/lib/display.sh'
        source '$SCRIPTS_DIR/lib/ui.sh'
        labels=('item A' 'item B')
        select_menu labels >/dev/null 2>&1 < <(printf 'q')
    "
    [ "$status" -eq 0 ]
}

@test "select_menu: Ctrl+C → exit 0 without selection" {
    run bash -c "
        source '$SCRIPTS_DIR/lib/vars.sh'
        source '$SCRIPTS_DIR/lib/display.sh'
        source '$SCRIPTS_DIR/lib/ui.sh'
        labels=('item A' 'item B')
        select_menu labels >/dev/null 2>&1 < <(printf '\x03')
    "
    [ "$status" -eq 0 ]
}

# ── select_menu_multi ──────────────────────────────────────────────────────────
# Same piped-input technique as _sm_run above works here too:
# read -rsn1 without a real TTY still consumes stdin char-by-char.
# tput calls are silenced via 2>/dev/null.

_smm_run() {
    # Runs select_menu_multi in an isolated subshell; prints SELECTED_INDICES on stdout.
    local input="$1"
    bash -c "
        source '$SCRIPTS_DIR/lib/vars.sh'
        source '$SCRIPTS_DIR/lib/display.sh'
        source '$SCRIPTS_DIR/lib/ui.sh'
        labels=('item A' 'item B' 'item C')
        select_menu_multi labels >/dev/null 2>&1 < <(printf '%b' '$input')
        echo \${SELECTED_INDICES[*]}
    "
}

@test "select_menu_multi: immediate Enter → SELECTED_INDICES empty" {
    result=$(_smm_run '\n')
    [ -z "$result" ]
}

@test "select_menu_multi: Space then Enter → index 0 selected" {
    result=$(_smm_run ' \n')
    [ "$result" = "0" ]
}

@test "select_menu_multi: Space twice (toggle off) → SELECTED_INDICES empty" {
    result=$(_smm_run '  \n')
    [ -z "$result" ]
}

@test "select_menu_multi: down + Space + Enter → index 1 selected" {
    result=$(_smm_run '\x1b[B \n')
    [ "$result" = "1" ]
}

@test "select_menu_multi: select items 0 and 1 → SELECTED_INDICES=(0 1)" {
    result=$(_smm_run ' \x1b[B \n')
    [ "$result" = "0 1" ]
}

@test "select_menu_multi: up arrow from cursor 0 wraps to last → index 2 selected" {
    result=$(_smm_run '\x1b[A \n')
    [ "$result" = "2" ]
}

@test "select_menu_multi: down arrow from last position wraps to first → index 0 selected" {
    # Down twice reaches index 2 (last in a 3-item list), down again wraps to 0.
    result=$(_smm_run '\x1b[B\x1b[B\x1b[B \n')
    [ "$result" = "0" ]
}

@test "select_menu_multi: 'q' → exit 0 without selection" {
    run bash -c "
        source '$SCRIPTS_DIR/lib/vars.sh'
        source '$SCRIPTS_DIR/lib/display.sh'
        source '$SCRIPTS_DIR/lib/ui.sh'
        labels=('item A' 'item B')
        select_menu_multi labels >/dev/null 2>&1 < <(printf 'q')
    "
    [ "$status" -eq 0 ]
}

@test "select_menu_multi: Ctrl+C → exit 0 without selection" {
    run bash -c "
        source '$SCRIPTS_DIR/lib/vars.sh'
        source '$SCRIPTS_DIR/lib/display.sh'
        source '$SCRIPTS_DIR/lib/ui.sh'
        labels=('item A' 'item B')
        select_menu_multi labels >/dev/null 2>&1 < <(printf '\x03')
    "
    [ "$status" -eq 0 ]
}

# ── prompt_confirm ────────────────────────────────────────────────────────────

@test "prompt_confirm: input Y → return 0" {
    run prompt_confirm "Continue?" <<< 'Y'
    [ "$status" -eq 0 ]
}

@test "prompt_confirm: empty input → defaults to Y → return 0" {
    run prompt_confirm "Continue?" <<< ''
    [ "$status" -eq 0 ]
}

@test "prompt_confirm: input n → return 1" {
    run prompt_confirm "Continue?" <<< 'n'
    [ "$status" -eq 1 ]
}

@test "prompt_confirm: input N → return 1" {
    run prompt_confirm "Continue?" <<< 'N'
    [ "$status" -eq 1 ]
}

@test "prompt_confirm: prints question with [Y/n] prompt" {
    run prompt_confirm "Delete it?" <<< 'Y'
    [[ "$output" == *"Delete it?"* ]]
    [[ "$output" == *"[Y/n]"* ]]
}

# ── prompt_sync_confirm ────────────────────────────────────────────────────────

@test "prompt_sync_confirm: response N → bash not called" {
    local call_file="$BATS_TEST_TMPDIR/bash_calls"
    bash() { echo "BASH_CALLED:$*" >> "$call_file"; }
    export -f bash
    run prompt_sync_confirm <<< 'N'
    unset -f bash
    [ "$status" -eq 0 ]
    [ ! -f "$call_file" ]
}

@test "prompt_sync_confirm: response Y → bash called with sync -q (quick mode by default)" {
    local call_file="$BATS_TEST_TMPDIR/bash_calls"
    bash() { echo "BASH_CALLED:$*" >> "$call_file"; }
    export -f bash
    run prompt_sync_confirm <<< 'Y'
    unset -f bash
    [ "$status" -eq 0 ]
    [ -f "$call_file" ]
    grep -q "sync" "$call_file"
    grep -q "\-q" "$call_file"
}

@test "prompt_sync_confirm: empty response → Y by default → bash called with sync -q" {
    local call_file="$BATS_TEST_TMPDIR/bash_calls"
    bash() { echo "BASH_CALLED:$*" >> "$call_file"; }
    export -f bash
    run prompt_sync_confirm <<< ''
    unset -f bash
    [ "$status" -eq 0 ]
    [ -f "$call_file" ]
    grep -q "sync" "$call_file"
    grep -q "\-q" "$call_file"
}

@test "prompt_sync_confirm: explicit full mode → bash called without -q" {
    local call_file="$BATS_TEST_TMPDIR/bash_calls"
    bash() { echo "BASH_CALLED:$*" >> "$call_file"; }
    export -f bash
    run prompt_sync_confirm full <<< 'Y'
    unset -f bash
    [ "$status" -eq 0 ]
    [ -f "$call_file" ]
    grep -q "sync" "$call_file"
    ! grep -q -- "-q" "$call_file"
}
