#!/usr/bin/env bash
# =============================================================================
#  setup.sh  — postCreateCommand for the CIM Tools codespace demo.
#
#  Stages three tools into a fresh Linux devcontainer:
#    1. cimgraph  — Python env (uv), notebooks read CIM XML directly (no database)
#    2. CIMTool   — Eclipse RCP GUI, downloaded from a GitHub release tarball
#    3. GLIMPSE   — Electron GUI, downloaded as a Linux AppImage
#
#  CIMTool and GLIMPSE are GUI apps; open the noVNC desktop (forwarded port 6080,
#  password "cimtool") and launch them from the desktop icons this script writes.
#
#  Idempotent: every download/extract is guarded so re-running is cheap.
# =============================================================================
set -euo pipefail

# --- Pinned artifact versions (bump these to move to newer releases) ---
CIMTOOL_REPO="AAndersn/CIMTool"
CIMTOOL_TAG="v2.3.1-rc1"
CIMTOOL_VERSION="2.3.1"
CIMTOOL_TARBALL="CIMTool-${CIMTOOL_VERSION}-linux.gtk.x86_64.tar.gz"

GLIMPSE_VERSION="0.8.0"
GLIMPSE_APPIMAGE="GLIMPSE-${GLIMPSE_VERSION}.AppImage"
GLIMPSE_URL="https://github.com/pnnl/GLIMPSE/releases/download/v${GLIMPSE_VERSION}/${GLIMPSE_APPIMAGE}"

# Sample CIM feeder models, pulled from the public GRIDAPPSD Powergrid-Models repo
# at postCreate (avoids committing a 54MB blob / git-lfs into this demo repo).
SAMPLE_MODELS_BASE="https://raw.githubusercontent.com/GRIDAPPSD/Powergrid-Models/develop/models/feeders/CIM/XML"
SAMPLE_9500_URL="${SAMPLE_MODELS_BASE}/IEEE9500bal/IEEE9500bal.xml"
SAMPLE_IEEE13_URL="${SAMPLE_MODELS_BASE}/IEEE13/IEEE13.xml"

# CGMES-CIM17 is itself a CIMTool project (its inner CGMES-CIM17/ folder has a
# .project + Schema/Profiles). Cloned into the CIMTool workspace so it shows up
# in the Project Explorer for the morning session. Tracks latest master.
CGMES_REPO_URL="https://github.com/cimug-org/CGMES-CIM17.git"
# IEEE PES CIM tutorial repo — instance data, Sparx EA models, and a CIMTool
# project (CIMTool-Projects/Part9-ed3). Cloned whole into the CIMTool workspace
# since its contents are still evolving upstream. Tracks latest master.
TUTORIAL_REPO_URL="https://github.com/cimug-org/ieee-pes-cim-tutorial.git"
# CIMTool workspace: launch-cimtool.sh opens CIMTool with `-data $CIMTOOL_WS`,
# so anything placed here appears as a project on launch (no manual import).
CIMTOOL_WS="${HOME}/cimtool-ws"
# GLIMPSE workspace (afternoon session). GLIMPSE's "Load" is a browser
# <input type=file> dialog, which the app can't point at a directory — GTK
# opens it at $HOME. So the sample feeders are symlinked into a folder under
# $HOME (separate from CIMTool's workspace) where the dialog can see them.
GLIMPSE_WS="${HOME}/glimpse-ws"

OPT_CIMTOOL="/opt/cimtool"
OPT_GLIMPSE="/opt/glimpse"
DESKTOP_DIR="${HOME}/Desktop"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SAMPLE_DIR="${REPO_ROOT}/sample_models"

echo "==============================================================="
echo " CIM Tools demo setup"
echo "==============================================================="

