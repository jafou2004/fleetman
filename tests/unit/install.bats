#!/usr/bin/env bats
# Unit tests for install.sh

load '../test_helper/common'

setup() {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin" "$HOME/.ssh"

    # Mock ssh-keygen: creates simulated key files
    cat > "$BATS_TEST_TMPDIR/bin/ssh-keygen" << 'EOF'
#!/bin/bash
# Parse args and create fake key files
out_file=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -f) out_file="$2"; shift 2 ;;
        -e) # Export to PEM → write to stdout
            echo "-----BEGIN PUBLIC KEY-----"
            echo "FAKEPUBKEYCONTENT=="
            echo "-----END PUBLIC KEY-----"
            exit 0 ;;
        -p) # Format conversion → success
            exit 0 ;;
        *) shift ;;
    esac
done
if [[ -n "$out_file" ]]; then
    echo "-----BEGIN RSA PRIVATE KEY-----" > "$out_file"
    echo "FAKEPRIVKEY==" >> "$out_file"
    echo "-----END RSA PRIVATE KEY-----" >> "$out_file"
    echo "FAKEPUBKEY==" > "${out_file}.pub"
fi
exit 0
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/ssh-keygen"

    # Mock openssl: encrypt → writes to -out, decrypt → writes fixed password
    cat > "$BATS_TEST_TMPDIR/bin/openssl" << 'EOF'
#!/bin/bash
mode=""
out_file=""
in_file=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        pkeyutl) shift ;;
        -encrypt) mode="encrypt"; shift ;;
        -decrypt) mode="decrypt"; shift ;;
        -out) out_file="$2"; shift 2 ;;
        -in)  in_file="$2";  shift 2 ;;
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

    # Mock diff: always success (encryption verification)
    printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/diff"
    chmod +x "$BATS_TEST_TMPDIR/bin/diff"

    # Mock crontab: -l → display stored content, - → store stdin
    cat > "$BATS_TEST_TMPDIR/bin/crontab" << EOF
#!/bin/bash
CRONTAB_FILE="$BATS_TEST_TMPDIR/crontab_store"
if [[ "\$1" == "-l" ]]; then
    [ -f "\$CRONTAB_FILE" ] && cat "\$CRONTAB_FILE" || true
elif [[ "\$1" == "-" ]]; then
    cat > "\$CRONTAB_FILE"
fi
exit 0
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/crontab"

    # Mock sshpass
    printf '#!/bin/bash\necho "SSHPASS:$*"\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/sshpass"
    chmod +x "$BATS_TEST_TMPDIR/bin/sshpass"

    load_common
    # Source install.sh (the bootstrap guard [[ ! -f "$0" ]] is safe from bats since $0=/usr/bin/bats)
    source "$PROJECT_ROOT/install.sh"
    # Disable spinner and iterate after sourcing
    _spin_start() { :; }
    _spin_stop()  { :; }
}

# ── _wizard_create_config ──────────────────────────────────────────────────────
# Uses fd 9 pattern to inject inputs into interactive reads

@test "_wizard_create_config: creates config.json from wizard inputs" {
    rm -f "$CONFIG_FILE"
    # Override prompt_response to read from fd 9
    exec 9< <(printf '/opt/pods\n\n4\n\n0\n\ndev test\ndev1.fleet.test\n\ntest1.fleet.test\n\n')
    prompt_response() {
        local response=""
        while [[ -z "$response" ]]; do
            read -r response <&9
            [[ -z "$response" && -n "${2:-}" ]] && response="$2"
        done
        printf '%s' "$response"
    }
    read() {
        local opts=() varname=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -r|-s|-rs|-sr) shift ;;
                -p) shift 2 ;;
                -ra|-n|-ra) shift 2 ;;
                *) varname="$1"; shift ;;
            esac
        done
        IFS= command read -r "$varname" <&9 || true
    }
    select_menu() { SELECTED_IDX=0; }

    _wizard_create_config <&9
    exec 9<&-

    [ -f "$CONFIG_FILE" ]
    run jq -e '.servers' "$CONFIG_FILE"
    [ "$status" -eq 0 ]
}

