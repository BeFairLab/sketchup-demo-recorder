# Fair SketchUp Demo Recorder

Hammerspoon-based tool by [Fair Lab](http://befairlab.com/) for recording, editing, and replaying user click sequences inside SketchUp — with auto-path replay, on-screen click + keystroke overlays, viewport sizing, and automatic crop to YouTube + Reels mp4.

## Links

- Website: <http://befairlab.com/>
- Email:   <hi@befairlab.com>
- GitHub:  <https://github.com/BeFairLab>
- YouTube: <https://www.youtube.com/@BeFairLab>

## Stack

- **Hammerspoon** (Lua) — event capture, replay, window sizing, video capture
- **HTML/JS WebView** — timeline editor UI inside Hammerspoon
- **screencapture / ffmpeg** — viewport video recording + post-processing
- **JSON** — sequence + preset storage

## Install

```bash
git clone https://github.com/BeFairLab/sketchup-demo-recorder.git ~/Code/sketchup-demo-recorder
cd ~/Code/sketchup-demo-recorder
./scripts/install.sh
```

Then:
1. Grant Accessibility + Screen Recording to Hammerspoon (System Settings → Privacy & Security)
2. Enable SDR Companion in SketchUp Extension Manager
3. Reload Hammerspoon
4. Press ⌃⌥⌘V to open the recorder UI

See `QUICKSTART.md` for a full walkthrough.

## Hotkeys

| Combo | Action |
|---|---|
| ⌃⌥⌘R | Toggle record (fresh) |
| ⌃⌥⌘E | Toggle record (continue / append) |
| ⌃⌥⌘P | Replay sequence (no capture) |
| ⌃⌥⌘V | Show/hide tool window |
