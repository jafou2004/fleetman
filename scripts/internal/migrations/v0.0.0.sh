#!/bin/bash

# Example migration — this file is never executed in practice (v0.0.0 is below
# any real version), but serves as a reference for writing new migrations.
#
# Naming convention: vX.Y.Z.sh
#   The script runs when upgrading from any version < X.Y.Z to any version >= X.Y.Z.
#
# This script is sourced by run_migrations.sh with a TTY in all cases:
#   - Locally when the git clone is on the current server
#   - Via "ssh -t" when the git clone is on a remote server
# Interactive prompts (read, select_menu, etc.) work in both cases.
#
# Sourcing libs (optional — use relative path from scripts/internal/migrations/):
#   _LIB="$(dirname "${BASH_SOURCE[0]}")/../../lib"
#   source "$_LIB/display.sh"   # ok, err, warn, section
#   source "$_LIB/ui.sh"        # select_menu, prompt_response

_LIB="$(dirname "${BASH_SOURCE[0]}")/../../lib"
# shellcheck source=scripts/lib/vars.sh
source "$_LIB/vars.sh"
# shellcheck source=scripts/lib/display.sh
source "$_LIB/display.sh"

ok "Example migration v0.0.0 — nothing to do"