# --- Section 1: System GUI / runtime dependencies -----------------------------
# Package names are for Ubuntu 24.04 (noble): the GTK/asound/atk libs carry the
# `t64` suffix (64-bit time_t transition) and WebKitGTK is the 4.1 series.
# libwebkit2gtk-4.1 : CIMTool's SWT Browser (profile SVG view) needs it.
# graphviz          : PlantUML shells out to `dot` for CIMTool profile diagrams.
# libgtk/gbm/asound/nss : Electron (GLIMPSE) runtime libs.
# netsurf-gtk       : lightweight browser for CIMTool's "open in browser" (HTML
#                     profile docs). Chosen over firefox/chromium (snap-only on
#                     24.04) and epiphany (needs bwrap user-namespaces, which are
#                     disabled here) — netsurf renders with no sandbox/D-Bus.
# file              : xdg-open shells out to `file --mime-type` to detect a local
#                     file's type; without it xdg-open can't resolve text/html and
#                     falls back to mousepad. Required for the browser default to work.
echo
echo "[1/8] Installing system GUI/runtime dependencies..."
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
	libwebkit2gtk-4.1-0 \
	graphviz \
	libgtk-3-0t64 \
	libgbm1 \
	libasound2t64 \
	libnss3 \
	libatk-bridge2.0-0t64 \
	fuse3 \
	netsurf-gtk \
	file

# On some Ubuntu images /usr/bin/dot is a dangling symlink to the
# libgvc6-config-update stub (no working layout engine). dot_builtins is a
# self-contained engine; point dot at it only if dot is missing/broken.
if ! dot -V >/dev/null 2>&1; then
	if command -v dot_builtins >/dev/null 2>&1; then
		echo "  fixing broken /usr/bin/dot -> dot_builtins"
		sudo ln -sf "$(command -v dot_builtins)" /usr/bin/dot
	fi
fi

# --- Section 2: Python environment (cimgraph + Jupyter) -----------------------
echo
echo "[2/8] Creating Python environment with uv..."
cd "$REPO_ROOT"
# The workspace is a persistent bind-mount, so a .venv from an earlier build (or
# from running uv on the host) can survive with an interpreter that no longer
# exists here. uv then tries to rebuild in place and can hit a permission error
# on the stale tree. If .venv's interpreter is dead, remove it for a clean sync.
if [ -d .venv ] && ! .venv/bin/python -c '' >/dev/null 2>&1; then
	echo "  removing stale .venv (interpreter no longer valid)"
	# A prior container may have written root-owned files into .venv; fall back
	# to sudo if a plain remove can't clear them.
	rm -rf .venv 2>/dev/null || sudo rm -rf .venv
fi
uv sync
# Register a Jupyter kernel so the notebooks find this env in VS Code.
uv run python -m ipykernel install --user \
	--name cimgraph-demo --display-name "Python (cimgraph-demo)"

# --- Section 3: CIMTool (GUI, from GitHub release tarball) ---------------------
echo
echo "[3/8] Installing CIMTool ${CIMTOOL_VERSION} (${CIMTOOL_TAG})..."
if [ -x "${OPT_CIMTOOL}/CIMTool-${CIMTOOL_VERSION}/CIMTool" ]; then
	echo "  already installed, skipping."
else
	sudo mkdir -p "$OPT_CIMTOOL"
	sudo chown "$(id -u):$(id -g)" "$OPT_CIMTOOL"
	tmp="$(mktemp -d)"
	base="https://github.com/${CIMTOOL_REPO}/releases/download/${CIMTOOL_TAG}"
	echo "  downloading ${CIMTOOL_TARBALL} (~736MB)..."
	curl -fL --retry 3 -o "${tmp}/${CIMTOOL_TARBALL}"        "${base}/${CIMTOOL_TARBALL}"
	curl -fL --retry 3 -o "${tmp}/${CIMTOOL_TARBALL}.sha256" "${base}/${CIMTOOL_TARBALL}.sha256"
	echo "  verifying checksum..."
	( cd "$tmp" && sha256sum -c "${CIMTOOL_TARBALL}.sha256" )
	echo "  extracting..."
	tar -xzf "${tmp}/${CIMTOOL_TARBALL}" -C "$OPT_CIMTOOL"
	rm -rf "$tmp"
	chmod +x "${OPT_CIMTOOL}/CIMTool-${CIMTOOL_VERSION}/CIMTool"
	echo "  installed to ${OPT_CIMTOOL}/CIMTool-${CIMTOOL_VERSION}"