@test "_wizard_create_config: status_checks contains wud_port if > 0" {
    rm -f "$CONFIG_FILE"
    exec 9< <(printf '/opt/pods\n\n4\n\n3000\n\ndev\ndev1.fleet.test\n\n')
    prompt_response() {
        local response=""
        while [[ -z "$response" ]]; do
            read -r response <&9
            [[ -z "$response" && -n "${2:-}" ]] && response="$2"
        done
        printf '%s' "$response"
    }
    read() {
        local varname=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -r|-s|-rs|-sr) shift ;;
                -p) shift 2 ;;
                -ra|-n) shift 2 ;;
                *) varname="$1"; shift ;;
            esac
        done
        IFS= command read -r "$varname" <&9 || true
    }
    select_menu() { SELECTED_IDX=0; }
    _wizard_create_config <&9
    exec 9<&-

    run jq -e '.status_checks.wud_port' "$CONFIG_FILE"
    [ "$status" -eq 0 ]
    [ "$output" -eq 3000 ]
}

@test "_wizard_create_config: status_checks.containers non-empty if containers provided" {
    rm -f "$CONFIG_FILE"
    exec 9< <(printf '/opt/pods\n\n4\nweb app\n0\n\ndev\ndev1.fleet.test\n\n')
    prompt_response() {
        local response=""
        while [[ -z "$response" ]]; do
            read -r response <&9
            [[ -z "$response" && -n "${2:-}" ]] && response="$2"
        done
        printf '%s' "$response"
    }
    read() {
        local varname=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -r|-s|-rs|-sr) shift ;;
                -p) shift 2 ;;
                -ra|-n) shift 2 ;;
                *) varname="$1"; shift ;;
            esac
        done
        IFS= command read -r "$varname" <&9 || true
    }
    select_menu() { SELECTED_IDX=0; }
    _wizard_create_config <&9
    exec 9<&-

    run jq -e '.status_checks.containers | length > 0' "$CONFIG_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == "true" ]]
}

@test "_wizard_create_config: re-prompts parallel if value is invalid" {
    rm -f "$CONFIG_FILE"
    # "abc" → invalid → retry → "2" → valid
    exec 9< <(printf '/opt/pods\n\nabc\n2\n\n0\n\ndev\n\n')
    prompt_response() {
        local response=""
        while [[ -z "$response" ]]; do
            read -r response <&9
            [[ -z "$response" && -n "${2:-}" ]] && response="$2"
        done
        printf '%s' "$response"
    }
    read() {
        local varname=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -r|-s|-rs|-sr) shift ;;
                -p) shift 2 ;;
                -ra|-n) shift 2 ;;
                *) varname="$1"; shift ;;
            esac
        done
        IFS= command read -r "$varname" <&9 || true
    }
    select_menu() { SELECTED_IDX=0; }
    run _wizard_create_config <&9
    exec 9<&-

    [[ "$output" == *"Must be a positive integer"* ]]
    run jq -r '.parallel' "$CONFIG_FILE"
    [ "$status" -eq 0 ]
    [ "$output" -eq 2 ]
}

@test "_wizard_create_config: re-prompts wud_port if value is invalid" {
    rm -f "$CONFIG_FILE"
    # wud_port="abc" → invalid → retry → "0" → valid
    exec 9< <(printf '/opt/pods\n\n4\n\nabc\n0\n\ndev\n\n')
    prompt_response() {
        local response=""
        while [[ -z "$response" ]]; do
            read -r response <&9
            [[ -z "$response" && -n "${2:-}" ]] && response="$2"
        done
        printf '%s' "$response"
    }
    read() {
        local varname=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -r|-s|-rs|-sr) shift ;;
                -p) shift 2 ;;
                -ra|-n) shift 2 ;;
                *) varname="$1"; shift ;;
            esac
        done
        IFS= command read -r "$varname" <&9 || true
    }
    select_menu() { SELECTED_IDX=0; }
    run _wizard_create_config <&9
    exec 9<&-

    [[ "$output" == *"Must be a non-negative integer"* ]]
    run jq -e '.status_checks' "$CONFIG_FILE"
    [ "$status" -eq 0 ]
}

