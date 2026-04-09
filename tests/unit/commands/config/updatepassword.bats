#!/usr/bin/env bats
# Unit tests for scripts/commands/config/updatepassword.sh

load '../../../test_helper/common'

setup() {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"

    # Mock ssh-keygen: print fake public key on stdout
    cat > "$BATS_TEST_TMPDIR/bin/ssh-keygen" << 'EOF'
#!/bin/bash
echo "-----BEGIN PUBLIC KEY-----"
echo "FAKEPUBKEYCONTENT=="
echo "-----END PUBLIC KEY-----"
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/ssh-keygen"

    # Mock openssl: encrypt writes to -out, decrypt writes testpassword to -out
    cat > "$BATS_TEST_TMPDIR/bin/openssl" << 'EOF'
#!/bin/bash
out_file=""
mode=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -encrypt) mode="encrypt"; shift ;;
        -decrypt) mode="decrypt"; shift ;;
        -out) out_file="$2"; shift 2 ;;
        *) shift ;;
    esac
done
if [[ "$mode" == "encrypt" && -n "$out_file" ]]; then
    printf 'ENCRYPTED' > "$out_file"
    exit 0
elif [[ "$mode" == "decrypt" && -n "$out_file" ]]; then
    printf 'testpassword' > "$out_file"
    exit 0
fi
exit 0
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/openssl"

    # Mock diff: always succeeds (simulates password match in encrypt_password)
    printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/diff"
    chmod +x "$BATS_TEST_TMPDIR/bin/diff"

    load_common
    source "$SCRIPTS_DIR/commands/config/updatepassword.sh"

    # Default: sync is a no-op
    bash() {
        if [[ "$*" == *"sync"* ]]; then return 0; fi
        command bash "$@"
    }
}

# ── config.json absent ────────────────────────────────────────────────────────

@test "cmd_config_updatepassword: config.json absent → exit 1 + ⚠" {
    rm -f "$CONFIG_FILE"
    run cmd_config_updatepassword
    [ "$status" -eq 1 ]
    [[ "$output" == *"⚠"* ]]
}

# ── Missing fleet key ─────────────────────────────────────────────────────────

@test "cmd_config_updatepassword: FLEET_KEY missing → exit 1 + 'Fleet key not found'" {
    rm -f "$FLEET_KEY"
    touch "$FLEET_PASS_FILE"
    run cmd_config_updatepassword
    [ "$status" -eq 1 ]
    [[ "$output" == *"Fleet key not found"* ]]
}

# ── Missing fleet pass file ───────────────────────────────────────────────────

@test "cmd_config_updatepassword: FLEET_PASS_FILE missing → exit 1 + 'Fleet password file not found'" {
    touch "$FLEET_KEY"
    rm -f "$FLEET_PASS_FILE"
    run cmd_config_updatepassword
    [ "$status" -eq 1 ]
    [[ "$output" == *"Fleet password file not found"* ]]
}

# ── Password mismatch ─────────────────────────────────────────────────────────

@test "cmd_config_updatepassword: passwords do not match → exit 1 + 'Passwords do not match'" {
    touch "$FLEET_KEY"
    touch "$FLEET_PASS_FILE"
    printf 'FAKEPUBKEY\n' > "${FLEET_KEY}.pub"
    printf 'newpass\ndifferent\n' > "$BATS_TEST_TMPDIR/input.txt"
    run cmd_config_updatepassword < "$BATS_TEST_TMPDIR/input.txt"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Passwords do not match"* ]]
}

# ── Success path ──────────────────────────────────────────────────────────────

@test "cmd_config_updatepassword: matching passwords → encrypt_password called, ok message shown" {
    touch "$FLEET_KEY"
    touch "$FLEET_PASS_FILE"
    printf 'FAKEPUBKEY\n' > "${FLEET_KEY}.pub"
    encrypt_password() { echo "ENCRYPT_CALLED"; }
    printf 'testpassword\ntestpassword\n' > "$BATS_TEST_TMPDIR/input.txt"
    run cmd_config_updatepassword < "$BATS_TEST_TMPDIR/input.txt"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ENCRYPT_CALLED"* ]]
    [[ "$output" == *"Password updated"* ]]
}

@test "cmd_config_updatepassword: success → triggers fleetman sync -q" {
    touch "$FLEET_KEY"
    touch "$FLEET_PASS_FILE"
    printf 'FAKEPUBKEY\n' > "${FLEET_KEY}.pub"
    encrypt_password() { :; }
    local sync_file="$BATS_TEST_TMPDIR/sync_called"
    bash() {
        if [[ "$*" == *"sync"* ]]; then
            touch "$sync_file"
            return 0
        fi
        command bash "$@"
    }
    printf 'testpassword\ntestpassword\n' > "$BATS_TEST_TMPDIR/input.txt"
    run cmd_config_updatepassword < "$BATS_TEST_TMPDIR/input.txt"
    [ "$status" -eq 0 ]
    [ -f "$sync_file" ]
}
