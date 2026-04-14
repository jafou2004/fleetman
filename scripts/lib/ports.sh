#!/bin/bash

# Port helpers — shared by fleetman port subcommands.
[[ -n "${_FLEETMAN_PORTS_LOADED:-}" ]] && return 0
_FLEETMAN_PORTS_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/vars.sh"
source "$(dirname "${BASH_SOURCE[0]}")/display.sh"

# Exits with error if $SERVICES_FILE does not exist.
# Call in port subcommands before reading services.json.
check_services_file() {
    if [ ! -f "$SERVICES_FILE" ]; then
        err "services.json not found — run 'fleetman sync --full' first"
        exit 1
    fi
}

# Reads port_range from config.json into globals PORT_MIN and PORT_MAX.
# Exits with error if port_range is absent.
_port_read_range() {
    PORT_MIN=$(jq -r '.port_range.min // empty' "$CONFIG_FILE" 2>/dev/null)
    PORT_MAX=$(jq -r '.port_range.max // empty' "$CONFIG_FILE" 2>/dev/null)
    if [ -z "$PORT_MIN" ] || [ -z "$PORT_MAX" ]; then
        err "port_range not configured — run 'fleetman config portrange'"
        exit 1
    fi
}

# Collects all used external ports from services.json.
# Outputs a JSON array of objects: {port, pod, service, env, server}
# port is a number; server is the full FQDN.
_port_collect_used() {
    jq '[
      to_entries[] | .key as $env |
      .value | to_entries[] | .key as $srv |
      .value | to_entries[] | .key as $pod |
      .value[] |
      .Service as $svc |
      (.Publishers[]? | select(.PublishedPort > 0)) |
      { port: .PublishedPort, pod: $pod, service: $svc, env: $env, server: $srv }
    ]' "$SERVICES_FILE"
}
