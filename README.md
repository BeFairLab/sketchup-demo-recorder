# sketchup-demo-recorder

Hammerspoon-based tool for recording, editing, and replaying click sequences inside SketchUp (and any app) for producing demo videos.

## Stack

- **Hammerspoon** (Lua) — event capture, replay, window sizing, video capture
- **HTML/JS WebView** — timeline editor UI inside Hammerspoon
- **screencapture / ffmpeg** — viewport video recording
- **JSON** — sequence storage format

## Status

Pre-implementation. Design spec in `docs/specs/`.
