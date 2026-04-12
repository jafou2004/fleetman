#!/bin/bash

##
# Hybrid smoke test for the fleetman CLI.
# Runs safe read-only commands automatically (with timing and pass/fail),
# then prints a manual test checklist for commands that cannot be automated.
#
# Usage: bash smoketest.sh [--plan] [--env <env>] [--timeout <secs>]
#
# Options:
#   --plan             Print only the manual checklist (no tests executed)
#   --env <env>        Restrict SSH-based tests to one environment
#   --timeout <secs>   Per-command timeout in seconds (default: 30)
#   -h, --help         Show this help
##

_LIB="$(dirname "${BASH_SOURCE[0]}")/scripts/lib"
# shellcheck source=scripts/lib/vars.sh
source "$_LIB/vars.sh"
# shellcheck source=scripts/lib/display.sh
source "$_LIB/display.sh"
# shellcheck source=scripts/lib/auth.sh
source "$_LIB/auth.sh"
# shellcheck source=scripts/lib/config.sh
source "$_LIB/config.sh"

# ── Globals ────────────────────────────────────────────────────────────────────
_ST_RESULTS=()
_ST_PASS=0
_ST_FAIL=0
_ST_TIMEOUT=30
_ST_ENV=""

# ── Test runner ────────────────────────────────────────────────────────────────

# Runs one command with timeout, records timing and pass/fail.
# Usage: _st_run_test <label> <cmd> [args...]
_st_run_test() {
    local label="$1"; shift
    local _t0 _t1 _ms _rc _head _tmpfile
    _tmpfile=$(mktemp)
    _t0=$(date +%s%3N)
    timeout "$_ST_TIMEOUT" "$@" > "$_tmpfile" 2>&1 && _rc=0 || _rc=$?
    _t1=$(date +%s%3N)
    _ms=$(( _t1 - _t0 ))
    _head=$(head -1 "$_tmpfile" 2>/dev/null || true)
    rm -f "$_tmpfile"
    if [[ $_rc -eq 0 ]]; then
        printf "  ${GREEN}✓${NC} %4dms  %s\n" "$_ms" "$label"
        _ST_RESULTS+=("PASS|${_ms}|${label}")
        _ST_PASS=$(( _ST_PASS + 1 ))
    else
        local _detail="exit ${_rc}"
        [[ -n "$_head" ]] && _detail="${_rc}: ${_head}"
        printf "  ${RED}✗${NC} %4dms  %s\n" "$_ms" "$label"
        printf "             → %s\n" "$_detail"
        _ST_RESULTS+=("FAIL|${_ms}|${label}|${_detail}")
        _ST_FAIL=$(( _ST_FAIL + 1 ))
    fi
}

# Prints the auto-test summary line.
_st_print_auto_results() {
    local _total=$(( _ST_PASS + _ST_FAIL ))
    echo ""
    printf "AUTO  : %s ✓  %s ✗  (%s tests)\n" "$_ST_PASS" "$_ST_FAIL" "$_total"
}

# ── Auto-test suites ───────────────────────────────────────────────────────────

_st_run_version_tests() {
    section "[AUTO] Version"
    echo ""
    _st_run_test "fleetman -v"        fleetman -v
    _st_run_test "fleetman --version" fleetman --version
}

_st_run_pod_list_tests() {
    section "[AUTO] Pod list (local)"
    echo ""

    if [[ ! -f "$PODS_FILE" ]]; then
        warn "pods.json absent — pod list tests skipped"
        return
    fi

    _st_run_test "fleetman pod list" fleetman pod list

    local _first_env _first_pod
    _first_env=$(jq -r 'keys[0]' "$PODS_FILE" 2>/dev/null || true)
    _first_pod=$(jq -r --arg e "$_first_env" '.[$e] | to_entries[0].value[0]' "$PODS_FILE" 2>/dev/null || true)

    if [[ -n "$_first_pod" ]]; then
        _st_run_test "fleetman pod list -p $_first_pod" fleetman pod list -p "$_first_pod"
    fi
    if [[ -n "$_first_env" ]]; then
        _st_run_test "fleetman pod list -e $_first_env" fleetman pod list -e "$_first_env"
    fi

    _st_run_test "fleetman pod list -p __nonexistent__" fleetman pod list -p "__nonexistent__"

    # Invalid env should exit non-zero — count as PASS if correctly rejected
    if fleetman pod list -e "__invalid__" > /dev/null 2>&1; then
        printf "  %s✗%s    0ms  fleetman pod list -e __invalid__ (expected non-zero)\n" "$RED" "$NC"
        _ST_RESULTS+=("FAIL|0|fleetman pod list -e __invalid__|expected exit non-zero, got 0")
        _ST_FAIL=$(( _ST_FAIL + 1 ))
    else
        printf "  %s✓%s    0ms  fleetman pod list -e __invalid__ (correctly rejected)\n" "$GREEN" "$NC"
        _ST_RESULTS+=("PASS|0|fleetman pod list -e __invalid__")
        _ST_PASS=$(( _ST_PASS + 1 ))
    fi
}

