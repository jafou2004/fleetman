#!/usr/bin/env bats
# Unit tests for scripts/lib/auth.sh

load '../../test_helper/common'

setup() {
    # Directory of mocked binaries at the head of PATH
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    load_common
}

# ── require_cmd ────────────────────────────────────────────────────────────────

@test "require_cmd: command present → return 0" {
    run require_cmd bash
    [ "$status" -eq 0 ]
}

@test "require_cmd: command absent → exit 1 with error message" {
    run require_cmd __cmd_that_does_not_exist__
    [ "$status" -eq 1 ]
    [[ "$output" == *"✗"* ]]
    [[ "$output" == *"__cmd_that_does_not_exist__"* ]]
}

# ── check_sshpass ──────────────────────────────────────────────────────────────

@test "check_sshpass: fleet_key present → return 0 without checking sshpass" {
    touch "$HOME/.ssh/fleet_key"
    FLEET_KEY="$HOME/.ssh/fleet_key"
    run check_sshpass
    [ "$status" -eq 0 ]
}

@test "check_sshpass: no key, sshpass present → return 0" {
    rm -f "$HOME/.ssh/fleet_key"
    # Create a fake sshpass in the mocked PATH
    printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/sshpass"
    chmod +x "$BATS_TEST_TMPDIR/bin/sshpass"
    FLEET_KEY="$HOME/.ssh/fleet_key"
    run check_sshpass
    [ "$status" -eq 0 ]
}

@test "check_sshpass: no key, sshpass absent → exit 1" {
    rm -f "$HOME/.ssh/fleet_key"
    rm -f "$BATS_TEST_TMPDIR/bin/sshpass"
    FLEET_KEY="$HOME/.ssh/fleet_key"
    run check_sshpass
    [ "$status" -eq 1 ]
}

# ── ask_password ───────────────────────────────────────────────────────────────

@test "ask_password: key + passfile present → decrypts, sets PASSWORD and B64_PASS" {
    touch "$HOME/.ssh/fleet_key"
    touch "$HOME/.fleet_pass.enc"
    FLEET_KEY="$HOME/.ssh/fleet_key"
    FLEET_PASS_FILE="$HOME/.fleet_pass.enc"

    # Mock openssl: prints the password to stdout (ask_password captures stdout, not -out)
    cat > "$BATS_TEST_TMPDIR/bin/openssl" << 'EOF'
#!/bin/bash
# ask_password fait: PASSWORD=$(openssl pkeyutl -decrypt ...) — capture stdout
printf 'testpassword'
exit 0
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/openssl"

    ask_password
    [ "$PASSWORD" = "testpassword" ]
    [ -n "$B64_PASS" ]
}

@test "ask_password: openssl fails → warn and fallback" {
    touch "$HOME/.ssh/fleet_key"
    touch "$HOME/.fleet_pass.enc"
    FLEET_KEY="$HOME/.ssh/fleet_key"
    FLEET_PASS_FILE="$HOME/.fleet_pass.enc"

    # Mock openssl that fails (produces no output)
    printf '#!/bin/bash\nexit 1\n' > "$BATS_TEST_TMPDIR/bin/openssl"
    chmod +x "$BATS_TEST_TMPDIR/bin/openssl"

    # Provide a password via stdin for the fallback read
    PASSWORD=""
    run bash -c "
        source '$SCRIPTS_DIR/lib/vars.sh'
        source '$SCRIPTS_DIR/lib/display.sh'
        source '$SCRIPTS_DIR/lib/auth.sh'
        export HOME='$HOME'
        export FLEET_KEY='$HOME/.ssh/fleet_key'
        export FLEET_PASS_FILE='$HOME/.fleet_pass.enc'
        export PATH='$BATS_TEST_TMPDIR/bin:\$PATH'
        ask_password <<< 'mypassword'
        echo \"PWD:\$PASSWORD\"
    "
    [[ "$output" == *"PWD:mypassword"* ]]
}

