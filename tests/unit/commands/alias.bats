#!/usr/bin/env bats
# Unit tests for scripts/commands/alias.sh

load '../../test_helper/common'

setup() {
    load_common
    cp "$FIXTURES_DIR/.bash_aliases" "$HOME/.bash_aliases"
    source "$SCRIPTS_DIR/commands/alias.sh"
}

# ── Option validation ─────────────────────────────────────────────────────────

@test "cmd_alias: -c without argument → exit 1 + error message" {
    run cmd_alias -c
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires an argument"* ]]
}

@test "cmd_alias: unknown option → exit 1 + error message" {
    run cmd_alias -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

# ── Prerequisites ─────────────────────────────────────────────────────────────

@test "cmd_alias: missing file → exit 1 + error message" {
    rm -f "$HOME/.bash_aliases"
    run cmd_alias
    [ "$status" -eq 1 ]
    [[ "$output" == *"✗"* ]]
}

# ── No filter ─────────────────────────────────────────────────────────────────

@test "cmd_alias: no filter → all categories displayed with titles" {
    run cmd_alias
    [ "$status" -eq 0 ]
    [[ "$output" == *"Git"* ]]
    [[ "$output" == *"Docker"* ]]
    [[ "$output" == *"Scripts"* ]]
    [[ "$output" == *"###"* ]]
}

@test "cmd_alias: no filter → aliases from each category are present" {
    run cmd_alias
    [ "$status" -eq 0 ]
    [[ "$output" == *"gs"* ]]
    [[ "$output" == *"dps"* ]]
    [[ "$output" == *"fl"* ]]
}

# ── Single filter ─────────────────────────────────────────────────────────────

@test "cmd_alias: filter 'git' → Git only, without title" {
    run cmd_alias -c git
    [ "$status" -eq 0 ]
    [[ "$output" == *"gs"* ]]
    [[ "$output" == *"gl"* ]]
    [[ "$output" != *"###"* ]]
    [[ "$output" != *"Docker"* ]]
    [[ "$output" != *"Scripts"* ]]
}

@test "cmd_alias: case-insensitive filter → 'GIT' matches Git" {
    run cmd_alias -c GIT
    [ "$status" -eq 0 ]
    [[ "$output" == *"gs"* ]]
    [[ "$output" != *"Docker"* ]]
}

@test "cmd_alias: filter 'doc' → Docker only (prefix match)" {
    run cmd_alias -c doc
    [ "$status" -eq 0 ]
    [[ "$output" == *"dps"* ]]
    [[ "$output" != *"###"* ]]
    [[ "$output" != *"Git"* ]]
}

# ── Filter with no match ──────────────────────────────────────────────────────

@test "cmd_alias: unknown filter → exit 1 + error message" {
    run cmd_alias -c zzz_inexistant
    [ "$status" -eq 1 ]
    [[ "$output" == *"✗"* ]]
    [[ "$output" == *"zzz_inexistant"* ]]
}

# ── Empty file / no categories ────────────────────────────────────────────────

@test "cmd_alias: empty file → exit 1 + warning (⚠)" {
    printf '' > "$HOME/.bash_aliases"
    run cmd_alias
    [ "$status" -eq 1 ]
    [[ "$output" == *"⚠"* ]]
    [[ "$output" != *"✗"* ]]
}

@test "cmd_alias: file without categories → warn 'No aliases defined yet'" {
    printf '# plain comment\n# another line\n' > "$HOME/.bash_aliases"
    run cmd_alias
    [ "$status" -eq 1 ]
    [[ "$output" == *"No aliases defined yet"* ]]
}

@test "cmd_alias: empty file with -c → warn (not err 'No category')" {
    printf '' > "$HOME/.bash_aliases"
    run cmd_alias -c git
    [ "$status" -eq 1 ]
    [[ "$output" == *"⚠"* ]]
    [[ "$output" != *"No category found"* ]]
}

# ── Description display ───────────────────────────────────────────────────────

@test "cmd_alias: alias with inline comment → displays description, not raw value" {
    run cmd_alias -c git
    [ "$status" -eq 0 ]
    # gs='git status' # Show working tree status → displays "Show working tree status"
    [[ "$output" == *"Show working tree status"* ]]
    [[ "$output" != *"'git status'"* ]]
}

@test "cmd_alias: alias without comment → displays cleaned value (without quotes)" {
    run cmd_alias -c git
    [ "$status" -eq 0 ]
    # gl='git log --oneline -10' (no comment) → displays "git log --oneline -10"
    [[ "$output" == *"git log --oneline -10"* ]]
}

@test "cmd_alias: alias with double-quote comment → displays description" {
    # Inject an alias with double quotes and comment
    echo '# ### Custom' >> "$HOME/.bash_aliases"
    echo 'alias myalias="some command" # My description' >> "$HOME/.bash_aliases"
    run cmd_alias -c custom
    [ "$status" -eq 0 ]
    [[ "$output" == *"My description"* ]]
}

# ── Separator arrow ───────────────────────────────────────────────────────────

@test "cmd_alias: output contains '→' arrows between name and value" {
    run cmd_alias -c git
    [ "$status" -eq 0 ]
    [[ "$output" == *"→"* ]]
}

# ── Direct coverage (without run, for kcov) ───────────────────────────────────

@test "cmd_alias: direct call with comment → BASH_REMATCH (line 61)" {
    # Call without 'run': executes in current shell, kcov traces line 61
    cmd_alias -c git > "$BATS_TEST_TMPDIR/out.txt"
    grep -q "Show working tree status" "$BATS_TEST_TMPDIR/out.txt"
}

@test "cmd_alias: direct mapfile call → for loop iterates all lines (line 71)" {
    # Covers the for loop that replaces while...done < file
    cmd_alias > "$BATS_TEST_TMPDIR/out.txt"
    grep -q "Git" "$BATS_TEST_TMPDIR/out.txt"
    grep -q "Docker" "$BATS_TEST_TMPDIR/out.txt"
    grep -q "Scripts" "$BATS_TEST_TMPDIR/out.txt"
}