@test "_wizard_create_config: created config contains required keys" {
    rm -f "$CONFIG_FILE"
    exec 9< <(printf '/opt/pods\n\n4\n\n0\n\ndev\ndev1.fleet.test\n\n')
    prompt_response() {
        local response=""
        while [[ -z "$response" ]]; do
            read -r response <&9
            [[ -z "$response" && -n "${2:-}" ]] && response="$2"
        done
        printf '%s' "$response"
    }
    select_menu() { SELECTED_IDX=0; }
    _wizard_create_config <&9
    exec 9<&-

    run jq -e '.parallel' "$CONFIG_FILE"
    [ "$status" -eq 0 ]
    run jq -e '.pods_dir' "$CONFIG_FILE"
    [ "$status" -eq 0 ]
    run jq -e '.pods' "$CONFIG_FILE"
    [ "$status" -eq 0 ]
}

@test "_wizard_create_config: welcome.enabled=false when response is 'n'" {
    rm -f "$CONFIG_FILE"
    exec 9< <(printf '/opt/pods\n\n4\n\n0\nn\ndev\ndev1.fleet.test\n\n')
    prompt_response() {
        local response=""
        while [[ -z "$response" ]]; do
            read -r response <&9
            [[ -z "$response" && -n "${2:-}" ]] && response="$2"
        done
        printf '%s' "$response"
    }
    read() {
        local varname=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -r|-s|-rs|-sr) shift ;;
                -p) shift 2 ;;
                -ra|-n) shift 2 ;;
                *) varname="$1"; shift ;;
            esac
        done
        IFS= command read -r "$varname" <&9 || true
    }
    select_menu() { SELECTED_IDX=0; }
    _wizard_create_config <&9
    exec 9<&-

    run jq -e '.welcome.enabled == false' "$CONFIG_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == "true" ]]
}

@test "_wizard_create_config: welcome.enabled=true when response is 'Y' (default)" {
    rm -f "$CONFIG_FILE"
    exec 9< <(printf '/opt/pods\n\n4\n\n0\n\ndev\ndev1.fleet.test\n\n')
    prompt_response() {
        local response=""
        while [[ -z "$response" ]]; do
            read -r response <&9
            [[ -z "$response" && -n "${2:-}" ]] && response="$2"
        done
        printf '%s' "$response"
    }
    read() {
        local varname=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -r|-s|-rs|-sr) shift ;;
                -p) shift 2 ;;
                -ra|-n) shift 2 ;;
                *) varname="$1"; shift ;;
            esac
        done
        IFS= command read -r "$varname" <&9 || true
    }
    select_menu() { SELECTED_IDX=0; }
    _wizard_create_config <&9
    exec 9<&-

    run jq -e '.welcome.enabled == true' "$CONFIG_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == "true" ]]
}

@test "_wizard_create_config: base_folder entered → included in config.json" {
    rm -f "$CONFIG_FILE"
    exec 9< <(printf "/opt/pods\n$BATS_TEST_TMPDIR\n4\n\n0\n\ndev\ndev1.fleet.test\n\n")
    prompt_response() {
        local response=""
        while [[ -z "$response" ]]; do
            read -r response <&9
            [[ -z "$response" && -n "${2:-}" ]] && response="$2"
        done
        printf '%s' "$response"
    }
    read() {
        local varname=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -r|-s|-rs|-sr) shift ;;
                -p) shift 2 ;;
                -ra|-n) shift 2 ;;
                *) varname="$1"; shift ;;
            esac
        done
        IFS= command read -r "$varname" <&9 || true
    }
    select_menu() { SELECTED_IDX=0; }
    _wizard_create_config <&9
    exec 9<&-

    run jq -r '.base_folder' "$CONFIG_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "$BATS_TEST_TMPDIR" ]
}

@test "_wizard_create_config: base_folder empty (Enter) → absent from config.json" {
    rm -f "$CONFIG_FILE"
    exec 9< <(printf '/opt/pods\n\n4\n\n0\n\ndev\ndev1.fleet.test\n\n')
    prompt_response() {
        local response=""
        while [[ -z "$response" ]]; do
            read -r response <&9
            [[ -z "$response" && -n "${2:-}" ]] && response="$2"
        done
        printf '%s' "$response"
    }
    read() {
        local varname=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -r|-s|-rs|-sr) shift ;;
                -p) shift 2 ;;
                -ra|-n) shift 2 ;;
                *) varname="$1"; shift ;;
            esac
        done
        IFS= command read -r "$varname" <&9 || true
    }
    select_menu() { SELECTED_IDX=0; }
    _wizard_create_config <&9
    exec 9<&-

    run jq 'has("base_folder")' "$CONFIG_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "false" ]
}