@test "ask_password: no key → interactive prompt" {
    rm -f "$HOME/.ssh/fleet_key"
    FLEET_KEY="$HOME/.ssh/fleet_key"
    FLEET_PASS_FILE="$HOME/.fleet_pass.enc"

    run bash -c "
        source '$SCRIPTS_DIR/lib/vars.sh'
        source '$SCRIPTS_DIR/lib/display.sh'
        source '$SCRIPTS_DIR/lib/auth.sh'
        export HOME='$HOME'
        export FLEET_KEY='$HOME/.ssh/fleet_key'
        ask_password <<< 'promptpass'
        echo \"PWD:\$PASSWORD\"
    "
    [[ "$output" == *"PWD:promptpass"* ]]
}

# ── ssh_cmd ────────────────────────────────────────────────────────────────────

@test "ssh_cmd: fleet_key present → uses ssh -i FLEET_KEY" {
    touch "$HOME/.ssh/fleet_key"
    FLEET_KEY="$HOME/.ssh/fleet_key"

    # Mock ssh to capture arguments
    cat > "$BATS_TEST_TMPDIR/bin/ssh" << 'EOF'
#!/bin/bash
echo "SSH_ARGS:$*"
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/ssh"

    run ssh_cmd user@host "echo hello"
    [ "$status" -eq 0 ]
    [[ "$output" == *"-i"* ]]
    [[ "$output" == *"$HOME/.ssh/fleet_key"* ]]
}

@test "ssh_cmd: no key → uses sshpass" {
    rm -f "$HOME/.ssh/fleet_key"
    FLEET_KEY="$HOME/.ssh/fleet_key"
    PASSWORD="secret"

    cat > "$BATS_TEST_TMPDIR/bin/sshpass" << 'EOF'
#!/bin/bash
echo "SSHPASS_ARGS:$*"
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/sshpass"

    run ssh_cmd user@host "echo hello"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SSHPASS_ARGS"* ]]
    [[ "$output" == *"-p"* ]]
}

# ── scp_cmd ────────────────────────────────────────────────────────────────────

@test "scp_cmd: fleet_key present → uses scp -i FLEET_KEY" {
    touch "$HOME/.ssh/fleet_key"
    FLEET_KEY="$HOME/.ssh/fleet_key"

    cat > "$BATS_TEST_TMPDIR/bin/scp" << 'EOF'
#!/bin/bash
echo "SCP_ARGS:$*"
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/scp"

    run scp_cmd /local/file user@host:/remote/
    [ "$status" -eq 0 ]
    [[ "$output" == *"-i"* ]]
    [[ "$output" == *"$HOME/.ssh/fleet_key"* ]]
}

@test "scp_cmd: no key → uses sshpass" {
    rm -f "$HOME/.ssh/fleet_key"
    FLEET_KEY="$HOME/.ssh/fleet_key"
    PASSWORD="secret"

    cat > "$BATS_TEST_TMPDIR/bin/sshpass" << 'EOF'
#!/bin/bash
echo "SSHPASS_SCP:$*"
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/sshpass"

    run scp_cmd /local/file user@host:/remote/
    [ "$status" -eq 0 ]
    [[ "$output" == *"SSHPASS_SCP"* ]]
}

# ── rsync_cmd ──────────────────────────────────────────────────────────────────

@test "rsync_cmd: fleet_key present → uses -e with ssh -i FLEET_KEY" {
    touch "$HOME/.ssh/fleet_key"
    FLEET_KEY="$HOME/.ssh/fleet_key"

    cat > "$BATS_TEST_TMPDIR/bin/rsync" << 'EOF'
#!/bin/bash
echo "RSYNC_ARGS:$*"
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/rsync"

    run rsync_cmd /local/ user@host:/remote/
    [ "$status" -eq 0 ]
    [[ "$output" == *"-e"* ]]
    [[ "$output" == *"$HOME/.ssh/fleet_key"* ]]
}

@test "rsync_cmd: no key → -e contains sshpass" {
    rm -f "$HOME/.ssh/fleet_key"
    FLEET_KEY="$HOME/.ssh/fleet_key"
    PASSWORD="secret"

    cat > "$BATS_TEST_TMPDIR/bin/rsync" << 'EOF'
#!/bin/bash
echo "RSYNC_ARGS:$*"
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/rsync"

    run rsync_cmd /local/ user@host:/remote/
    [ "$status" -eq 0 ]
    [[ "$output" == *"sshpass"* ]]
    [[ "$output" == *"-p"* ]]
}

