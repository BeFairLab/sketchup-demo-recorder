#!/usr/bin/env bash
# install.sh — symlink Hammerspoon module + SU companion plugin from repo.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
echo "Repo root: $REPO_ROOT"

# ─── Hammerspoon ───────────────────────────────────────────────────────
HS_DIR="$HOME/.hammerspoon"
HS_TARGET="$HS_DIR/sdr"
mkdir -p "$HS_DIR"
if [ -L "$HS_TARGET" ] || [ -d "$HS_TARGET" ]; then
  rm -rf "$HS_TARGET"
fi
ln -s "$REPO_ROOT/hammerspoon/sdr" "$HS_TARGET"
echo "Symlinked: $HS_TARGET → $REPO_ROOT/hammerspoon/sdr"

# Append loader to ~/.hammerspoon/init.lua if not already present.
HS_INIT="$HS_DIR/init.lua"
touch "$HS_INIT"
if ! grep -q "require('sdr')" "$HS_INIT" 2>/dev/null; then
  cat >> "$HS_INIT" <<EOF

-- sketchup-demo-recorder
sdr = require('sdr')
sdr.start({ repo_root = '$REPO_ROOT' })
EOF
  echo "Appended SDR loader to $HS_INIT"
else
  echo "SDR loader already present in $HS_INIT"
fi

# ─── SketchUp companion plugin ─────────────────────────────────────────
# Detect installed SU versions in standard plugin path.
for ver in 2026 2025 2024 2023; do
  SU_PLUGINS="$HOME/Library/Application Support/SketchUp $ver/SketchUp/Plugins"
  if [ -d "$SU_PLUGINS" ]; then
    REG="$SU_PLUGINS/sdr_companion.rb"
    DIR="$SU_PLUGINS/sdr_companion"
    rm -f "$REG"
    rm -rf "$DIR"
    ln -s "$REPO_ROOT/companion/sdr_companion/sdr_companion.rb" "$REG"
    ln -s "$REPO_ROOT/companion/sdr_companion/sdr_companion"    "$DIR"
    echo "Symlinked SU $ver companion plugin → $SU_PLUGINS"
  fi
done

echo ""
echo "Done. Next steps:"
echo "  1. Reload Hammerspoon (menubar → Reload Config)"
echo "  2. Restart SketchUp (or reload via Window → Ruby Console: load 'sdr_companion.rb')"
echo "  3. Grant macOS permissions: Accessibility (Hammerspoon) + Screen Recording (Hammerspoon, screencapture)"
echo "  4. Hotkey: ⌃⌥⌘V to open SDR UI"