fi

# --- Section 3b: CGMES-CIM17 CIMTool project (into the CIMTool workspace) ------
# Clone the CGMES-CIM17 CIMTool project into the workspace that launch-cimtool.sh
# opens, so it appears in CIMTool's Project Explorer on launch. The repo nests the
# actual project one level down (CGMES-CIM17/CGMES-CIM17), so we move that inner
# folder up into the workspace. Fail-soft: a clone failure warns but must not
# abort setup — CIMTool still runs, just without the pre-loaded project.
echo
echo "[4/8] Cloning CGMES-CIM17 project into CIMTool workspace..."
mkdir -p "$CIMTOOL_WS"
if [ -f "${CIMTOOL_WS}/CGMES-CIM17/.project" ]; then
	echo "  already present, skipping."
else
	tmp="$(mktemp -d)"
	if git clone --depth 1 "$CGMES_REPO_URL" "${tmp}/repo"; then
		# The importable CIMTool project is the nested CGMES-CIM17/CGMES-CIM17.
		if [ -f "${tmp}/repo/CGMES-CIM17/.project" ]; then
			rm -rf "${CIMTOOL_WS}/CGMES-CIM17"
			mv "${tmp}/repo/CGMES-CIM17" "${CIMTOOL_WS}/CGMES-CIM17"
			echo "  installed CGMES-CIM17 into ${CIMTOOL_WS}"
		else
			echo "  WARNING: cloned repo has no CGMES-CIM17/.project — skipping." >&2
		fi
	else
		echo "  WARNING: could not clone ${CGMES_REPO_URL} — skipping." >&2
	fi
	rm -rf "$tmp"
fi

# ieee-pes-cim-tutorial: clone the entire repo into the workspace as-is. It has
# instance data (XML), Sparx EA models (.qea), and a CIMTool project inside
# CIMTool-Projects/Part9-ed3. Repo is still evolving upstream, so we keep the
# whole tree rather than extracting a single folder. Fail-soft.
if [ -d "${CIMTOOL_WS}/ieee-pes-cim-tutorial/.git" ]; then
	echo "  ieee-pes-cim-tutorial already present, skipping."
else
	if git clone --depth 1 "$TUTORIAL_REPO_URL" "${CIMTOOL_WS}/ieee-pes-cim-tutorial"; then
		echo "  cloned ieee-pes-cim-tutorial into ${CIMTOOL_WS}"
	else
		echo "  WARNING: could not clone ${TUTORIAL_REPO_URL} — skipping." >&2
	fi
fi

# --- Section 4: GLIMPSE (GUI, from AppImage) ----------------------------------
# AppImages need FUSE; rather than depend on it in the container we extract the
# AppImage and run its AppRun directly (the FUSE-free path).
echo
echo "[5/8] Installing GLIMPSE ${GLIMPSE_VERSION}..."
if [ -x "${OPT_GLIMPSE}/squashfs-root/AppRun" ]; then
	echo "  already installed, skipping."
else
	sudo mkdir -p "$OPT_GLIMPSE"
	sudo chown "$(id -u):$(id -g)" "$OPT_GLIMPSE"
	echo "  downloading ${GLIMPSE_APPIMAGE} (~214MB)..."
	curl -fL --retry 3 -o "${OPT_GLIMPSE}/${GLIMPSE_APPIMAGE}" "$GLIMPSE_URL"
	chmod +x "${OPT_GLIMPSE}/${GLIMPSE_APPIMAGE}"
	echo "  extracting AppImage..."
	( cd "$OPT_GLIMPSE" && "./${GLIMPSE_APPIMAGE}" --appimage-extract >/dev/null )
	rm -f "${OPT_GLIMPSE}/${GLIMPSE_APPIMAGE}"
	echo "  installed to ${OPT_GLIMPSE}/squashfs-root"