# ── sudo_run ───────────────────────────────────────────────────────────────────

@test "sudo_run: pipe PASSWORD vers sudo -S" {
    PASSWORD="mypassword"

    cat > "$BATS_TEST_TMPDIR/bin/sudo" << 'EOF'
#!/bin/bash
# Verify that -S is present and read stdin
has_S=0
for arg in "$@"; do [[ "$arg" == "-S" ]] && has_S=1; done
stdin_val=$(cat)
echo "HAS_S:$has_S STDIN:$stdin_val"
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/sudo"

    run sudo_run echo test
    [ "$status" -eq 0 ]
    [[ "$output" == *"HAS_S:1"* ]]
    [[ "$output" == *"STDIN:mypassword"* ]]
}

# ── is_local_server ────────────────────────────────────────────────────────────

@test "is_local_server: exact FQDN match → return 0" {
    MASTER_HOST="dev1.fleet.test"
    run is_local_server "dev1.fleet.test"
    [ "$status" -eq 0 ]
}

@test "is_local_server: short name match → return 0" {
    MASTER_HOST="dev1.fleet.test"
    run is_local_server "dev1.other.domain"
    [ "$status" -eq 0 ]
}

@test "is_local_server: different server → return 1" {
    MASTER_HOST="dev1.fleet.test"
    run is_local_server "dev2.fleet.test"
    [ "$status" -eq 1 ]
}

@test "is_local_server: short name differs → return 1" {
    MASTER_HOST="dev1.fleet.test"
    run is_local_server "prod1.fleet.test"
    [ "$status" -eq 1 ]
}

# ── encrypt_password ───────────────────────────────────────────────────────────

@test "encrypt_password: creates FLEET_PASS_FILE via mocked openssl" {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat > "$BATS_TEST_TMPDIR/bin/ssh-keygen" << 'EOF'
#!/bin/bash
echo "-----BEGIN PUBLIC KEY-----"
echo "FAKEPUBKEYCONTENT=="
echo "-----END PUBLIC KEY-----"
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/ssh-keygen"
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
    printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/diff"
    chmod +x "$BATS_TEST_TMPDIR/bin/diff"

    touch "$HOME/.ssh/fleet_key"
    printf 'FAKEPUBKEY\n' > "$HOME/.ssh/fleet_key.pub"
    FLEET_KEY="$HOME/.ssh/fleet_key"
    FLEET_PASS_FILE="$HOME/.fleet_pass.enc"
    RAW_PASSWORD="testpassword"
    encrypt_password
    [ -f "$FLEET_PASS_FILE" ]
}

@test "encrypt_password: exits 1 if openssl encrypt fails" {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat > "$BATS_TEST_TMPDIR/bin/ssh-keygen" << 'EOF'
#!/bin/bash
echo "-----BEGIN PUBLIC KEY-----"
echo "FAKEPUBKEYCONTENT=="
echo "-----END PUBLIC KEY-----"
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/ssh-keygen"
    cat > "$BATS_TEST_TMPDIR/bin/openssl" << 'EOF'
#!/bin/bash
if [[ "$*" == *"-encrypt"* ]]; then exit 1; fi
exit 0
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/openssl"

    touch "$HOME/.ssh/fleet_key"
    printf 'FAKEPUBKEY\n' > "$HOME/.ssh/fleet_key.pub"
    FLEET_KEY="$HOME/.ssh/fleet_key"
    FLEET_PASS_FILE="$HOME/.fleet_pass.enc"
    RAW_PASSWORD="testpassword"
    run encrypt_password
    [ "$status" -eq 1 ]
    [[ "$output" == *"Encryption failed"* ]]
}

