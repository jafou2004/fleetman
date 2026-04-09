#!/usr/bin/env bats
# Unit tests for scripts/lib/templates.sh
# Migrated from tests/unit/commands/pod/env/cp.bats

load '../../test_helper/common'

setup() {
    load_common

    export SELECTED_POD="api"
    export MASTER_HOST="dev1.fleet.test"

    source "$SCRIPTS_DIR/lib/templates.sh"
}

# ── _parse_server_parts ─────────────────────────────────────────────────────────

@test "_parse_server_parts: FQDN standard → name=server num=1 suffix=rec" {
    _parse_server_parts "server1-rec.abc.example.com"
    [ "$_TP_NAME" = "server" ]
    [ "$_TP_NUM" = "1" ]
    [ "$_TP_SUFFIX" = "rec" ]
}

@test "_parse_server_parts: hostname without dash → suffix equals short name" {
    _parse_server_parts "server1.example.com"
    [ "$_TP_NUM" = "1" ]
    [ "$_TP_NAME" = "server" ]
    [ "$_TP_SUFFIX" = "server1" ]
}

@test "_parse_server_parts: hostname without digit → num empty" {
    _parse_server_parts "myserver-dev.example.com"
    [ "$_TP_NUM" = "" ]
    [ "$_TP_NAME" = "myserver" ]
    [ "$_TP_SUFFIX" = "dev" ]
}

# ── _substitute ─────────────────────────────────────────────────────────────────

@test "_substitute: {hostname} → FQDN in lowercase" {
    _parse_server_parts "Server1-REC.example.com"
    result=$(_substitute "{hostname}" "Server1-REC.example.com" "server1-rec" "prod" "api")
    [ "$result" = "server1-rec.example.com" ]
}

@test "_substitute: {HOSTNAME} → FQDN in uppercase" {
    _parse_server_parts "server1-rec.example.com"
    result=$(_substitute "{HOSTNAME}" "server1-rec.example.com" "server1-rec" "prod" "api")
    [ "$result" = "SERVER1-REC.EXAMPLE.COM" ]
}

@test "_substitute: {Hostname} → first letter uppercase, rest lowercase" {
    _parse_server_parts "server1-rec.example.com"
    result=$(_substitute "{Hostname}" "SERVER1-REC.example.com" "server1-rec" "prod" "api")
    [ "$result" = "Server1-rec.example.com" ]
}

@test "_substitute: {env}/{ENV}/{Env} correctly transformed" {
    _parse_server_parts "server1-rec.example.com"
    r1=$(_substitute "{env}" "s" "s" "prod" "api")
    r2=$(_substitute "{ENV}" "s" "s" "prod" "api")
    r3=$(_substitute "{Env}" "s" "s" "prod" "api")
    [ "$r1" = "prod" ]
    [ "$r2" = "PROD" ]
    [ "$r3" = "Prod" ]
}

@test "_substitute: {pod}/{POD}/{Pod} correctly transformed" {
    _parse_server_parts "server1-rec.example.com"
    r1=$(_substitute "{pod}" "s" "s" "dev" "my-app")
    r2=$(_substitute "{POD}" "s" "s" "dev" "my-app")
    r3=$(_substitute "{Pod}" "s" "s" "dev" "my-app")
    [ "$r1" = "my-app" ]
    [ "$r2" = "MY-APP" ]
    [ "$r3" = "My-app" ]
}

@test "_substitute: {name}/{num}/{suffix} correctly substituted" {
    _parse_server_parts "server1-rec.example.com"
    result=$(_substitute "n={name} #{num} s={suffix}" "s" "s" "dev" "api")
    [ "$result" = "n=server #1 s=rec" ]
}

@test "_substitute: variable custom depuis TEMPLATE_VARS_JSON" {
    export TEMPLATE_VARS_JSON='{"company":"ACME","region":"EU"}'
    _parse_server_parts "server1-rec.example.com"
    result=$(_substitute "[{COMPANY}] {region}" "s" "s" "dev" "api")
    [ "$result" = "[ACME] eu" ]
}

@test "_substitute: custom variable - all 3 case forms" {
    export TEMPLATE_VARS_JSON='{"region":"eu"}'
    _parse_server_parts "server1.example.com"
    r1=$(_substitute "{region}" "s" "s" "dev" "api")
    r2=$(_substitute "{REGION}" "s" "s" "dev" "api")
    r3=$(_substitute "{Region}" "s" "s" "dev" "api")
    [ "$r1" = "eu" ]
    [ "$r2" = "EU" ]
    [ "$r3" = "Eu" ]
}

@test "_substitute: template without {token} → returned as-is" {
    _parse_server_parts "server1.example.com"
    result=$(_substitute "static value" "s" "s" "dev" "api")
    [ "$result" = "static value" ]
}

@test "_substitute: unknown token → left as-is" {
    _parse_server_parts "server1.example.com"
    result=$(_substitute "{unknown_token_xyz}" "s" "s" "dev" "api")
    [ "$result" = "{unknown_token_xyz}" ]
}

@test "_substitute: template_var object → direct env match" {
    export TEMPLATE_VARS_JSON='{"region":{"*":"EU","dev":"EU-DEV"}}'
    _parse_server_parts "server1.example.com"
    result=$(_substitute "{region}" "s" "s" "dev" "api")
    [ "$result" = "eu-dev" ]
}

