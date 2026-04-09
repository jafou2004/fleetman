#!/usr/bin/env bats
# Tests unitaires pour scripts/commands/config/templatevars.sh

load '../../../test_helper/common'

setup() {
    load_common
    source "$SCRIPTS_DIR/commands/config/templatevars.sh"
    select_menu() { SELECTED_IDX=0; }
    prompt_sync_confirm() { :; }
}

# ── Invalid options ───────────────────────────────────────────────────────────

@test "cmd_config_templatevars: unknown option → exit 1 + 'Unknown option'" {
    run cmd_config_templatevars -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

# ── check_config_file ──────────────────────────────────────────────────────────

@test "cmd_config_templatevars: config.json absent → exit 1 + warning" {
    rm -f "$CONFIG_FILE"
    # Actions when empty: Add(0) Quit(1) — pick Quit to avoid stdin hang
    select_menu() { SELECTED_IDX=1; }
    run cmd_config_templatevars
    [ "$status" -eq 1 ]
    [[ "$output" == *"⚠"* ]]
}

# ── Display ───────────────────────────────────────────────────────────────────

@test "cmd_config_templatevars: vars present → displays company and region" {
    # Actions with vars + scoped: Add(0) Edit(1) Remove(2) DelOverride(3) Quit(4)
    select_menu() { SELECTED_IDX=4; }
    run cmd_config_templatevars
    [ "$status" -eq 0 ]
    [[ "$output" == *"company"* ]]
    [[ "$output" == *"region"* ]]
}

@test "cmd_config_templatevars: template_vars absent → displays 'No variable'" {
    jq 'del(.template_vars)' "$CONFIG_FILE" > "$BATS_TEST_TMPDIR/tmp.json" \
        && mv "$BATS_TEST_TMPDIR/tmp.json" "$CONFIG_FILE"
    # Actions when empty: Add(0) Quit(1)
    select_menu() { SELECTED_IDX=1; }
    run cmd_config_templatevars
    [ "$status" -eq 0 ]
    [[ "$output" == *"No variable"* ]]
}

@test "cmd_config_templatevars: simple var displayed with its lowercase value" {
    select_menu() { SELECTED_IDX=4; }
    run cmd_config_templatevars
    [ "$status" -eq 0 ]
    [[ "$output" == *'company = "acme"'* ]]
}

@test "cmd_config_templatevars: scoped var displayed with env overrides" {
    select_menu() { SELECTED_IDX=4; }
    run cmd_config_templatevars
    [ "$status" -eq 0 ]
    [[ "$output" == *'* → "eu"'* ]]
    [[ "$output" == *'dev → "eu-dev"'* ]]
}

# ── Add — simple variable ─────────────────────────────────────────────────────

@test "cmd_config_templatevars: add simple variable → config.json updated" {
    # Actions: Add(0) — pick 0, then stdin: name, value, N (no override)
    select_menu() { SELECTED_IDX=0; }
    run cmd_config_templatevars <<< $'newvar\nmyvalue\nN'
    [ "$status" -eq 0 ]
    [[ "$output" == *"added"* ]]
    [ "$(jq -r '.template_vars.newvar' "$CONFIG_FILE")" = "myvalue" ]
}

@test "cmd_config_templatevars: add simple variable → prompt_sync_confirm called" {
    local sync_file="$BATS_TEST_TMPDIR/sync_calls"
    prompt_sync_confirm() { echo "SYNC" >> "$sync_file"; }
    select_menu() { SELECTED_IDX=0; }
    run cmd_config_templatevars <<< $'newvar\nmyvalue\nN'
    [ "$status" -eq 0 ]
    [ -f "$sync_file" ]
}

@test "cmd_config_templatevars: add without template_vars in config → creates the section" {
    jq 'del(.template_vars)' "$CONFIG_FILE" > "$BATS_TEST_TMPDIR/tmp.json" \
        && mv "$BATS_TEST_TMPDIR/tmp.json" "$CONFIG_FILE"
    # Actions when empty: Add(0)
    select_menu() { SELECTED_IDX=0; }
    run cmd_config_templatevars <<< $'firstvar\nfirstval\nN'
    [ "$status" -eq 0 ]
    [ "$(jq -r '.template_vars.firstvar' "$CONFIG_FILE")" = "firstval" ]
}

# ── Add — duplicate ───────────────────────────────────────────────────────────

@test "cmd_config_templatevars: duplicate → warn + config unchanged" {
    local before
    before=$(jq -c '.template_vars' "$CONFIG_FILE")
    select_menu() { SELECTED_IDX=0; }
    run cmd_config_templatevars <<< $'company\nmyvalue\nN'
    [ "$status" -eq 0 ]
    [[ "$output" == *"already defined"* ]]
    [ "$(jq -c '.template_vars' "$CONFIG_FILE")" = "$before" ]
}

@test "cmd_config_templatevars: duplicate → prompt_sync_confirm not called" {
    local sync_file="$BATS_TEST_TMPDIR/sync_calls"
    prompt_sync_confirm() { echo "SYNC" >> "$sync_file"; }
    select_menu() { SELECTED_IDX=0; }
    run cmd_config_templatevars <<< $'company\nmyvalue\nN'
    [ "$status" -eq 0 ]
    [ ! -f "$sync_file" ]
}

# ── Add — scoped variable ─────────────────────────────────────────────────────

@test "cmd_config_templatevars: add scoped variable → object structure in config.json" {
    # select_menu call 1: action Add(0)
    # select_menu call 2: env selection → dev(0)
    # stdin: name, fallback, y (add override), dev value, N (no more)
    local _call=0
    select_menu() {
        _call=$(( _call + 1 ))
        if [ "$_call" -eq 1 ]; then SELECTED_IDX=0; else SELECTED_IDX=0; fi
    }
    run cmd_config_templatevars <<< $'scopedvar\nfallback\ny\ndevvalue\nN'
    [ "$status" -eq 0 ]
    [ "$(jq -r '.template_vars.scopedvar["*"]' "$CONFIG_FILE")" = "fallback" ]
    [ "$(jq -r '.template_vars.scopedvar.dev' "$CONFIG_FILE")" = "devvalue" ]
    [ "$(jq -r '.template_vars.scopedvar | type' "$CONFIG_FILE")" = "object" ]
}

@test "cmd_config_templatevars: add scoped with 2 overrides → both present" {

    # select_menu call 1: Add(0)
    # select_menu call 2: env dev(0)
    # select_menu call 3: env prod(1)
    # stdin: name, *, y, devval, y, prodval, N
    local _call=0
    select_menu() {
        _call=$(( _call + 1 ))
        case "$_call" in
            1) SELECTED_IDX=0 ;;   # action Add
            2) SELECTED_IDX=0 ;;   # env dev
            3) SELECTED_IDX=1 ;;   # env prod
        esac
    }
    run cmd_config_templatevars <<< $'multivar\nallenv\ny\nfordev\ny\nforprod\nN'
    [ "$status" -eq 0 ]
    [ "$(jq -r '.template_vars.multivar["*"]' "$CONFIG_FILE")" = "allenv" ]
    [ "$(jq -r '.template_vars.multivar.dev' "$CONFIG_FILE")" = "fordev" ]
    [ "$(jq -r '.template_vars.multivar.prod' "$CONFIG_FILE")" = "forprod" ]
}

