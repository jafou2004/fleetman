#!/usr/bin/env bats
# Tests unitaires pour scripts/commands/config/server/add.sh

load '../../../../test_helper/common'

setup() {
    load_common
    source "$SCRIPTS_DIR/commands/config/server/add.sh"
    # select_menu requires a TTY — mock: selects index 0 (dev, alphabetically).
    select_menu() { SELECTED_IDX=0; }
}

# ── check_config_file ──────────────────────────────────────────────────────────

@test "cmd_config_server_add: config.json absent → exit 1 + ⚠" {
    rm -f "$CONFIG_FILE"
    run cmd_config_server_add
    [ "$status" -eq 1 ]
    [[ "$output" == *"⚠"* ]]
}

# ── Option inconnue ────────────────────────────────────────────────────────────

@test "cmd_config_server_add: unknown option → exit 1 + 'Unknown option'" {
    run cmd_config_server_add -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

# ── Display of existing servers ───────────────────────────────────────────────

@test "cmd_config_server_add: lists existing servers before input" {
    _bootstrap_key() { :; }
    run cmd_config_server_add < <(printf 'server1-staging.abc.example.com\n')
    [[ "$output" == *"dev1.fleet.test"* ]]
    [[ "$output" == *"test1.fleet.test"* ]]
    [[ "$output" == *"prod1.fleet.test"* ]]
}

# ── FQDN validation ───────────────────────────────────────────────────────────

@test "cmd_config_server_add: invalid then valid FQDN → warn + success" {
    # 'bad fqdn' → warn + re-prompt (space not allowed)
    # 'server1-staging.abc.example.com' → valid, not duplicate → break
    _bootstrap_key() { :; }
    run cmd_config_server_add < <(printf 'bad fqdn\nserver1-staging.abc.example.com\n')
    [ "$status" -eq 0 ]
    [[ "$output" == *"⚠"* ]]
    [[ "$output" == *"added"* ]]
}

@test "cmd_config_server_add: FQDN without dot → invalid → warn" {
    # 'nopoint' → invalid (at least one dot required)
    # then valid FQDN → add
    _bootstrap_key() { :; }
    run cmd_config_server_add < <(printf 'nopoint\nserver1-staging.abc.example.com\n')
    [ "$status" -eq 0 ]
    [[ "$output" == *"⚠"* ]]
    [[ "$output" == *"added"* ]]
}

# ── Duplicate check ───────────────────────────────────────────────────────────

@test "cmd_config_server_add: server already present → warn + re-prompt" {
    # 'dev1.fleet.test' exists in fixture (env dev) → warn
    # 'server1-staging.abc.example.com' → new → break
    _bootstrap_key() { :; }
    run cmd_config_server_add < <(printf 'dev1.fleet.test\nserver1-staging.abc.example.com\n')
    [ "$status" -eq 0 ]
    [[ "$output" == *"⚠"* ]]
    [[ "$output" == *"added"* ]]
}

@test "cmd_config_server_add: server from another env already present → warn" {
    # 'prod1.fleet.test' is in env prod (not dev) → global duplicate → warn
    _bootstrap_key() { :; }
    run cmd_config_server_add < <(printf 'prod1.fleet.test\nserver1-staging.abc.example.com\n')
    [ "$status" -eq 0 ]
    [[ "$output" == *"⚠"* ]]
    [[ "$output" == *"added"* ]]
}

# ── Successful addition ───────────────────────────────────────────────────────

@test "cmd_config_server_add: successful addition → .servers updated in config.json" {
    # SELECTED_IDX=0 → dev (alphabetical: dev=0, prod=1, test=2)
    _bootstrap_key() { :; }
    run cmd_config_server_add < <(printf 'server1-staging.abc.example.com\n')
    [ "$status" -eq 0 ]
    local result
    result=$(jq -r '.servers.dev[]' "$CONFIG_FILE")
    [[ "$result" == *"server1-staging.abc.example.com"* ]]
}

@test "cmd_config_server_add: successful addition → displays ok with FQDN and env" {
    _bootstrap_key() { :; }
    run cmd_config_server_add < <(printf 'server1-staging.abc.example.com\n')
    [ "$status" -eq 0 ]
    [[ "$output" == *"✓"* ]]
    [[ "$output" == *"server1-staging.abc.example.com"* ]]
    [[ "$output" == *"dev"* ]]
}

@test "cmd_config_server_add: FQDN normalized to lowercase" {
    _bootstrap_key() { :; }
    run cmd_config_server_add < <(printf 'Server1-Staging.ABC.EXAMPLE.COM\n')
    [ "$status" -eq 0 ]
    local result
    result=$(jq -r '.servers.dev[]' "$CONFIG_FILE")
    [[ "$result" == *"server1-staging.abc.example.com"* ]]
}

@test "cmd_config_server_add: bootstrap always called after successful addition" {
    local call_file="$BATS_TEST_TMPDIR/bootstrap_calls"
    _bootstrap_key() { echo "BOOTSTRAP:$1" >> "$call_file"; }
    run cmd_config_server_add < <(printf 'server1-staging.abc.example.com\n')
    [ "$status" -eq 0 ]
    [ -f "$call_file" ]
    grep -q "BOOTSTRAP:server1-staging.abc.example.com" "$call_file"
}

# ── _bootstrap_key ────────────────────────────────────────────────────────────

@test "_bootstrap_key: fleet_key absent → exit 1 + 'run install.sh first'" {
    rm -f "$FLEET_KEY"
    touch "$HOME/.fleet_pass.enc"
    export FLEET_PASS_FILE="$HOME/.fleet_pass.enc"
    run _bootstrap_key "server1.fleet.test"
    [ "$status" -eq 1 ]
    [[ "$output" == *"install.sh"* ]]
}

@test "_bootstrap_key: fleet_pass.enc absent → exit 1 + 'run install.sh first'" {
    touch "$FLEET_KEY"
    rm -f "$HOME/.fleet_pass.enc"
    export FLEET_PASS_FILE="$HOME/.fleet_pass.enc"
    run _bootstrap_key "server1.fleet.test"
    [ "$status" -eq 1 ]
    [[ "$output" == *"install.sh"* ]]
}

@test "_bootstrap_key: ssh-copy-id fails → return 1 + err" {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    touch "$FLEET_KEY"
    touch "$HOME/.fleet_pass.enc"
    export FLEET_PASS_FILE="$HOME/.fleet_pass.enc"
    printf 'ssh-rsa AAAAFAKEKEY fleet-key\n' > "${FLEET_KEY}.pub"
    printf '#!/bin/bash\nprintf "testpassword"\n' > "$BATS_TEST_TMPDIR/bin/openssl"
    chmod +x "$BATS_TEST_TMPDIR/bin/openssl"
    printf '#!/bin/bash\nexit 1\n' > "$BATS_TEST_TMPDIR/bin/sshpass"
    chmod +x "$BATS_TEST_TMPDIR/bin/sshpass"
    run _bootstrap_key "server1.fleet.test"
    [ "$status" -ne 0 ]
    [[ "$output" == *"✗"* ]]
}

@test "_bootstrap_key: key auth verification fails → return 1 + err" {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    touch "$FLEET_KEY"
    touch "$HOME/.fleet_pass.enc"
    export FLEET_PASS_FILE="$HOME/.fleet_pass.enc"
    printf 'ssh-rsa AAAAFAKEKEY fleet-key\n' > "${FLEET_KEY}.pub"
    printf '#!/bin/bash\nprintf "testpassword"\n' > "$BATS_TEST_TMPDIR/bin/openssl"
    chmod +x "$BATS_TEST_TMPDIR/bin/openssl"
    printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/sshpass"
    chmod +x "$BATS_TEST_TMPDIR/bin/sshpass"
    printf '#!/bin/bash\nexit 1\n' > "$BATS_TEST_TMPDIR/bin/ssh"
    chmod +x "$BATS_TEST_TMPDIR/bin/ssh"
    run _bootstrap_key "server1.fleet.test"
    [ "$status" -ne 0 ]
    [[ "$output" == *"✗"* ]]
}

@test "_bootstrap_key: success → ok message + sync launched" {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    touch "$FLEET_KEY"
    touch "$HOME/.fleet_pass.enc"
    export FLEET_KEY="$HOME/.ssh/fleet_key"
    export FLEET_PASS_FILE="$HOME/.fleet_pass.enc"
    printf 'ssh-rsa AAAAFAKEKEY fleet-key\n' > "${FLEET_KEY}.pub"
    local call_file="$BATS_TEST_TMPDIR/bash_calls"
    printf '#!/bin/bash\nprintf "testpassword"\n' > "$BATS_TEST_TMPDIR/bin/openssl"
    chmod +x "$BATS_TEST_TMPDIR/bin/openssl"
    printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/sshpass"
    chmod +x "$BATS_TEST_TMPDIR/bin/sshpass"
    printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/ssh"
    chmod +x "$BATS_TEST_TMPDIR/bin/ssh"
    bash() { echo "BASH_CALLED:$*" >> "$call_file"; }
    export -f bash
    run _bootstrap_key "server1.fleet.test"
    unset -f bash
    [ "$status" -eq 0 ]
    [[ "$output" == *"✓"* ]]
    [ -f "$call_file" ]
    grep -q "sync" "$call_file"
}