_st_run_fleet_tests() {
    section "[AUTO] Fleet (SSH)"
    echo ""

    local _env_flag=()
    [[ -n "$_ST_ENV" ]] && _env_flag=(-e "$_ST_ENV")

    _st_run_test "fleetman status${_ST_ENV:+ -e $_ST_ENV}" \
        fleetman status "${_env_flag[@]}"
    _st_run_test "fleetman exec${_ST_ENV:+ -e $_ST_ENV} -- hostname" \
        fleetman exec "${_env_flag[@]}" -- hostname
    _st_run_test "fleetman exec${_ST_ENV:+ -e $_ST_ENV} -- uptime" \
        fleetman exec "${_env_flag[@]}" -- uptime
    _st_run_test "fleetman exec${_ST_ENV:+ -e $_ST_ENV} -- date" \
        fleetman exec "${_env_flag[@]}" -- date
    _st_run_test "fleetman sudo -- id" \
        fleetman sudo -- id
}

# ── Manual plan ────────────────────────────────────────────────────────────────

_st_print_manual_plan() {
    echo ""
    section "TESTS MANUELS"
    cat << 'PLAN'

[ ] SYNC
    fleetman sync                          # sync complet (scripts + config + pods)
    fleetman sync -q                       # quick sync (config only)
    fleetman sync -f                       # + collecte services Docker

[ ] ALIAS
    fleetman alias                         # liste toutes les catégories
    fleetman alias -c <category>           # filtre par catégorie

[ ] POD — opérations d'état
    fleetman pod up -p <pod>               # démarrage docker compose
    fleetman pod pull -p <pod>             # pull image Docker
    fleetman pod update -p <pod>           # mise à jour env vars + restart
    fleetman pod clone -p <pod>            # clone pod vers nouveau serveur
    fleetman pod status -p <pod>           # état des services Docker Compose
    fleetman pod status -p <pod> -e <env>  # scoped à un env

[ ] POD — interactif
    fleetman pod ssh -p <pod>              # shell interactif
    fleetman pod logs -p <pod>             # logs (follow)
    fleetman pod logs -p <pod> -s          # sélection service interactive

[ ] POD ENV
    fleetman pod env cp -p <pod>           # propager .env à tous les serveurs
    fleetman pod env diff -p <pod>         # comparer .env-dist vs .env
    fleetman pod env diff -p <pod> -e <env>
    fleetman pod env edit -p <pod>         # éditer .env

[ ] CONFIG
    fleetman config parallel               # parallel jobs
    fleetman config status                 # containers status_checks + WUD
    fleetman config podsignore             # patterns PCRE
    fleetman config autosync               # cron job
    fleetman config pod                    # gestion pods
    fleetman config selfupdate             # track/branch/pin
    fleetman config welcome                # écran d'accueil
    fleetman config basefolder             # répertoire de travail SSH
    fleetman config templatevars           # template vars globales
    fleetman config env add                # ajouter un env
    fleetman config env color              # changer couleur env
    fleetman config server add             # ajouter un serveur

[ ] SELFUPDATE
    fleetman selfupdate                    # mise à jour depuis git

PLAN
    printf "MANUAL: 31 [ ] à jouer manuellement\n"
}

# ── Entry point ────────────────────────────────────────────────────────────────

main() {
    _ST_PASS=0
    _ST_FAIL=0
    _ST_RESULTS=()
    _ST_TIMEOUT=30
    _ST_ENV=""
    local _plan_only=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --plan)
                _plan_only=true ;;
            --env)
                [[ -z "${2:-}" ]] && { err "--env requires an argument"; exit 1; }
                _ST_ENV="$2"; shift ;;
            --timeout)
                [[ -z "${2:-}" ]] && { err "--timeout requires an argument"; exit 1; }
                _ST_TIMEOUT="$2"; shift ;;
            -h|--help)
                sed -n '/^##$/,/^##$/{/^##$/d; s/^# \{0,1\}//; p}' "${BASH_SOURCE[0]}"
                exit 0 ;;
            *)
                err "Unknown option: $1"; exit 1 ;;
        esac
        shift
    done

    if [[ "$_plan_only" == true ]]; then
        _st_print_manual_plan
        return
    fi

    check_config_file
    if [[ -n "$_ST_ENV" ]]; then
        parse_env "$_ST_ENV" || exit 1
    fi

    echo ""
    section "FLEETMAN SMOKE TEST — $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    check_sshpass
    ask_password

    _st_run_version_tests
    echo ""
    _st_run_pod_list_tests
    echo ""
    _st_run_fleet_tests

    _st_print_auto_results
    _st_print_manual_plan
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then main "$@"; fi
