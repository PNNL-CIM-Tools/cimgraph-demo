#!/usr/bin/env bash
# =============================================================================
#  launch-cimtool.sh — start CIMTool (tutorial MORNING session).
#
#  Opens CIMTool on a fixed workspace (~/cimtool-ws) so it skips the interactive
#  workspace-picker dialog and shows the pre-loaded CGMES-CIM17 project (cloned
#  there by scripts/setup.sh) in its Project Explorer.
#
#  Works both from a terminal inside the noVNC desktop and from the VS Code
#  terminal on the host — DISPLAY defaults to the desktop-lite VNC display (:1).
# =============================================================================
set -euo pipefail

# CIMTool version — keep in sync with CIMTOOL_VERSION in scripts/setup.sh.
CIMTOOL_VERSION="2.3.1"
CIMTOOL_BIN="/opt/cimtool/CIMTool-${CIMTOOL_VERSION}/CIMTool"
CIMTOOL_WS="${HOME}/cimtool-ws"

# The noVNC desktop runs on display :1; default to it when launched from a
# terminal that has no DISPLAY of its own.
export DISPLAY="${DISPLAY:-:1}"

exec "$CIMTOOL_BIN" -data "$CIMTOOL_WS"