@test "_substitute: template_var object → fallback to *" {
    export TEMPLATE_VARS_JSON='{"region":{"*":"EU","dev":"EU-DEV"}}'
    _parse_server_parts "server1.example.com"
    result=$(_substitute "{region}" "s" "s" "prod" "api")
    [ "$result" = "eu" ]
}

@test "_substitute: template_var object without * and unknown env → token not substituted" {
    export TEMPLATE_VARS_JSON='{"region":{"dev":"EU-DEV"}}'
    _parse_server_parts "server1.example.com"
    result=$(_substitute "{region}" "s" "s" "prod" "api")
    [ "$result" = "{region}" ]
}

@test "_substitute: template_var object without * and env matches → correct value" {
    export TEMPLATE_VARS_JSON='{"region":{"dev":"EU-DEV"}}'
    _parse_server_parts "server1.example.com"
    result=$(_substitute "{region}" "s" "s" "dev" "api")
    [ "$result" = "eu-dev" ]
}

# ── _escape_for_sed ─────────────────────────────────────────────────────────────

@test "_escape_for_sed: pipe → \\|" {
    run _escape_for_sed "foo|bar"
    [ "$output" = 'foo\|bar' ]
}

@test "_escape_for_sed: ampersand → \\&" {
    run _escape_for_sed "foo&bar"
    [ "$output" = 'foo\&bar' ]
}

@test "_escape_for_sed: backslash → \\\\" {
    run _escape_for_sed 'foo\bar'
    [ "$output" = 'foo\\bar' ]
}

@test "_escape_for_sed: value without special characters → unchanged" {
    run _escape_for_sed "hello-world"
    [ "$output" = "hello-world" ]
}

# ── _get_env_for_server ─────────────────────────────────────────────────────────

@test "_get_env_for_server: dev server → 'dev'" {
    run _get_env_for_server "dev1.fleet.test"
    [ "$status" -eq 0 ]
    [ "$output" = "dev" ]
}

@test "_get_env_for_server: prod server → 'prod'" {
    run _get_env_for_server "prod1.fleet.test"
    [ "$output" = "prod" ]
}

# ── _build_sed_cmds ─────────────────────────────────────────────────────────────

@test "_build_sed_cmds: value with | → escaped as \|" {
    export TEMPLATES_JSON='{"MY_VAR":"{hostname}"}'
    _substitute() { echo "foo|bar"; }
    _build_sed_cmds "dev1.fleet.test"
    [[ "$SED_CMDS" == *'\|'* ]]
}

@test "_build_sed_cmds: value with & → escaped as \&" {
    export TEMPLATES_JSON='{"MY_VAR":"{hostname}"}'
    _substitute() { echo "foo&bar"; }
    _build_sed_cmds "dev1.fleet.test"
    [[ "$SED_CMDS" == *'\&'* ]]
}

@test "_build_sed_cmds: value with \\ → escaped as \\\\" {
    export TEMPLATES_JSON='{"MY_VAR":"{hostname}"}'
    _substitute() { printf '%s' 'foo\bar'; }
    _build_sed_cmds "dev1.fleet.test"
    [[ "$SED_CMDS" == *'\\'* ]]
}

@test "_build_sed_cmds: multiple templates → separated by ;" {
    export TEMPLATES_JSON='{"VAR1":"{hostname}","VAR2":"{env}"}'
    _substitute() { echo "value"; }
    _build_sed_cmds "dev1.fleet.test"
    [[ "$SED_CMDS" == *";"* ]]
}

@test "_build_sed_cmds: SED_CMDS reset entre deux appels" {
    export TEMPLATES_JSON='{"MY_VAR":"{hostname}"}'
    _substitute() { echo "val1"; }
    _build_sed_cmds "dev1.fleet.test"
    local first="$SED_CMDS"
    _build_sed_cmds "dev1.fleet.test"
    # Must have the same length (no accumulation)
    [ "${#SED_CMDS}" -eq "${#first}" ]
}

# ── load_pod_templates ──────────────────────────────────────────────────────────

@test "load_pod_templates: pod with env_templates → TEMPLATES_JSON non-empty" {
    load_pod_templates "api"
    [ -n "$TEMPLATES_JSON" ]
}

@test "load_pod_templates: pod with env_templates → TEMPLATES_JSON is valid JSON" {
    load_pod_templates "api"
    run jq '.' <<< "$TEMPLATES_JSON"
    [ "$status" -eq 0 ]
}

@test "load_pod_templates: pod without env_templates → TEMPLATES_JSON empty" {
    local tmp
    tmp=$(mktemp)
    jq '.pods.api = {"env_vars": []}' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
    load_pod_templates "api"
    [ -z "$TEMPLATES_JSON" ]
}

@test "load_pod_templates: template_vars present → TEMPLATE_VARS_JSON non-empty" {
    local tmp
    tmp=$(mktemp)
    jq '.template_vars = {"COMPANY": "ACME"}' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
    load_pod_templates "api"
    [ -n "$TEMPLATE_VARS_JSON" ]
}

@test "load_pod_templates: template_vars absent → TEMPLATE_VARS_JSON empty" {
    local tmp
    tmp=$(mktemp)
    jq 'del(.template_vars)' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
    load_pod_templates "api"
    [ -z "$TEMPLATE_VARS_JSON" ]
}
