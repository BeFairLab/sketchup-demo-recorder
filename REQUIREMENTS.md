# Requirements

## System

- macOS 13+ (Ventura or newer)
- ARM (Apple Silicon) — tested on M-series; Intel should work but is unverified
- Built-in display ≥ 1117 pt logical height for any 1080p-tall recording target
- One free TCP port on 127.0.0.1 (auto-assigned)

## Software

| Tool | Purpose | Install |
|---|---|---|
| **SketchUp 2022.1+** | host app (uses `Sketchup.resize_viewport` API) | from sketchup.com |
| **Hammerspoon** | event capture, replay, window mgmt, capture | `brew install --cask hammerspoon` |
| **ffmpeg + ffprobe** | mp4 post-processing (crop / scale / encode) | `brew install ffmpeg` |
| **screencapture** | built-in macOS — used for region recording | (preinstalled) |

## Permissions

Required in **System Settings → Privacy & Security**:

| Permission | Target | Why |
|---|---|---|
| Accessibility | Hammerspoon | mouse + keyboard capture/replay, window resize |
| Screen Recording | Hammerspoon | screen recording for replay capture |
| Input Monitoring | Hammerspoon (if prompted) | global event tap reliability |

## SketchUp side

The bundled **SDR Companion** plugin must be enabled inside SketchUp:

1. Open SketchUp → **Window → Extension Manager**
2. Find **SDR Companion** in the list and toggle **Enable** if not already on
3. Restart SketchUp once