fi

# --- Section 6: Sample CIM feeder models --------------------------------------
# Downloaded into the repo's sample_models/ (the source of truth — visible in
# the VS Code explorer and on the host), then symlinked into ~/glimpse-ws so
# GLIMPSE's file dialog can see them (see the symlink step below for why).
# Fail-soft: a network/upstream failure must not abort setup — the GUI apps and
# notebooks still work without the samples.
echo
echo "[6/8] Downloading sample CIM feeder models..."
mkdir -p "$SAMPLE_DIR"
download_sample() {
	# $1 = url, $2 = destination filename
	local url="$1" dest="${SAMPLE_DIR}/$2"
	if [ -s "$dest" ]; then
		echo "  $2 already present, skipping."
		return 0
	fi
	echo "  downloading $2..."
	if curl -fL --retry 3 -o "$dest" "$url"; then
		echo "  saved $2 ($(du -h "$dest" | cut -f1))"
	else
		echo "  WARNING: could not download $2 from $url — skipping." >&2
		rm -f "$dest"
	fi
}
download_sample "$SAMPLE_IEEE13_URL" "IEEE13.xml"
download_sample "$SAMPLE_9500_URL"   "IEEE9500bal.xml"

# GLIMPSE's "Load" is a browser <input type=file> dialog (its Electron main.js
# has no native open-dialog), so the app can't preset the starting directory —
# GTK opens the chooser at $HOME. sample_models/ lives under /workspaces/... (a
# different tree), so it isn't visible there. Symlink each sample into a folder
# under $HOME (~/glimpse-ws) so it shows up where the dialog opens, and add a
# GTK bookmark so it's one click from the chooser sidebar. Keeps the repo copy
# as the source of truth. Fail-soft.
mkdir -p "$GLIMPSE_WS"
for f in IEEE13.xml IEEE9500bal.xml; do
	if [ -s "${SAMPLE_DIR}/${f}" ]; then
		ln -sfn "${SAMPLE_DIR}/${f}" "${GLIMPSE_WS}/${f}"
	fi
done
# Also link the tutorial repo's instance data so GLIMPSE can see it too.
if [ -d "${CIMTOOL_WS}/ieee-pes-cim-tutorial" ]; then
	ln -sfn "${CIMTOOL_WS}/ieee-pes-cim-tutorial" "${GLIMPSE_WS}/ieee-pes-cim-tutorial"
fi
echo "  linked samples into ${GLIMPSE_WS} (for the GLIMPSE Load dialog)."

# Add ~/glimpse-ws to the GTK3 file-chooser sidebar (one-click in GLIMPSE).
GTK_BOOKMARKS="${HOME}/.config/gtk-3.0/bookmarks"
mkdir -p "$(dirname "$GTK_BOOKMARKS")"
if ! grep -qsF "file://${GLIMPSE_WS}" "$GTK_BOOKMARKS" 2>/dev/null; then
	echo "file://${GLIMPSE_WS} GLIMPSE samples" >> "$GTK_BOOKMARKS"
	echo "  added ${GLIMPSE_WS} to the GTK file-chooser sidebar."
fi

# --- Section 7: Desktop launchers + fluxbox menu ------------------------------
# The two GUI apps are launched via scripts/launch-{cimtool,glimpse}.sh (one per
# tutorial session — CIMTool = morning, GLIMPSE = afternoon). The .desktop files
# and the fluxbox right-click menu both point at those scripts, so there's a
# single source of truth for launch args (workspace path, swiftshader flags).
echo
echo "[7/8] Writing desktop launchers and fluxbox menu entries..."
LAUNCH_CIMTOOL="${REPO_ROOT}/scripts/launch-cimtool.sh"
LAUNCH_GLIMPSE="${REPO_ROOT}/scripts/launch-glimpse.sh"
chmod +x "$LAUNCH_CIMTOOL" "$LAUNCH_GLIMPSE"

