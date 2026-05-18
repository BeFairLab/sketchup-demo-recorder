# Quickstart

5-minute path from clone → first recording.

## 1. Prerequisites

See [REQUIREMENTS.md](REQUIREMENTS.md). At a minimum:
- macOS 13+, SketchUp 2022.1+, Hammerspoon, ffmpeg.

## 2. Clone + install

```bash
git clone https://github.com/BeFairLab/sketchup-demo-recorder.git ~/Code/sketchup-demo-recorder
cd ~/Code/sketchup-demo-recorder
./scripts/install.sh
```

`install.sh`:
- Symlinks `hammerspoon/sdr/` → `~/.hammerspoon/sdr`
- Appends `require('sdr'); sdr.start(...)` to `~/.hammerspoon/init.lua`
- Symlinks the SDR Companion plugin into every installed SketchUp's Plugins folder

## 3. Grant macOS permissions

System Settings → Privacy & Security → enable for **Hammerspoon**:
1. Accessibility
2. Screen Recording
3. Input Monitoring (if prompted)

## 4. Enable SDR Companion in SketchUp

Open SketchUp → **Window → Extension Manager** → toggle **SDR Companion** to ON → restart SketchUp once.

## 5. Smoke test

1. Open Hammerspoon (menubar hammer icon → Reload Config if needed)
2. Press **⌃⌥⌘V** → "Fair SketchUp Demo Recorder" window opens
3. Click **Ping companion** → expect `{"result":"pong"}`. If timeout, the SDR Companion isn't loaded — recheck step 4.

## 6. Make a first recording

Follow [HOWTO.md](HOWTO.md). TL;DR:
1. Preset settings tab → **New… (defaults)** → name it → tweak → **Save changes**
2. Header: pick the preset → **Apply to SketchUp**
3. Timeline tab → **New… (prompt + save)** → name it
4. ⌃⌥⌘R → click around in SketchUp → ⌃⌥⌘R
5. **⏺ Record + Replay** → mp4 lands on Desktop

## Hotkeys

| Combo | Action |
|---|---|
| ⌃⌥⌘R | Toggle record (fresh) |
| ⌃⌥⌘E | Toggle record (continue / append) |
| ⌃⌥⌘P | Replay sequence (no capture) |
| ⌃⌥⌘V | Show/hide tool window |

## Troubleshooting

| Symptom | Fix |
|---|---|
| Hotkeys don't fire | Grant Accessibility to Hammerspoon, then reload HS |
| `Ping companion` fails | Restart SketchUp; check `/tmp/sdr_companion.log` |
| Empty mp4 / black frames | Grant Screen Recording to Hammerspoon |
| `Apply to SketchUp` errors | Need SketchUp 2022.1+ for `Sketchup.resize_viewport` |
| Replay clicks land off-target | SU window moved after recording — Apply preset again |
| Reels variant is 0 KB | Crop target exceeds source — switch to smaller universal preset |
