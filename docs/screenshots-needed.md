# Screenshots needed for befairlab.com project page

Capture all at retina (so the long edge is ≥ 1600 px, per CONTENT-GUIDE
§ 3). Format: PNG with the macOS window shadow trimmed but the window
chrome (title bar) intact — keeps the "real app" feel.

| # | Block | Filename suggestion | Capture |
|---|---|---|---|
| 1 | Hero (Block 1) | `sdr-01-hero-timeline.png` | Timeline tab. A recorded sequence (~12 events) visible. Pause chips at varied values. Highlight one event with a comment so the bold "— click toolbar X-Min" is visible. SU isn't needed in the shot — just the recorder. 1600 px wide minimum. |
| 2 | Tour: Timeline (Block 3) | `sdr-02-tour-timeline.png` | Same tab, **scrolled to show the event grid + Linked preset row + dirty badge**. Stage a sequence with at least one `pause` chip and one `skipped` chip so the styling is visible. |
| 3 | Tour: Viewport (Block 3) | `sdr-03-tour-preset-viewport.png` | Preset Settings → Viewport card. Show a Universal Custom selection with the editable YouTube / Reels W×H rows visible. `region: …` populated. |
| 4 | Tour: Playback (Block 3) | `sdr-04-tour-preset-playback.png` | Preset Settings → Playback card with auto-path ON, speed 1000, easing Ease in-out, click circles ON, keystrokes ON, both delays checked at 1000 ms. |
| 5 | Tour: Output (Block 3) | `sdr-05-tour-preset-output.png` | Preset Settings, two Output cards visible together (non-universal + universal), Auto-crop checkbox ON, both Resolution dropdowns showing a chosen preset. |
| 6 | Tour: Manage (Block 3) | `sdr-06-tour-manage.png` | Manage tab with 3-5 preset rows + 3-5 timeline rows. Each timeline row shows the `(N events, preset: …)` meta. |
| 6.5 | Viewport vs Window mode (Block 3) | `sdr-065-viewport-vs-window.png` | Side-by-side composite: left frame = an mp4 captured in `Viewport` mode (clean 3D model only, no SU chrome); right frame = same scene captured in `Window` mode (full SU window with toolbars + status bar visible). Caption: "Same scene, two capture modes." |
| 7 | Overlay + safe zones (Block 6) | `sdr-07-overlay-safe-zones.png` | Screenshot of SketchUp with the recording overlay visible — red outer frame + the two safe-zone rectangles (yellow YouTube + red Reels) overlaid on a real SU scene. Use the Universal 1920×1920 preset so both zones fit cleanly. |
| 8 | Three-file output (Block 6) | `sdr-08-three-outputs.png` | Finder window OR collage showing the source `.mov` and the two derivative `_youtube_*.mp4` + `_reels_*.mp4` files side by side. A composite is fine. |
| 9 | OG / social image | `sdr-og-1200x630.png` | 1200×630. Recommended layout: timeline UI on the left, the words "Fair SketchUp Demo Recorder · open source, MIT" on the right. Use the peach accent. |

## Optional but nice

| # | Block | Filename | Capture |
|---|---|---|---|
| A | Block 4 (auto-path) | `sdr-A-replay.mp4` | 3-5 second screen recording of `Play timeline (no capture)` running — click circles + keystroke pill visible. Encode H.264, under 5 MB. |
| B | Block 6 (architecture) | `sdr-B-arch.svg` | Simple diagram: `Hammerspoon (Lua) ⇄ HTTP ⇄ Webview UI` + `Hammerspoon ⇄ /tmp/sdr_cmd.json ⇄ SDR Companion (Ruby in SketchUp)`. Could draw in Figma or omit. |
| C | About tab | `sdr-C-about.png` | Shows the About card with the four Fair Lab links + Documentation card. |

## How to capture

```bash
# whole window (cmd+shift+4 then space, click window)
# OR scripted with retina + window shadow stripped:
screencapture -x -o -w sdr-XX-name.png      # -o drops the shadow
```

For the SU overlay shot (#7) you'll need to **Apply** the preset, **Show
overlay**, then arrange SketchUp + recorder so the overlay is captured —
cmd+shift+5 then drag the region.

All shots go to `~/Code/befairlab/<wherever uploads live>` or upload via
`/admin/files` and paste the URL into the block.
