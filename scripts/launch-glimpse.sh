#!/usr/bin/env bash
# =============================================================================
#  launch-glimpse.sh — start GLIMPSE (tutorial AFTERNOON session).
#
#  GLIMPSE is an Electron app. The swiftshader GL flags are required on the
#  headless noVNC desktop: without them Chromium falls back to its X11
#  software-BITMAP presenter, which fails XGetWindowAttributes under Xtigervnc
#  so menus/dialogs (hamburger, About, Load) never composite and clicks don't
#  route. SwiftShader software GL composites correctly, so the UI is interactive.
#  --no-sandbox is required for a container user with no user-namespace sandbox.
#
#  Works from a terminal inside the noVNC desktop or from the VS Code terminal;
#  DISPLAY defaults to the desktop-lite VNC display (:1).
# =============================================================================
set -euo pipefail

GLIMPSE_APPRUN="/opt/glimpse/squashfs-root/AppRun"

export DISPLAY="${DISPLAY:-:1}"

exec "$GLIMPSE_APPRUN" \
	--no-sandbox \
	--use-gl=angle \
	--use-angle=swiftshader \
	--enable-unsafe-swiftshader
