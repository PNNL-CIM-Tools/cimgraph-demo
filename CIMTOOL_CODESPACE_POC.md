# CIMTool in GitHub Codespaces — Proof of Concept Plan

## Goal

Validate whether CIMTool (Eclipse RCP desktop app) can run in a GitHub Codespace
via noVNC, eliminating the need for Windows VMs at the summer hackathon.

## Background

- CIMTool is an Eclipse RCP product (Java 20, SWT/GTK, OSGi)
- Official releases are Windows-only (.exe)
- The `.product` file already declares a Linux launcher icon, so Linux builds are supported in principle
- No automated build exists (Tycho/Maven) — builds are manual "File > Export > Eclipse Product" in Eclipse IDE
- The `cimtool-cli` uber-JAR exists for headless work but the hackathon demo is GUI-focused

## Architecture

```
GitHub Codespace (Linux container)
├── noVNC (browser → VNC on port 6080)
│   └── lightweight desktop (fluxbox/xfce4)
│       └── CIMTool Linux RCP product (SWT/GTK)
├── Java 20 runtime
├── Existing Python stack (cimgraph, blazegraph, etc.)
└── VS Code (normal codespace IDE)
```

## Prerequisites (before testing)

1. **Produce a Linux CIMTool build** — one-time manual step:
   - Open CIMTool workspace in Eclipse (on your Windows machine)
   - File > Export > Plug-in Development > Eclipse Product
   - Configuration: `/CIMToolProduct/CIMTool.product`
   - In the export dialog, set target OS/arch: `linux / gtk / x86_64`
   - Export to a local directory, then ZIP the result
   - Upload as a GitHub release artifact on the fork (or drop in this repo under `CIMTool/`)

2. **Verify the ZIP contains:**
   - `CIMTool` executable (Linux launcher)
   - `plugins/` directory with all OSGi bundles
   - `configuration/` directory
   - SWT GTK fragment (`org.eclipse.swt.gtk.linux.x86_64_*.jar`)

## Devcontainer Changes

Modify `.devcontainer/devcontainer.json` to add:

```jsonc
{
  "name": "CIMGraph + CIMTool Demo",
  "image": "mcr.microsoft.com/devcontainers/python:0-3.10",
  "hostRequirements": {
    "cpus": 4
  },
  "features": {
    "ghcr.io/devcontainers/features/docker-in-docker:2": {},
    "ghcr.io/devcontainers/features/desktop-lite:1": {
      "password": "cimtool",
      "webPort": "6080",
      "vncPort": "5901"
    },
    "ghcr.io/devcontainers/features/java:1": {
      "version": "20",
      "installGradle": "false",
      "installMaven": "false"
    }
  },
  "forwardPorts": [6080, 8889],
  "portsAttributes": {
    "6080": {
      "label": "CIMTool Desktop (noVNC)",
      "onAutoForward": "openBrowser"
    }
  },
  "customizations": {
    "vscode": {
      "extensions": [
        "ms-python.python",
        "ms-python.vscode-pylance",
        "github.vscode-pull-request-github",
        "eamodio.gitlens",
        "ms-toolsai.jupyter"
      ]
    }
  },
  "postCreateCommand": "bash scripts/setup.sh"
}
```

Add to `scripts/setup.sh` (or a separate `scripts/setup-cimtool.sh`):

```bash
# --- CIMTool Linux GUI setup ---
# Download pre-built Linux release (update URL after uploading)
CIMTOOL_ZIP_URL="https://github.com/<fork>/CIMTool/releases/download/v2.3.0-linux/CIMTool-2.3.0-linux.gtk.x86_64.zip"
curl -fsSL "$CIMTOOL_ZIP_URL" -o /tmp/cimtool.zip
sudo mkdir -p /opt/cimtool
sudo unzip -q /tmp/cimtool.zip -d /opt/cimtool
sudo chmod +x /opt/cimtool/CIMTool
rm /tmp/cimtool.zip

# GTK3 runtime libs needed by SWT
sudo apt-get update
sudo apt-get install -y libgtk-3-0 libwebkit2gtk-4.0-37 libswt-gtk-4-java 2>/dev/null || true

# Desktop shortcut for easy launch
mkdir -p ~/Desktop
cat > ~/Desktop/CIMTool.desktop <<EOF
[Desktop Entry]
Type=Application
Name=CIMTool
Exec=/opt/cimtool/CIMTool
Icon=/opt/cimtool/icon.xpm
Terminal=false
EOF
chmod +x ~/Desktop/CIMTool.desktop
```

## Test Procedure

1. Push devcontainer changes to repo
2. Open in GitHub Codespaces (or `devcontainer up` locally with Docker)
3. Wait for build to complete
4. Open port 6080 in browser (noVNC desktop)
5. Double-click CIMTool on desktop (or run `/opt/cimtool/CIMTool` in terminal)
6. Verify: splash screen appears, workspace prompt loads, profile editor is functional

## Known Risks / Likely Failure Points

| Risk | Impact | Mitigation |
|------|--------|------------|
| SWT/GTK version mismatch | CIMTool won't launch | Pin GTK3 packages matching the Eclipse version |
| Missing native libs (libwebkit2gtk, libcairo, etc.) | Crash on startup | Check `.log` in workspace `.metadata/` for missing deps |
| noVNC performance too slow for tree-heavy UI | Unusable UX | Test with real CIM schema loaded |
| Java 20 not available in devcontainer feature | Build won't start | Fall back to Java 17 (product manifest says 17, plugin says 20) |
| Eclipse RCP needs writable `configuration/` dir | Permission errors | Ensure `/opt/cimtool` is writable or use `-configuration` flag |
| x86_64 emulation on ARM codespace hosts | Very slow or broken | Force x86_64 machine type in `hostRequirements` |

## Fallback Plan

If CIMTool GUI doesn't work in codespace:
- **Option A:** Windows VMs (original plan) — CIMTool works out of the box
- **Option B:** Package CIMGraph as a desktop app (PySide6/CIMantic-Studio approach) — avoids Java/Eclipse entirely, demo stays Python-native

## Next Steps

1. [ ] Do the Linux PDE export from Eclipse on Windows
2. [ ] Upload ZIP to GitHub release on fork
3. [ ] Update `CIMTOOL_ZIP_URL` in setup script
4. [ ] Push devcontainer changes, open codespace, test launch
5. [ ] If it works: load a real CIM schema and walk through profile editing
6. [ ] Decision: proceed with codespace approach or fall back
