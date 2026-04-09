#!/usr/bin/env bats
# Unit tests for scripts/lib/display.sh

load '../../test_helper/common'

setup() {
    load_common
}

# ── short_name ─────────────────────────────────────────────────────────────────

@test "short_name: FQDN → prefix before the first dot" {
    run short_name "server1.example.com"
    [ "$status" -eq 0 ]
    [ "$output" = "server1" ]
}

@test "short_name: hostname without dot → unchanged" {
    run short_name "server1"
    [ "$status" -eq 0 ]
    [ "$output" = "server1" ]
}

@test "short_name: multiple subdomains → first segment only" {
    run short_name "prod1.dc1.example.com"
    [ "$status" -eq 0 ]
    [ "$output" = "prod1" ]
}

# ── compute_title ──────────────────────────────────────────────────────────────

@test "compute_title: server1-rec.abc.example.com → Serveur Server 1 REC" {
    run compute_title "server1-rec.abc.example.com"
    [ "$status" -eq 0 ]
    [ "$output" = "Serveur Server 1 REC" ]
}

@test "compute_title: server2-prod.x.y.z → Serveur Server 2 PROD" {
    run compute_title "server2-prod.x.y.z"
    [ "$status" -eq 0 ]
    [ "$output" = "Serveur Server 2 PROD" ]
}

@test "compute_title: web3-dev.example.com → Serveur Web 3 DEV" {
    run compute_title "web3-dev.example.com"
    [ "$status" -eq 0 ]
    [ "$output" = "Serveur Web 3 DEV" ]
}

# ── ok / err / warn / section ──────────────────────────────────────────────────

@test "ok: output contains ✓ and the message" {
    run ok "All good"
    [ "$status" -eq 0 ]
    [[ "$output" == *"✓"* ]]
    [[ "$output" == *"All good"* ]]
}

@test "err: output contains ✗ and the message" {
    run err "Something failed"
    [ "$status" -eq 0 ]
    [[ "$output" == *"✗"* ]]
    [[ "$output" == *"Something failed"* ]]
}

@test "warn: output contains ⚠ and the message" {
    run warn "Take care"
    [ "$status" -eq 0 ]
    [[ "$output" == *"⚠"* ]]
    [[ "$output" == *"Take care"* ]]
}

@test "section: output contains === title ===" {
    run section "My Section"
    [ "$status" -eq 0 ]
    [[ "$output" == *"=== My Section ==="* ]]
}

# ── print_summary ──────────────────────────────────────────────────────────────

@test "print_summary: displays all 3 counters when all non-zero" {
    success_count=3
    warn_count=1
    failure_count=1
    run print_summary
    [ "$status" -eq 0 ]
    [[ "$output" == *"✓"* ]]
    [[ "$output" == *"⚠"* ]]
    [[ "$output" == *"✗"* ]]
}

@test "print_summary: does not display ✗ when failure_count=0" {
    success_count=2
    warn_count=0
    failure_count=0
    run print_summary
    [ "$status" -eq 0 ]
    [[ "$output" != *"✗"* ]]
}

@test "print_summary: does not display ⚠ when warn_count=0" {
    success_count=1
    warn_count=0
    failure_count=0
    run print_summary
    [ "$status" -eq 0 ]
    [[ "$output" != *"⚠"* ]]
}

# ── env_color_ansi ─────────────────────────────────────────────────────────────

@test "env_color_ansi: green fg → literal \\033[1;32m" {
    run env_color_ansi green fg
    [ "$status" -eq 0 ]
    [ "$output" = '\033[1;32m' ]
}

@test "env_color_ansi: green bg → literal \\033[37;1;42m" {
    run env_color_ansi green bg
    [ "$status" -eq 0 ]
    [ "$output" = '\033[37;1;42m' ]
}

@test "env_color_ansi: yellow fg → literal \\033[1;33m" {
    run env_color_ansi yellow fg
    [ "$status" -eq 0 ]
    [ "$output" = '\033[1;33m' ]
}

@test "env_color_ansi: red fg → literal \\033[1;31m" {
    run env_color_ansi red fg
    [ "$status" -eq 0 ]
    [ "$output" = '\033[1;31m' ]
}

@test "env_color_ansi: grey fg → grey text \\033[1;30m" {
    run env_color_ansi grey fg
    [ "$status" -eq 0 ]
    [ "$output" = '\033[1;30m' ]
}

@test "env_color_ansi: blue fg → blue text \\033[1;34m" {
    run env_color_ansi blue fg
    [ "$status" -eq 0 ]
    [ "$output" = '\033[1;34m' ]
}

@test "env_color_ansi: unknown color fg → reset \\033[0m" {
    run env_color_ansi unknown fg
    [ "$status" -eq 0 ]
    [ "$output" = '\033[0m' ]
}

@test "env_color_ansi: unknown color bg → reset \\033[0m" {
    run env_color_ansi unknown bg
    [ "$status" -eq 0 ]
    [ "$output" = '\033[0m' ]
}