@test "_wizard_create_config: re-prompts base_folder if directory does not exist" {
    rm -f "$CONFIG_FILE"
    exec 9< <(printf "/opt/pods\n/nonexistent_xyz_12345\n$BATS_TEST_TMPDIR\n4\n\n0\n\ndev\ndev1.fleet.test\n\n")
    prompt_response() {
        local response=""
        while [[ -z "$response" ]]; do
            read -r response <&9
            [[ -z "$response" && -n "${2:-}" ]] && response="$2"
        done
        printf '%s' "$response"
    }
    read() {
        local varname=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -r|-s|-rs|-sr) shift ;;
                -p) shift 2 ;;
                -ra|-n) shift 2 ;;
                *) varname="$1"; shift ;;
            esac
        done
        IFS= command read -r "$varname" <&9 || true
    }
    select_menu() { SELECTED_IDX=0; }
    run _wizard_create_config <&9
    exec 9<&-

    [[ "$output" == *"does not exist"* ]]
    run jq -r '.base_folder' "$CONFIG_FILE"
    [ "$output" = "$BATS_TEST_TMPDIR" ]
}

# ── Key generation ─────────────────────────────────────────────────────────────

@test "main (step 1): generates ~/.ssh/fleet_key if absent" {
    rm -f "$FLEET_KEY" "${FLEET_KEY}.pub"
    cp "$FIXTURES_DIR/config.json" "$CONFIG_FILE"

    # Bypass all interactive steps
    _wizard_create_config() { :; }
    check_config_file()  { :; }
    _write_repo_url()    { :; }
    require_cmd()        { :; }
    deploy_local()       { ok "local configured"; echo ""; }
    deploy_remote()      { ok "remote configured"; echo ""; }
    _run_sync()          { :; }
    _ask_sync_cron()     { :; }
    iterate_servers()    { deploy_local; }
    prompt_pass_and_encrypt() { RAW_PASSWORD="testpass"; return 0; }

    # stdin: 'y' for re-run guard
    run main <<< $'y\n'
    [ -f "$HOME/.ssh/fleet_key" ]
}

# ── Crontab sync ───────────────────────────────────────────────────────────────

@test "_ask_sync_cron: adds cron if accepted (response 'y')" {
    rm -f "$BATS_TEST_TMPDIR/crontab_store"
    run _ask_sync_cron <<< 'y'
    [ "$status" -eq 0 ]
    grep -q "bin/fleetman sync" "$BATS_TEST_TMPDIR/crontab_store"
}

@test "_ask_sync_cron: idempotent — does not duplicate the cron entry" {
    # Pre-fill crontab with the line
    echo "0 1 * * * mv ~/.data/autosync.log ~/.data/autosync.log.1 2>/dev/null; bash ~/scripts/bin/fleetman sync > ~/.data/autosync.log 2>&1" \
        > "$BATS_TEST_TMPDIR/crontab_store"

    run _ask_sync_cron <<< 'y'
    [ "$status" -eq 0 ]
    local count
    count=$(grep -c "bin/fleetman sync" "$BATS_TEST_TMPDIR/crontab_store")
    [ "$count" -eq 1 ]
    [[ "$output" == *"already"* ]] || [[ "$output" == *"✓"* ]]
}

@test "_ask_sync_cron: does not touch crontab if declined (response 'n')" {
    rm -f "$BATS_TEST_TMPDIR/crontab_store"
    run _ask_sync_cron <<< 'n'
    [ "$status" -eq 0 ]
    [ ! -f "$BATS_TEST_TMPDIR/crontab_store" ] || \
        ! grep -q "bin/fleetman sync" "$BATS_TEST_TMPDIR/crontab_store"
    [[ "$output" == *"Skipped"* ]]
}

@test "_ask_sync_cron: installs cron if response is empty (default Y)" {
    rm -f "$BATS_TEST_TMPDIR/crontab_store"
    run _ask_sync_cron <<< ''
    [ "$status" -eq 0 ]
    grep -q "bin/fleetman sync" "$BATS_TEST_TMPDIR/crontab_store"
}

