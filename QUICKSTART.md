# Quickstart

## 0. Prerequisites

- macOS 13+
- Hammerspoon (`brew install --cask hammerspoon`)
- SketchUp 2022.1+ (resize_viewport API)
- ffmpeg optional (`screencapture -V` is used by default)

## 1. Install

```bash
git clone <this repo> ~/Code/sketchup-demo-recorder
cd ~/Code/sketchup-demo-recorder
./scripts/install.sh
```

This:
- Symlinks `hammerspoon/sdr/` → `~/.hammerspoon/sdr`
- Appends `require('sdr'); sdr.start(...)` to `~/.hammerspoon/init.lua`
- Symlinks `companion/sdr_companion/*` → `~/Library/Application Support/SketchUp <ver>/SketchUp/Plugins/`

## 2. Grant macOS permissions

System Settings → Privacy & Security:

1. **Accessibility** → enable for **Hammerspoon** (required for `hs.eventtap` + `hs.window`)
2. **Screen Recording** → enable for **Hammerspoon** (required for screen capture)
3. **Input Monitoring** (if prompted) → enable for **Hammerspoon**

## 3. Launch

1. Open Hammerspoon (menubar → its hammer icon)
2. Open SketchUp; dismiss welcome and open any model
3. Reload Hammerspoon: menubar → SDR → Reload

Verify companion plugin is alive:
- Menubar → SDR → "Ping Companion" → should show **OK: pong**
- Or: `cat /tmp/sdr_companion.log` should show "companion installed, polling …"

## 4. Open UI

- Hotkey **⌃⌥⌘V** → opens "SketchUp Demo Recorder" window

## 5. Record your first sequence

1. In SDR UI: type a name in the text field → click **New**
2. Set viewport mode + preset → **Apply to SketchUp** (SU window resizes)
3. Switch to SketchUp, put it in the start state (open scene, no selection)
4. Hotkey **⌃⌥⌘R** → recording starts (menubar dot turns red)
5. Click around in SketchUp as if doing the demo
6. Hotkey **⌃⌥⌘R** → recording stops
7. Back in SDR UI: timeline populates. Edit pause-chip values (ms) inline.
8. Click **Save**

## 6. Replay

- **▶ Play (no capture)** — fires events with edited timings; nothing recorded
- **⏺ Record + Replay** — starts `screencapture -V` on viewport region, replays, saves mp4 to `~/Movies/sdr/`

## 7. Hotkeys

| Combo | Action |
|---|---|
| ⌃⌥⌘R | Toggle record clicks |
| ⌃⌥⌘P | Replay sequence (no capture) |
| ⌃⌥⌘V | Show/hide SDR UI |

## Troubleshooting

| Symptom | Fix |
|---|---|
| Hotkeys don't fire | Grant Accessibility to Hammerspoon, then reload HS |
| Ping Companion fails | Restart SketchUp; check `/tmp/sdr_companion.log` |
| Empty mp4 / black frames | Grant Screen Recording to Hammerspoon AND `/usr/sbin/screencapture` |
| Apply Viewport fails | Need SketchUp 2022.1+ for `Sketchup.resize_viewport` |
| Hotkeys interfere with recording | Recorder filters our 3 hotkeys automatically |