# ── Remove variable ───────────────────────────────────────────────────────────

@test "cmd_config_templatevars: confirmed variable removal → absent from config.json" {
    # select_menu call 1: action Remove(2)
    # select_menu call 2: var company(0)
    # stdin: y (confirmation)
    local _call=0
    select_menu() {
        _call=$(( _call + 1 ))
        if [ "$_call" -eq 1 ]; then SELECTED_IDX=2; else SELECTED_IDX=0; fi
    }
    run cmd_config_templatevars <<< 'y'
    [ "$status" -eq 0 ]
    [[ "$output" == *"removed"* ]]
    [ "$(jq '.template_vars | has("company")' "$CONFIG_FILE")" = "false" ]
}

@test "cmd_config_templatevars: cancelled removal → config unchanged" {
    local before
    before=$(jq -c '.template_vars' "$CONFIG_FILE")
    local _call=0
    select_menu() {
        _call=$(( _call + 1 ))
        if [ "$_call" -eq 1 ]; then SELECTED_IDX=2; else SELECTED_IDX=0; fi
    }
    run cmd_config_templatevars <<< 'N'
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cancelled"* ]]
    [ "$(jq -c '.template_vars' "$CONFIG_FILE")" = "$before" ]
}

@test "cmd_config_templatevars: removal → prompt_sync_confirm called" {
    local sync_file="$BATS_TEST_TMPDIR/sync_calls"
    prompt_sync_confirm() { echo "SYNC" >> "$sync_file"; }
    local _call=0
    select_menu() {
        _call=$(( _call + 1 ))
        if [ "$_call" -eq 1 ]; then SELECTED_IDX=2; else SELECTED_IDX=0; fi
    }
    run cmd_config_templatevars <<< 'y'
    [ "$status" -eq 0 ]
    [ -f "$sync_file" ]
}

