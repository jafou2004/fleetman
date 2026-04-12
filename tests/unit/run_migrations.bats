#!/usr/bin/env bats
# Unit tests for run_migrations.sh

load '../test_helper/common'

setup() {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    load_common
    source "$PROJECT_ROOT/run_migrations.sh"
    # Override _MIGRATIONS_DIR to a test-controlled location
    _MIGRATIONS_DIR="$BATS_TEST_TMPDIR/migrations"
    mkdir -p "$_MIGRATIONS_DIR"
}

# ── _ver_lt ────────────────────────────────────────────────────────────────────

@test "_ver_lt: 1.0.0 < 1.1.0 → return 0" {
    run _ver_lt "1.0.0" "1.1.0"
    [ "$status" -eq 0 ]
}

@test "_ver_lt: 1.1.0 < 1.0.0 → return 1" {
    run _ver_lt "1.1.0" "1.0.0"
    [ "$status" -eq 1 ]
}

@test "_ver_lt: equal → return 1" {
    run _ver_lt "1.0.0" "1.0.0"
    [ "$status" -eq 1 ]
}

@test "_ver_lt: v-prefix ignored — v1.0.0 < v1.1.0 → return 0" {
    run _ver_lt "v1.0.0" "v1.1.0"
    [ "$status" -eq 0 ]
}

@test "_ver_lt: 3-digit versions — 1.9.0 < 1.10.0 → return 0" {
    run _ver_lt "1.9.0" "1.10.0"
    [ "$status" -eq 0 ]
}

# ── main (run_migrations) ──────────────────────────────────────────────────────

@test "run_migrations: no file → displays No migration to apply" {
    run main "1.0.0" "1.1.0"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No migration to apply"* ]]
}

@test "run_migrations: migration within window → executed" {
    echo 'echo "MIGRATION_RAN"' > "$_MIGRATIONS_DIR/v1.1.0.sh"
    chmod +x "$_MIGRATIONS_DIR/v1.1.0.sh"
    run main "1.0.0" "1.1.0"
    [ "$status" -eq 0 ]
    [[ "$output" == *"MIGRATION_RAN"* ]]
}

@test "run_migrations: multiple migrations executed in order" {
    echo 'echo "MIG_A"' > "$_MIGRATIONS_DIR/v1.1.0.sh"
    echo 'echo "MIG_B"' > "$_MIGRATIONS_DIR/v1.2.0.sh"
    chmod +x "$_MIGRATIONS_DIR/v1.1.0.sh" "$_MIGRATIONS_DIR/v1.2.0.sh"
    run main "1.0.0" "1.2.0"
    [ "$status" -eq 0 ]
    [[ "$output" == *"MIG_A"* ]]
    [[ "$output" == *"MIG_B"* ]]
    # Verify order: MIG_A appears before MIG_B
    local pos_a pos_b
    pos_a=$(echo "$output" | grep -n "MIG_A" | cut -d: -f1)
    pos_b=$(echo "$output" | grep -n "MIG_B" | cut -d: -f1)
    [ "$pos_a" -lt "$pos_b" ]
}

@test "run_migrations: too old migration → ignored" {
    echo 'echo "OLD_MIG"' > "$_MIGRATIONS_DIR/v0.9.0.sh"
    chmod +x "$_MIGRATIONS_DIR/v0.9.0.sh"
    run main "1.0.0" "1.1.0"
    [ "$status" -eq 0 ]
    [[ "$output" != *"OLD_MIG"* ]]
}

@test "run_migrations: migration equal to new_ver → executed (inclusive bound)" {
    echo 'echo "EXACT_VER"' > "$_MIGRATIONS_DIR/v1.1.0.sh"
    chmod +x "$_MIGRATIONS_DIR/v1.1.0.sh"
    run main "1.0.0" "1.1.0"
    [ "$status" -eq 0 ]
    [[ "$output" == *"EXACT_VER"* ]]
}

@test "run_migrations: migration equal to old_ver → ignored (exclusive bound)" {
    echo 'echo "OLD_EXACT"' > "$_MIGRATIONS_DIR/v1.0.0.sh"
    chmod +x "$_MIGRATIONS_DIR/v1.0.0.sh"
    run main "1.0.0" "1.1.0"
    [ "$status" -eq 0 ]
    [[ "$output" != *"OLD_EXACT"* ]]
}

@test "run_migrations: displays section header with versions" {
    run main "1.0.0" "1.1.0"
    [ "$status" -eq 0 ]
    [[ "$output" == *"1.0.0"*"1.1.0"* ]]
}

@test "run_migrations: displays the title of each migration" {
    echo 'echo "MIG"' > "$_MIGRATIONS_DIR/v1.1.0.sh"
    chmod +x "$_MIGRATIONS_DIR/v1.1.0.sh"
    run main "1.0.0" "1.1.0"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Migration to v1.1.0"* ]]
}