# ── help ───────────────────────────────────────────────────────────────────────

@test "help: displays the Usage line" {
    run help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

# ── _run_sync ──────────────────────────────────────────────────────────────────

@test "_run_sync: bin/fleetman present → bash called with sync" {
    bash() { echo "BASH_CALLED:$1:$2"; }
    export -f bash
    run _run_sync
    unset -f bash
    [ "$status" -eq 0 ]
    [[ "$output" == *"BASH_CALLED:"*"bin/fleetman"*":sync"* ]]
}

@test "_run_sync: bin/fleetman absent → warn" {
    dirname() { echo "$BATS_TEST_TMPDIR/nonexistent"; }
    export -f dirname
    run _run_sync
    unset -f dirname
    [ "$status" -eq 0 ]
    [[ "$output" == *"⚠"* ]]
    [[ "$output" == *"manually"* ]]
}

# ── deploy_remote ──────────────────────────────────────────────────────────────

@test "deploy_remote: deploys public key and verifies auth" {
    touch "$FLEET_KEY"
    printf 'ssh-rsa AAAAFAKEKEY fleet-key\n' > "${FLEET_KEY}.pub"

    # Mock sshpass: success
    printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/sshpass"
    chmod +x "$BATS_TEST_TMPDIR/bin/sshpass"
    # Mock ssh: success (auth verification)
    printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/ssh"
    chmod +x "$BATS_TEST_TMPDIR/bin/ssh"

    PASSWORD="testpassword"
    run deploy_remote "server1.fleet.test"
    [ "$status" -eq 0 ]
    [[ "$output" == *"✓"* ]]
}

@test "deploy_remote: fails if ssh-copy-id fails" {
    touch "$FLEET_KEY"
    printf 'ssh-rsa AAAAFAKEKEY fleet-key\n' > "${FLEET_KEY}.pub"

    # Mock sshpass: failure
    printf '#!/bin/bash\nexit 1\n' > "$BATS_TEST_TMPDIR/bin/sshpass"
    chmod +x "$BATS_TEST_TMPDIR/bin/sshpass"

    PASSWORD="testpassword"
    run deploy_remote "server1.fleet.test"
    [ "$status" -ne 0 ]
    [[ "$output" == *"✗"* ]]
}

@test "deploy_remote: fails if key auth verification fails" {
    touch "$FLEET_KEY"
    printf 'ssh-rsa AAAAFAKEKEY fleet-key\n' > "${FLEET_KEY}.pub"

    # Mock sshpass: success
    printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/sshpass"
    chmod +x "$BATS_TEST_TMPDIR/bin/sshpass"
    # Mock ssh: failure (auth verification)
    printf '#!/bin/bash\nexit 1\n' > "$BATS_TEST_TMPDIR/bin/ssh"
    chmod +x "$BATS_TEST_TMPDIR/bin/ssh"

    PASSWORD="testpassword"
    run deploy_remote "server1.fleet.test"
    [ "$status" -ne 0 ]
    [[ "$output" == *"✗"* ]]
}

# ── deploy_local ───────────────────────────────────────────────────────────────

@test "deploy_local: adds public key to authorized_keys" {
    touch "$FLEET_KEY"
    printf 'ssh-rsa AAAAFAKEKEY fleet-key\n' > "${FLEET_KEY}.pub"
    mkdir -p "$HOME/.ssh"
    touch "$HOME/.ssh/authorized_keys"

    deploy_local
    grep -q "AAAAFAKEKEY" "$HOME/.ssh/authorized_keys"
}

@test "deploy_local: idempotent — does not duplicate public key" {
    touch "$FLEET_KEY"
    printf 'ssh-rsa AAAAFAKEKEY fleet-key\n' > "${FLEET_KEY}.pub"
    mkdir -p "$HOME/.ssh"
    printf 'ssh-rsa AAAAFAKEKEY fleet-key\n' > "$HOME/.ssh/authorized_keys"

    deploy_local
    local count
    count=$(grep -c "AAAAFAKEKEY" "$HOME/.ssh/authorized_keys")
    [ "$count" -eq 1 ]
}

# ── Bootstrap ──────────────────────────────────────────────────────────────────
# The bootstrap block triggers when $0 is not a file (bash reads from
# a pipe). Tested via: bash -c "cat install.sh | bash"
# Tests target early outputs (before the final exec).

@test "bootstrap: fails if a dependency is missing" {
    # Hide sshpass (last in the list) — other dependencies are
    # available via the system or setup() mocks
    mv "$BATS_TEST_TMPDIR/bin/sshpass" "$BATS_TEST_TMPDIR/bin/sshpass.bak"
    run bash -c "cat '$PROJECT_ROOT/install.sh' | bash"
    mv "$BATS_TEST_TMPDIR/bin/sshpass.bak" "$BATS_TEST_TMPDIR/bin/sshpass"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Missing requirement"*"sshpass"* ]]
}

@test "bootstrap: fails if ~/scripts is a real directory" {
    local real_install_sh="$PROJECT_ROOT/install.sh"

    # Simulate an already-cloned repo (to pass the git check)
    export FLEETMAN_DIR="$BATS_TEST_TMPDIR/fleetman"
    mkdir -p "$FLEETMAN_DIR/.git"
    # load_common already created $HOME/scripts as a symlink — replace it with a real directory
    rm -f "$HOME/scripts"
    mkdir "$HOME/scripts"
    run bash -c "cat '$real_install_sh' | bash"
    [ "$status" -ne 0 ]
    [[ "$output" == *"real directory"* ]]
}

# ── _write_repo_url ────────────────────────────────────────────────────────────

@test "_write_repo_url: clone present with remote → repo_url written to config.json" {
    local pdir="$BATS_TEST_TMPDIR/fleetman"
    mkdir -p "$pdir/.git"
    cat > "$BATS_TEST_TMPDIR/bin/git" << 'EOF'
#!/bin/bash
if [[ "$1" == "-C" && "$3" == "remote" && "$4" == "get-url" ]]; then
    echo "https://github.com/example/fleetman.git"
fi
exit 0
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/git"
    jq 'del(.repo_url)' "$CONFIG_FILE" > "$BATS_TEST_TMPDIR/t.json" && mv "$BATS_TEST_TMPDIR/t.json" "$CONFIG_FILE"
    export FLEETMAN_DIR="$pdir"

    _write_repo_url
    [ "$(jq -r '.repo_url' "$CONFIG_FILE")" = "https://github.com/example/fleetman.git" ]
}

@test "_write_repo_url: clone absent → config.json unchanged, no error" {
    export FLEETMAN_DIR="$BATS_TEST_TMPDIR/no-clone-here"
    local before
    before=$(jq -r '.repo_url // ""' "$CONFIG_FILE")

    _write_repo_url
    local after
    after=$(jq -r '.repo_url // ""' "$CONFIG_FILE")
    [ "$before" = "$after" ]
}

@test "_write_repo_url: repo_url already present and non-empty → no-op, value preserved" {
    jq '.repo_url = "https://already-set.example.com/repo.git"' "$CONFIG_FILE" \
        > "$BATS_TEST_TMPDIR/t.json" && mv "$BATS_TEST_TMPDIR/t.json" "$CONFIG_FILE"
    local pdir="$BATS_TEST_TMPDIR/fleetman"
    mkdir -p "$pdir/.git"
    export FLEETMAN_DIR="$pdir"

    _write_repo_url
    [ "$(jq -r '.repo_url' "$CONFIG_FILE")" = "https://already-set.example.com/repo.git" ]
}

@test "_write_repo_url: git remote get-url fails → config.json unchanged, no blocking error" {
    local pdir="$BATS_TEST_TMPDIR/fleetman"
    mkdir -p "$pdir/.git"
    printf '#!/bin/bash\nexit 1\n' > "$BATS_TEST_TMPDIR/bin/git"
    chmod +x "$BATS_TEST_TMPDIR/bin/git"
    export FLEETMAN_DIR="$pdir"
    local before
    before=$(jq -r '.repo_url // ""' "$CONFIG_FILE")

    _write_repo_url
    [ $? -eq 0 ]
    local after
    after=$(jq -r '.repo_url // ""' "$CONFIG_FILE")
    [ "$before" = "$after" ]
}


# ── main: -h ───────────────────────────────────────────────────────────────────

@test "main: -h prints usage and exits 0" {
    run main -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

# ── main: no config.json → calls wizard ────────────────────────────────────────

@test "main: no config.json → calls _wizard_create_config" {
    rm -f "$CONFIG_FILE"
    local wizard_called="$BATS_TEST_TMPDIR/wizard_called"
    _wizard_create_config() { cp "$FIXTURES_DIR/config.json" "$CONFIG_FILE"; touch "$wizard_called"; }
    deploy_local()    { ok "configured"; echo ""; }
    iterate_servers() { deploy_local; }
    _run_sync()       { :; }
    _ask_sync_cron()  { :; }
    prompt_pass_and_encrypt() { RAW_PASSWORD="testpass"; return 0; }

    run main
    [ -f "$wizard_called" ]
}

# ── Re-run guard ───────────────────────────────────────────────────────────────

@test "main: config.json exists + response N → exit 0, wizard not called" {
    cp "$FIXTURES_DIR/config.json" "$CONFIG_FILE"
    _wizard_create_config() { echo "WIZARD_CALLED"; }
    run main <<< 'n'
    [ "$status" -eq 0 ]
    [[ "$output" != *"WIZARD_CALLED"* ]]
    [[ "$output" == *"nothing changed"* ]] || [[ "$output" == *"Aborted"* ]]
}

@test "main: config.json exists + empty response → N by default → exit 0" {
    cp "$FIXTURES_DIR/config.json" "$CONFIG_FILE"
    _wizard_create_config() { echo "WIZARD_CALLED"; }
    run main <<< ''
    [ "$status" -eq 0 ]
    [[ "$output" != *"WIZARD_CALLED"* ]]
}

@test "main: config.json exists + response Y → wizard called" {
    cp "$FIXTURES_DIR/config.json" "$CONFIG_FILE"
    _wizard_create_config() { echo "WIZARD_CALLED"; }
    check_config_file()  { :; }
    _write_repo_url()    { :; }
    require_cmd()        { :; }
    prompt_pass_and_encrypt() { RAW_PASSWORD="testpass"; return 0; }
    deploy_local()       { ok "configured"; echo ""; }
    deploy_remote()      { ok "configured"; echo ""; }
    _run_sync()          { :; }
    _ask_sync_cron()     { :; }
    iterate_servers()    { deploy_local; }
    run main <<< 'y'
    [ "$status" -eq 0 ]
    [[ "$output" == *"WIZARD_CALLED"* ]]
}

# ── deploy_remote: no .bashrc injection ───────────────────────────────────────

@test "deploy_remote: does not attempt .bashrc injection" {
    touch "$FLEET_KEY"
    printf 'ssh-rsa AAAAFAKEKEY fleet-key\n' > "${FLEET_KEY}.pub"

    local ssh_calls="$BATS_TEST_TMPDIR/ssh_calls"
    printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/sshpass"
    chmod +x "$BATS_TEST_TMPDIR/bin/sshpass"
    cat > "$BATS_TEST_TMPDIR/bin/ssh" << ENDF
#!/bin/bash
echo "SSH:\$*" >> "$ssh_calls"
exit 0
ENDF
    chmod +x "$BATS_TEST_TMPDIR/bin/ssh"

    PASSWORD="testpassword"
    run deploy_remote "server1.fleet.test"
    [ "$status" -eq 0 ]
    # Exactly one ssh call (key auth verification), no second .bashrc call
    local count
    count=$(wc -l < "$ssh_calls")
    [ "$count" -eq 1 ]
    ! grep -q "FLEETMAN" "$ssh_calls"
}

# ── deploy_local: no bashrc/fleetman.sh side-effects ─────────────────────────

@test "deploy_local: does not add BEGIN FLEETMAN block to ~/.bashrc" {
    printf 'ssh-rsa AAAAFAKEKEY fleet-key\n' > "${FLEET_KEY}.pub"
    touch "$HOME/.bashrc"
    deploy_local
    ! grep -q '# BEGIN FLEETMAN' "$HOME/.bashrc"
}

@test "deploy_local: does not generate ~/.data/fleetman.sh" {
    printf 'ssh-rsa AAAAFAKEKEY fleet-key\n' > "${FLEET_KEY}.pub"
    rm -f "$DATA_DIR/fleetman.sh"
    deploy_local
    [ ! -f "$DATA_DIR/fleetman.sh" ]
}