@test "cmd_config_templatevars: cancelled removal → prompt_sync_confirm not called" {
    local sync_file="$BATS_TEST_TMPDIR/sync_calls"
    prompt_sync_confirm() { echo "SYNC" >> "$sync_file"; }
    local _call=0
    select_menu() {
        _call=$(( _call + 1 ))
        if [ "$_call" -eq 1 ]; then SELECTED_IDX=2; else SELECTED_IDX=0; fi
    }
    run cmd_config_templatevars <<< 'N'
    [ "$status" -eq 0 ]
    [ ! -f "$sync_file" ]
}

# ── Remove env override ───────────────────────────────────────────────────────

@test "cmd_config_templatevars: override removal → env key removed" {
    # select_menu call 1: action Remove env override(3)
    # select_menu call 2: var region(0) — only scoped var
    # select_menu call 3: env key dev(0) — only non-* key
    # stdin: y (confirmation)
    local _call=0
    select_menu() {
        _call=$(( _call + 1 ))
        case "$_call" in
            1) SELECTED_IDX=3 ;;
            2) SELECTED_IDX=0 ;;
            3) SELECTED_IDX=0 ;;
        esac
    }
    run cmd_config_templatevars <<< 'y'
    [ "$status" -eq 0 ]
    [[ "$output" == *"Override removed"* ]]
}

@test "cmd_config_templatevars: only * remains → converted to simple value" {
    # region has * + dev; deleting dev leaves only * → simple string "EU"
    local _call=0
    select_menu() {
        _call=$(( _call + 1 ))
        case "$_call" in
            1) SELECTED_IDX=3 ;;
            2) SELECTED_IDX=0 ;;
            3) SELECTED_IDX=0 ;;
        esac
    }
    run cmd_config_templatevars <<< 'y'
    [ "$status" -eq 0 ]
    [ "$(jq -r '.template_vars.region | type' "$CONFIG_FILE")" = "string" ]
    [ "$(jq -r '.template_vars.region' "$CONFIG_FILE")" = "EU" ]
}

@test "cmd_config_templatevars: override removal with other envs → object preserved" {
    # Add a second env override so after deleting dev, test still remains
    jq '.template_vars.region.test = "EU-TEST"' "$CONFIG_FILE" \
        > "$BATS_TEST_TMPDIR/tmp.json" && mv "$BATS_TEST_TMPDIR/tmp.json" "$CONFIG_FILE"
    # region non-* keys sorted: dev(0), test(1)
    local _call=0
    select_menu() {
        _call=$(( _call + 1 ))
        case "$_call" in
            1) SELECTED_IDX=3 ;;
            2) SELECTED_IDX=0 ;;
            3) SELECTED_IDX=0 ;;  # dev (alphabetically first)
        esac
    }
    run cmd_config_templatevars <<< 'y'
    [ "$status" -eq 0 ]
    [ "$(jq -r '.template_vars.region | type' "$CONFIG_FILE")" = "object" ]
    [ "$(jq '.template_vars.region | has("dev")' "$CONFIG_FILE")" = "false" ]
    [ "$(jq '.template_vars.region | has("test")' "$CONFIG_FILE")" = "true" ]
}

@test "cmd_config_templatevars: cancelled override removal → config unchanged" {
    local before
    before=$(jq -c '.template_vars' "$CONFIG_FILE")
    local _call=0
    select_menu() {
        _call=$(( _call + 1 ))
        case "$_call" in
            1) SELECTED_IDX=3 ;;
            2) SELECTED_IDX=0 ;;
            3) SELECTED_IDX=0 ;;
        esac
    }
    run cmd_config_templatevars <<< 'N'
    [ "$status" -eq 0 ]
    [ "$(jq -c '.template_vars' "$CONFIG_FILE")" = "$before" ]
}

@test "cmd_config_templatevars: override removal → prompt_sync_confirm called" {
    local sync_file="$BATS_TEST_TMPDIR/sync_calls"
    prompt_sync_confirm() { echo "SYNC" >> "$sync_file"; }
    local _call=0
    select_menu() {
        _call=$(( _call + 1 ))
        case "$_call" in
            1) SELECTED_IDX=3 ;;
            2) SELECTED_IDX=0 ;;
            3) SELECTED_IDX=0 ;;
        esac
    }
    run cmd_config_templatevars <<< 'y'
    [ "$status" -eq 0 ]
    [ -f "$sync_file" ]
}

# ── Edit simple variable ──────────────────────────────────────────────────────

