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

# ── Unknown option ─────────────────────────────────────────────────────────────

@test "cmd_config_server_add: unknown option → exit 1 + 'Unknown option'" {
    run cmd_config_server_add -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

# ── Display of existing servers ───────────────────────────────────────────────

@test "cmd_config_server_add: lists existing servers before input" {
    _deploy_key() { :; }
    SCRIPTS_DIR="$BATS_TEST_TMPDIR"
    run cmd_config_server_add < <(printf 'server1-staging.abc.example.com\n\n')
    [[ "$output" == *"dev1.fleet.test"* ]]
    [[ "$output" == *"test1.fleet.test"* ]]
    [[ "$output" == *"prod1.fleet.test"* ]]
}

# ── Empty input immediately ───────────────────────────────────────────────────

@test "cmd_config_server_add: empty input immediately → warn + exit 0" {
    run cmd_config_server_add < <(printf '\n')
    [ "$status" -eq 0 ]
    [[ "$output" == *"⚠"* ]]
}

# ── FQDN validation ───────────────────────────────────────────────────────────

@test "cmd_config_server_add: invalid then valid FQDN → warn + success" {
    _deploy_key() { :; }
    SCRIPTS_DIR="$BATS_TEST_TMPDIR"
    run cmd_config_server_add < <(printf 'bad fqdn\nserver1-staging.abc.example.com\n\n')
    [ "$status" -eq 0 ]
    [[ "$output" == *"⚠"* ]]
    [[ "$output" == *"added"* ]]
}

@test "cmd_config_server_add: FQDN without dot → invalid → warn" {
    _deploy_key() { :; }
    SCRIPTS_DIR="$BATS_TEST_TMPDIR"
    run cmd_config_server_add < <(printf 'nopoint\nserver1-staging.abc.example.com\n\n')
    [ "$status" -eq 0 ]
    [[ "$output" == *"⚠"* ]]
    [[ "$output" == *"added"* ]]
}

# ── Duplicate check ───────────────────────────────────────────────────────────

@test "cmd_config_server_add: server already present → warn + re-prompt" {
    _deploy_key() { :; }
    SCRIPTS_DIR="$BATS_TEST_TMPDIR"
    run cmd_config_server_add < <(printf 'dev1.fleet.test\nserver1-staging.abc.example.com\n\n')
    [ "$status" -eq 0 ]
    [[ "$output" == *"⚠"* ]]
    [[ "$output" == *"added"* ]]
}

@test "cmd_config_server_add: server from another env already present → warn" {
    _deploy_key() { :; }
    SCRIPTS_DIR="$BATS_TEST_TMPDIR"
    run cmd_config_server_add < <(printf 'prod1.fleet.test\nserver1-staging.abc.example.com\n\n')
    [ "$status" -eq 0 ]
    [[ "$output" == *"⚠"* ]]
    [[ "$output" == *"added"* ]]
}

# ── Successful addition ───────────────────────────────────────────────────────

@test "cmd_config_server_add: successful addition → .servers updated in config.json" {
    _deploy_key() { :; }
    SCRIPTS_DIR="$BATS_TEST_TMPDIR"
    run cmd_config_server_add < <(printf 'server1-staging.abc.example.com\n\n')
    [ "$status" -eq 0 ]
    local result
    result=$(jq -r '.servers.dev[]' "$CONFIG_FILE")
    [[ "$result" == *"server1-staging.abc.example.com"* ]]
}

@test "cmd_config_server_add: successful addition → displays ok with FQDN and env" {
    _deploy_key() { :; }
    SCRIPTS_DIR="$BATS_TEST_TMPDIR"
    run cmd_config_server_add < <(printf 'server1-staging.abc.example.com\n\n')
    [ "$status" -eq 0 ]
    [[ "$output" == *"✓"* ]]
    [[ "$output" == *"server1-staging.abc.example.com"* ]]
    [[ "$output" == *"dev"* ]]
}

@test "cmd_config_server_add: FQDN normalized to lowercase" {
    _deploy_key() { :; }
    SCRIPTS_DIR="$BATS_TEST_TMPDIR"
    run cmd_config_server_add < <(printf 'Server1-Staging.ABC.EXAMPLE.COM\n\n')
    [ "$status" -eq 0 ]
    local result
    result=$(jq -r '.servers.dev[]' "$CONFIG_FILE")
    [[ "$result" == *"server1-staging.abc.example.com"* ]]
}

# ── Multi-server collection ───────────────────────────────────────────────────

@test "cmd_config_server_add: multiple servers → _deploy_key called for each" {
    local call_file="$BATS_TEST_TMPDIR/deploy_calls"
    _deploy_key() { echo "DEPLOY:$1" >> "$call_file"; }
    SCRIPTS_DIR="$BATS_TEST_TMPDIR"
    run cmd_config_server_add < <(printf 's1.abc.example.com\ns2.abc.example.com\n\n')
    [ "$status" -eq 0 ]
    [ -f "$call_file" ]
    grep -q "DEPLOY:s1.abc.example.com" "$call_file"
    grep -q "DEPLOY:s2.abc.example.com" "$call_file"
}

@test "cmd_config_server_add: multiple servers → both added to config.json" {
    _deploy_key() { :; }
    SCRIPTS_DIR="$BATS_TEST_TMPDIR"
    run cmd_config_server_add < <(printf 's1.abc.example.com\ns2.abc.example.com\n\n')
    [ "$status" -eq 0 ]
    local result
    result=$(jq -r '.servers.dev[]' "$CONFIG_FILE")
    [[ "$result" == *"s1.abc.example.com"* ]]
    [[ "$result" == *"s2.abc.example.com"* ]]
}

@test "cmd_config_server_add: multiple servers → sync called once" {
    local call_file="$BATS_TEST_TMPDIR/sync_calls"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    printf '#!/bin/bash\necho "SYNC" >> "%s"\n' "$call_file" \
        > "$BATS_TEST_TMPDIR/bin/fleetman"
    chmod +x "$BATS_TEST_TMPDIR/bin/fleetman"
    SCRIPTS_DIR="$BATS_TEST_TMPDIR"
    _deploy_key() { :; }
    run cmd_config_server_add < <(printf 's1.abc.example.com\ns2.abc.example.com\n\n')
    [ "$status" -eq 0 ]
    [ -f "$call_file" ]
    [ "$(wc -l < "$call_file")" -eq 1 ]
}

# ── _deploy_key ────────────────────────────────────────────────────────────────

@test "_deploy_key: fleet_key absent → exit 1 + 'run install.sh first'" {
    rm -f "$FLEET_KEY"
    touch "$HOME/.fleet_pass.enc"
    export FLEET_PASS_FILE="$HOME/.fleet_pass.enc"
    run _deploy_key "server1.fleet.test"
    [ "$status" -eq 1 ]
    [[ "$output" == *"install.sh"* ]]
}

@test "_deploy_key: fleet_pass.enc absent → exit 1 + 'run install.sh first'" {
    touch "$FLEET_KEY"
    rm -f "$HOME/.fleet_pass.enc"
    export FLEET_PASS_FILE="$HOME/.fleet_pass.enc"
    run _deploy_key "server1.fleet.test"
    [ "$status" -eq 1 ]
    [[ "$output" == *"install.sh"* ]]
}

@test "_deploy_key: ssh-copy-id fails → return 1 + err" {
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
    run _deploy_key "server1.fleet.test"
    [ "$status" -ne 0 ]
    [[ "$output" == *"✗"* ]]
}

@test "_deploy_key: key auth verification fails → return 1 + err" {
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
    run _deploy_key "server1.fleet.test"
    [ "$status" -ne 0 ]
    [[ "$output" == *"✗"* ]]
}

@test "_deploy_key: success → ok messages, no sync" {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    export FLEET_KEY="$HOME/.ssh/fleet_key"
    export FLEET_PASS_FILE="$HOME/.fleet_pass.enc"
    touch "$FLEET_KEY" "$FLEET_PASS_FILE"
    printf 'ssh-rsa AAAAFAKEKEY fleet-key\n' > "${FLEET_KEY}.pub"
    printf '#!/bin/bash\nprintf "testpassword"\n' > "$BATS_TEST_TMPDIR/bin/openssl"
    chmod +x "$BATS_TEST_TMPDIR/bin/openssl"
    printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/sshpass"
    chmod +x "$BATS_TEST_TMPDIR/bin/sshpass"
    printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/ssh"
    chmod +x "$BATS_TEST_TMPDIR/bin/ssh"
    run _deploy_key "server1.fleet.test"
    [ "$status" -eq 0 ]
    [[ "$output" == *"✓"* ]]
    [[ "$output" != *"sync"* ]]
}