@test "encrypt_password: exits 1 if openssl decrypt test fails" {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat > "$BATS_TEST_TMPDIR/bin/ssh-keygen" << 'EOF'
#!/bin/bash
echo "-----BEGIN PUBLIC KEY-----"
echo "FAKEPUBKEYCONTENT=="
echo "-----END PUBLIC KEY-----"
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/ssh-keygen"
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
fi
# decrypt always fails
exit 1
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/openssl"

    touch "$HOME/.ssh/fleet_key"
    printf 'FAKEPUBKEY\n' > "$HOME/.ssh/fleet_key.pub"
    FLEET_KEY="$HOME/.ssh/fleet_key"
    FLEET_PASS_FILE="$HOME/.fleet_pass.enc"
    RAW_PASSWORD="testpassword"
    run encrypt_password
    [ "$status" -eq 1 ]
    [[ "$output" == *"Decryption test failed"* ]]
}

@test "encrypt_password: exits 1 if decrypted content does not match password" {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat > "$BATS_TEST_TMPDIR/bin/ssh-keygen" << 'EOF'
#!/bin/bash
echo "-----BEGIN PUBLIC KEY-----"
echo "FAKEPUBKEYCONTENT=="
echo "-----END PUBLIC KEY-----"
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/ssh-keygen"
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
    printf 'WRONGCONTENT' > "$out_file"
    exit 0
fi
exit 0
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/openssl"

    touch "$HOME/.ssh/fleet_key"
    printf 'FAKEPUBKEY\n' > "$HOME/.ssh/fleet_key.pub"
    FLEET_KEY="$HOME/.ssh/fleet_key"
    FLEET_PASS_FILE="$HOME/.fleet_pass.enc"
    RAW_PASSWORD="testpassword"
    run encrypt_password
    [ "$status" -eq 1 ]
    [[ "$output" == *"verification failed"* ]]
}

# ── prompt_pass_and_encrypt ────────────────────────────────────────────────────

@test "prompt_pass_and_encrypt: empty password → return 1 + 'password cannot be empty'" {
    touch "$HOME/.ssh/fleet_key"
    printf 'FAKEPUBKEY\n' > "$HOME/.ssh/fleet_key.pub"
    FLEET_KEY="$HOME/.ssh/fleet_key"
    FLEET_PASS_FILE="$HOME/.fleet_pass.enc"
    run prompt_pass_and_encrypt <<< ''
    [ "$status" -ne 0 ]
    [[ "$output" == *"password cannot be empty"* ]]
}

@test "prompt_pass_and_encrypt: passwords do not match → return 1 + error message" {
    touch "$HOME/.ssh/fleet_key"
    printf 'FAKEPUBKEY\n' > "$HOME/.ssh/fleet_key.pub"
    FLEET_KEY="$HOME/.ssh/fleet_key"
    FLEET_PASS_FILE="$HOME/.fleet_pass.enc"
    run prompt_pass_and_encrypt <<< $'pass1\npass2\n'
    [ "$status" -ne 0 ]
    [[ "$output" == *"do not match"* ]]
}

@test "prompt_pass_and_encrypt: matching passwords → calls encrypt_password" {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    touch "$HOME/.ssh/fleet_key"
    printf 'FAKEPUBKEY\n' > "$HOME/.ssh/fleet_key.pub"
    FLEET_KEY="$HOME/.ssh/fleet_key"
    FLEET_PASS_FILE="$HOME/.fleet_pass.enc"
    encrypt_password() { echo "ENCRYPT_CALLED"; }
    run prompt_pass_and_encrypt <<< $'mypass\nmypass\n'
    [ "$status" -eq 0 ]
    [[ "$output" == *"ENCRYPT_CALLED"* ]]
}

@test "prompt_pass_and_encrypt: mismatch uses return 1 — caller not killed" {
    encrypt_password() { echo "ENCRYPT_CALLED"; }
    FLEET_KEY="$HOME/.ssh/fleet_key"
    FLEET_PASS_FILE="$HOME/.fleet_pass.enc"
    # Direct call without run — exit 1 tuerait bats, return 1 non
    prompt_pass_and_encrypt <<< $'pass1\npass2\n' || true
    # Si on arrive ici, return 1 a été utilisé (pas exit 1)
    true
}
