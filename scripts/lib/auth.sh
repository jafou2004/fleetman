#!/bin/bash

# Authentication and SSH helpers.
[[ -n "${_FLEETMAN_AUTH_LOADED:-}" ]] && return 0
_FLEETMAN_AUTH_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/vars.sh"
source "$(dirname "${BASH_SOURCE[0]}")/display.sh"

# Exits with an error if a required command is not available.
# Usage: require_cmd <cmd>
require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        err "Missing requirement: $cmd — install it with: sudo apt-get install $cmd"
        exit 1
    fi
}

# Returns 0 if server is the local master host, 1 otherwise.
# Compares by FQDN and by short name to handle both exact and short-name matches.
# Usage: is_local_server <server>
is_local_server() {
    local server="$1"
    [ "$server" = "$MASTER_HOST" ] || [ "$(short_name "$server")" = "$(short_name "$MASTER_HOST")" ]
}

# Runs a command with sudo, feeding the password via stdin.
# Usage: sudo_run docker compose up -d
sudo_run() {
    echo "$PASSWORD" | sudo -S "$@" 2>/dev/null
}

check_sshpass() {
    # Not needed once key-based auth is configured via install.sh
    [ -f "$FLEET_KEY" ] && return 0
    require_cmd sshpass
}

ask_password() {
    # Decrypt stored password using the fleet private key (no prompt needed)
    if [ -f "$FLEET_PASS_FILE" ] && [ -f "$FLEET_KEY" ]; then
        PASSWORD=$(openssl pkeyutl -decrypt -inkey "$FLEET_KEY" \
            -pkeyopt rsa_padding_mode:oaep -in "$FLEET_PASS_FILE" 2>/dev/null)
        if [ -n "$PASSWORD" ]; then
            B64_PASS=$(printf '%s' "$PASSWORD" | base64)
            return 0
        fi
        warn "Could not decrypt $FLEET_PASS_FILE — falling back to prompt"
    fi

    # Fallback: manual prompt
    echo -e "${YELLOW}Enter the SSH password:${NC}"
    read -rs PASSWORD
    echo ""
    if [ -z "$PASSWORD" ]; then
        err "Error: password cannot be empty"
        exit 1
    fi
    # shellcheck disable=SC2034  # used in caller scripts via source
    B64_PASS=$(printf '%s' "$PASSWORD" | base64)
}

# SSH/SCP wrappers — use fleet key if available, fall back to sshpass.
# Usage: ssh_cmd user@host bash -s << ENDSSH
#        scp_cmd src user@host:dst
ssh_cmd() {
    if [ -f "$FLEET_KEY" ]; then
        ssh -i "$FLEET_KEY" -o StrictHostKeyChecking=no "$@"
    else
        sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$@"
    fi
}

scp_cmd() {
    if [ -f "$FLEET_KEY" ]; then
        scp -i "$FLEET_KEY" -o StrictHostKeyChecking=no "$@"
    else
        sshpass -p "$PASSWORD" scp -o StrictHostKeyChecking=no "$@"
    fi
}

rsync_cmd() {
    if [ -f "$FLEET_KEY" ]; then
        rsync -e "ssh -i '$FLEET_KEY' -o StrictHostKeyChecking=no" "$@"
    else
        rsync -e "sshpass -p '$PASSWORD' ssh -o StrictHostKeyChecking=no" "$@"
    fi
}

# Encrypts $RAW_PASSWORD to $FLEET_PASS_FILE using the fleet RSA public key.
# Verifies the result by decrypting and comparing. Exits 1 on failure.
# Requires: $RAW_PASSWORD, $FLEET_KEY, $FLEET_PASS_FILE set in environment.
encrypt_password() {
    local pub_pem tmpfile
    pub_pem=$(ssh-keygen -e -f "$FLEET_KEY.pub" -m PKCS8)
    if ! printf '%s' "$RAW_PASSWORD" | openssl pkeyutl -encrypt -pubin \
            -inkey <(echo "$pub_pem") \
            -pkeyopt rsa_padding_mode:oaep \
            -out "$FLEET_PASS_FILE" 2>/dev/null; then
        err "Encryption failed — aborting"
        exit 1
    fi
    chmod 600 "$FLEET_PASS_FILE"
    # Verify by decrypting to a temp file and comparing bytes
    tmpfile=$(mktemp)
    if ! openssl pkeyutl -decrypt -inkey "$FLEET_KEY" \
            -pkeyopt rsa_padding_mode:oaep \
            -in "$FLEET_PASS_FILE" -out "$tmpfile" 2>/dev/null; then
        rm -f "$tmpfile"
        err "Decryption test failed — aborting"
        exit 1
    fi
    if ! printf '%s' "$RAW_PASSWORD" | diff - "$tmpfile" >/dev/null 2>&1; then
        rm -f "$tmpfile"
        err "Encryption verification failed — aborting"
        exit 1
    fi
    rm -f "$tmpfile"
    ok "Password encrypted and verified: $FLEET_PASS_FILE"
}

# Prompts interactively for a password (hidden input, with confirmation) then
# calls encrypt_password. Returns 1 (never exits) on empty or mismatched input,
# allowing callers to loop or exit as appropriate.
prompt_pass_and_encrypt() {
    local _pass2
    echo -e "${YELLOW}Enter the fleet SSH/sudo password to encrypt:${NC}"
    read -rs RAW_PASSWORD
    echo ""
    if [ -z "$RAW_PASSWORD" ]; then
        err "Error: password cannot be empty"
        return 1
    fi
    printf "  Confirm password: "
    read -rs _pass2
    echo ""
    if [ "$RAW_PASSWORD" != "$_pass2" ]; then
        err "Passwords do not match"
        return 1
    fi
    encrypt_password
}
