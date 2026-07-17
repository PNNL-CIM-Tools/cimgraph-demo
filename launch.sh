#!/usr/bin/env bash
# =============================================================================
#  launch.sh — host-side helper to run scripts/setup.sh in a live devcontainer.
#
#  setup.sh targets Ubuntu 24.04 (noble) and installs GUI apps + MIME defaults;
#  it is NOT safe to run on the WSL host (jammy — the t64 package names don't
#  even exist there). This script runs it where it belongs: inside the noble
#  devcontainer, as the `vscode` user, against your CURRENT working copy.
#
#  It reuses the image the VS Code Dev Containers extension already built
#  (vsc-cimgraph-demo-*). Build that once via "Dev Containers: Rebuild Container"
#  (or the devcontainer CLI) before running this.
#
#  The container is left RUNNING afterwards so you can poke at it, e.g.:
#     docker exec -u vscode -it <name> bash
#  Stop/remove it with:  docker rm -f cimgraph-demo-test
# =============================================================================
set -euo pipefail

CONTAINER_NAME="cimgraph-demo-test"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Mounted at the standard devcontainer workspace path so setup.sh's REPO_ROOT
# resolution and relative paths behave exactly as under postCreateCommand.
WORKSPACE_MOUNT="/workspaces/cimgraph-demo"

# --- Locate the devcontainer image the VS Code extension built ----------------
# Its name is vsc-<folder>-<hash>[-uid]; pick the most recent match.
IMAGE="$(docker images --format '{{.Repository}}:{{.Tag}}' \
	| grep '^vsc-cimgraph-demo-' | head -n1 || true)"

if [ -z "$IMAGE" ]; then
	echo "ERROR: no vsc-cimgraph-demo-* image found." >&2
	echo "  Build the devcontainer first (VS Code: 'Dev Containers: Rebuild" >&2
	echo "  Container', or the devcontainer CLI), then re-run this script." >&2
	exit 1
fi
echo "Using image: $IMAGE"

# --- Recreate the test container from scratch ---------------------------------
# Remove any leftover from a previous run so each launch is a clean slate.
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

echo "Starting container '$CONTAINER_NAME'..."
docker run -d --name "$CONTAINER_NAME" \
	-v "${REPO_ROOT}:${WORKSPACE_MOUNT}" \
	-p 6080:6080 \
	"$IMAGE" sleep infinity >/dev/null

# --- Run setup.sh as the vscode user (how postCreateCommand runs it) ----------
echo "Running scripts/setup.sh as vscode..."
docker exec -u vscode -w "$WORKSPACE_MOUNT" "$CONTAINER_NAME" \
	bash scripts/setup.sh

echo
echo "==============================================================="
echo " setup.sh finished in container '$CONTAINER_NAME' (left running)."
echo "   Shell in :   docker exec -u vscode -it $CONTAINER_NAME bash"
echo "   noVNC     :   http://localhost:6080  (password: cimtool)"
echo "   Remove    :   docker rm -f $CONTAINER_NAME"
echo "==============================================================="
