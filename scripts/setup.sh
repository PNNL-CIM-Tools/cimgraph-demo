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
echo
echo "[1/5] Installing system GUI/runtime dependencies..."
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
	libwebkit2gtk-4.1-0 \
	graphviz \
	libgtk-3-0t64 \
	libgbm1 \
	libasound2t64 \
	libnss3 \
	libatk-bridge2.0-0t64 \
	fuse3

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
echo "[2/5] Creating Python environment with uv..."
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
echo "[3/5] Installing CIMTool ${CIMTOOL_VERSION} (${CIMTOOL_TAG})..."
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

# --- Section 4: GLIMPSE (GUI, from AppImage) ----------------------------------
# AppImages need FUSE; rather than depend on it in the container we extract the
# AppImage and run its AppRun directly (the FUSE-free path).
echo
echo "[4/5] Installing GLIMPSE ${GLIMPSE_VERSION}..."
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

# --- Section 5: Sample CIM feeder models --------------------------------------
# Downloaded into the workspace so they appear in the GUI file explorers
# (GLIMPSE "Load", CIMTool import). Fail-soft: a network/upstream failure must
# not abort setup — the GUI apps and notebooks still work without the samples.
echo
echo "[5/6] Downloading sample CIM feeder models..."
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

# --- Section 6: Desktop launchers (shown on the noVNC desktop) -----------------
echo
echo "[6/6] Writing desktop launchers..."
mkdir -p "$DESKTOP_DIR"

cat > "${DESKTOP_DIR}/CIMTool.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=CIMTool
Comment=CIM profile and model editor (Eclipse RCP)
Exec=${OPT_CIMTOOL}/CIMTool-${CIMTOOL_VERSION}/CIMTool
Icon=${OPT_CIMTOOL}/CIMTool-${CIMTOOL_VERSION}/icon.xpm
Terminal=false
Categories=Development;
EOF

# Electron launch flags for the headless noVNC desktop:
#   --no-sandbox         : required when running as a container user with no
#                          user-namespace sandbox.
#   --use-gl=angle
#   --use-angle=swiftshader
#   --enable-unsafe-swiftshader : force software GL via SwiftShader. Without this,
#                          --disable-gpu falls back to Chromium's X11 software-BITMAP
#                          presenter, which fails XGetWindowAttributes under Xtigervnc
#                          — menus/dialogs (hamburger, About, Load) then never
#                          composite and clicks don't route. SwiftShader composites
#                          correctly, so the UI is fully interactive.
cat > "${DESKTOP_DIR}/GLIMPSE.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=GLIMPSE
Comment=Power system graph visualizer (Electron)
Exec=${OPT_GLIMPSE}/squashfs-root/AppRun --no-sandbox --use-gl=angle --use-angle=swiftshader --enable-unsafe-swiftshader
Terminal=false
Categories=Development;
EOF

chmod +x "${DESKTOP_DIR}/CIMTool.desktop" "${DESKTOP_DIR}/GLIMPSE.desktop"

echo
echo "==============================================================="
echo " Setup complete."
echo "   Notebooks : run in VS Code with the 'Python (cimgraph-demo)' kernel."
echo "   GUI apps  : open forwarded port 6080 (noVNC, password 'cimtool')"
echo "               then launch CIMTool / GLIMPSE from the desktop icons."
echo "   Samples   : sample_models/IEEE9500bal.xml (or IEEE13.xml if slow)."
echo "==============================================================="