@test "cmd_config_templatevars: edit simple var → config.json updated" {
    # select_menu call 1: action Edit(1)
    # select_menu call 2: var company(0)
    # stdin: new value, N (no scope conversion)
    local _call=0
    select_menu() {
        _call=$(( _call + 1 ))
        if [ "$_call" -eq 1 ]; then SELECTED_IDX=1; else SELECTED_IDX=0; fi
    }
    run cmd_config_templatevars <<< $'NEWACME\nN'
    [ "$status" -eq 0 ]
    [ "$(jq -r '.template_vars.company' "$CONFIG_FILE")" = "NEWACME" ]
}

@test "cmd_config_templatevars: edit simple var with scoped conversion" {
    # select_menu call 1: Edit(1)
    # select_menu call 2: company(0)
    # stdin: new value, y (add scopes), y (add override)
    # select_menu call 3: env dev(0)
    # stdin: dev value, N (no more)
    local _call=0
    select_menu() {
        _call=$(( _call + 1 ))
        case "$_call" in
            1) SELECTED_IDX=1 ;;  # Edit
            2) SELECTED_IDX=0 ;;  # company
            3) SELECTED_IDX=0 ;;  # dev
        esac
    }
    run cmd_config_templatevars <<< $'NEWACME\ny\ny\nACME-DEV\nN'
    [ "$status" -eq 0 ]
    [ "$(jq -r '.template_vars.company["*"]' "$CONFIG_FILE")" = "NEWACME" ]
    [ "$(jq -r '.template_vars.company.dev' "$CONFIG_FILE")" = "ACME-DEV" ]
}

@test "cmd_config_templatevars: edit simple var → prompt_sync_confirm called" {
    local sync_file="$BATS_TEST_TMPDIR/sync_calls"
    prompt_sync_confirm() { echo "SYNC" >> "$sync_file"; }
    local _call=0
    select_menu() {
        _call=$(( _call + 1 ))
        if [ "$_call" -eq 1 ]; then SELECTED_IDX=1; else SELECTED_IDX=0; fi
    }
    run cmd_config_templatevars <<< $'NEWACME\nN'
    [ "$status" -eq 0 ]
    [ -f "$sync_file" ]
}

# ── Edit scoped variable ──────────────────────────────────────────────────────

@test "cmd_config_templatevars: edit env override in scoped var → updated" {
    # select_menu call 1: Edit(1)
    # select_menu call 2: region(1) — alphabetical after company
    # select_menu call 3: key dev(1) in region — keys: *(0), dev(1)
    # stdin: new value, N (no additional override)
    local _call=0
    select_menu() {
        _call=$(( _call + 1 ))
        case "$_call" in
            1) SELECTED_IDX=1 ;;  # Edit
            2) SELECTED_IDX=1 ;;  # region
            3) SELECTED_IDX=1 ;;  # dev (idx 1, after *)
        esac
    }
    run cmd_config_templatevars <<< $'NEWDEVVAL\nN'
    [ "$status" -eq 0 ]
    [ "$(jq -r '.template_vars.region.dev' "$CONFIG_FILE")" = "NEWDEVVAL" ]
}

@test "cmd_config_templatevars: edit scoped with adding new override" {

    # select_menu call 1: Edit(1)
    # select_menu call 2: region(1)
    # select_menu call 3: *(0) — edit * value
    # stdin: new * value, y (add new override)
    # select_menu call 4: env test(2) — envs: dev(0), prod(1), test(2)
    # stdin: test value
    local _call=0
    select_menu() {
        _call=$(( _call + 1 ))
        case "$_call" in
            1) SELECTED_IDX=1 ;;  # Edit
            2) SELECTED_IDX=1 ;;  # region
            3) SELECTED_IDX=0 ;;  # * (idx 0)
            4) SELECTED_IDX=2 ;;  # test (idx 2 among dev/prod/test)
        esac
    }
    run cmd_config_templatevars <<< $'NEWEU\ny\nEU-TEST'
    [ "$status" -eq 0 ]
    [ "$(jq -r '.template_vars.region["*"]' "$CONFIG_FILE")" = "NEWEU" ]
    [ "$(jq -r '.template_vars.region.test' "$CONFIG_FILE")" = "EU-TEST" ]
}

# ── Quit / sync ───────────────────────────────────────────────────────────────

@test "cmd_config_templatevars: Quit → exit 0 + prompt_sync_confirm not called" {
    local sync_file="$BATS_TEST_TMPDIR/sync_calls"
    prompt_sync_confirm() { echo "SYNC" >> "$sync_file"; }
    # Actions with vars+scoped: Add(0) Edit(1) Remove(2) DelOverride(3) Quit(4)
    select_menu() { SELECTED_IDX=4; }
    run cmd_config_templatevars
    [ "$status" -eq 0 ]
    [ ! -f "$sync_file" ]
}