mkdir -p "$DESKTOP_DIR"

cat > "${DESKTOP_DIR}/CIMTool.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=CIMTool
Comment=CIM profile and model editor (Eclipse RCP) — tutorial morning session
Exec=${LAUNCH_CIMTOOL}
Icon=${OPT_CIMTOOL}/CIMTool-${CIMTOOL_VERSION}/icon.xpm
Terminal=false
Categories=Development;
EOF

cat > "${DESKTOP_DIR}/GLIMPSE.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=GLIMPSE
Comment=Power system graph visualizer (Electron) — tutorial afternoon session
Exec=${LAUNCH_GLIMPSE}
Terminal=false
Categories=Development;
EOF

chmod +x "${DESKTOP_DIR}/CIMTool.desktop" "${DESKTOP_DIR}/GLIMPSE.desktop"

# fluxbox shows nothing on the desktop by default, so make the apps reachable
# from its right-click menu. desktop-lite writes ~/.fluxbox/menu once and does
# not regenerate it, so inserting our entries here is stable. Guard on a grep so
# re-running setup.sh doesn't add duplicates; fail-soft if the menu is missing.
FLUXBOX_MENU="${HOME}/.fluxbox/menu"
if [ -f "$FLUXBOX_MENU" ]; then
	if ! grep -q "launch-cimtool.sh" "$FLUXBOX_MENU"; then
		# Insert the two entries right after the [begin] line (top of the menu).
		sed -i "/^\[begin\]/a\\
    [exec] (CIMTool) { ${LAUNCH_CIMTOOL} } <>\\
    [exec] (GLIMPSE) { ${LAUNCH_GLIMPSE} } <>" "$FLUXBOX_MENU"
		echo "  added CIMTool and GLIMPSE to the fluxbox right-click menu."
	else
		echo "  fluxbox menu entries already present, skipping."
	fi
else
	echo "  WARNING: ${FLUXBOX_MENU} not found — skipping menu entries." >&2
fi

# --- Section 8: Default web browser (CIMTool "open in browser") ---------------
# CIMTool's "open in browser" (and any xdg-open call) needs a registered default
# handler for text/html and the http(s) schemes. With none set, xdg-open falls
# back to mousepad and HTML profile docs open as source text. Point all three at
# netsurf (installed in section 1). Writes to this user's ~/.config/mimeapps.list.
echo
echo "[8/8] Registering netsurf as the default web browser..."
if command -v xdg-mime >/dev/null 2>&1; then
	xdg-mime default netsurf-gtk.desktop \
		text/html x-scheme-handler/http x-scheme-handler/https
	echo "  text/html + http(s) -> netsurf-gtk.desktop"
else
	echo "  WARNING: xdg-mime not found — skipping browser default." >&2
fi

echo
echo "==============================================================="
echo " Setup complete."
echo "   Notebooks : run in VS Code with the 'Python (cimgraph-demo)' kernel."
echo "   GUI apps  : open forwarded port 6080 (noVNC, password 'cimtool'),"
echo "               then right-click the desktop -> CIMTool or GLIMPSE"
echo "               (or run scripts/launch-cimtool.sh / launch-glimpse.sh)."
echo "   CIMTool   : opens ${CIMTOOL_WS} with the CGMES-CIM17 project loaded."
echo "   GLIMPSE   : Load samples from ${GLIMPSE_WS} (sidebar bookmark)."
echo "   Samples   : sample_models/IEEE9500bal.xml (or IEEE13.xml if slow)."
echo "==============================================================="
