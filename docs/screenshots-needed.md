# Screenshots — what's done, what's still needed

All assets live under `docs/assets/screenshots/`. Icons under
`docs/assets/icons/`.

## Done

| Block | File | Source |
|---|---|---|
| 1 Hero | `01-timeline.png` | from Desktop dropbox |
| 1 alt (video) | `01-demo.mp4` | from Desktop dropbox |
| 3 Viewport-vs-Window | `03b-mode-viewport.png` + `03c-mode-window.png` (carousel) | Desktop dropbox |
| 4 Tour — Viewport | `03-preset-viewport.png` | Desktop dropbox |
| 4 Tour — Playback | `04-preset-playback.png` | Desktop dropbox |
| 4 Tour — Output nonU | `05-preset-output-nonuniversal.png` | Desktop dropbox |
| 4 Tour — Output Universal | `05b-preset-output-universal.png` | Desktop dropbox |
| 4 Tour — Manage | `06-manage.png` | Desktop dropbox |
| 5 Auto-path effects | `04-replay-effects.gif` | Desktop dropbox |
| 6 Overlay safe zones | `07-overlay-safe-zones.png` | Desktop dropbox |
| Project icon | `docs/assets/icons/extension-icon-*.png` + `.svg` | `skp-extension icons/fair-demo-recorder/` |

## Still needed

| # | Use | Filename suggestion | Spec |
|---|---|---|---|
| OG | `seo.ogImage` | `og-1200x630.png` | 1200×630 PNG. Suggested: timeline screenshot on the left (50%), Title + "Open source · MIT" on the right with the sky-blue accent + the project icon. |
| Tour 7 (optional) | Block 7 architecture | `arch-diagram.svg` | Simple two-arrow flowchart: `Hammerspoon (Lua) ⇄ HTTP ⇄ Webview UI` and `Hammerspoon ⇄ /tmp/sdr_cmd.json ⇄ SDR Companion (Ruby in SketchUp)`. Mono ink (#0c0a09) + hairline strokes per BeFair design system. |
| Universal 8 (optional) | Block 6 collage | `three-outputs.png` | Composite showing the source `.mov` + `_youtube_*.mp4` + `_reels_*.mp4` thumbnails. Caption: "One capture, three files." |

## Capture cheatsheet (for future shots)

```bash
# whole window with shadow stripped, retina:
screencapture -x -o -w sdr-XX-name.png

# region:
screencapture -x -i sdr-XX-name.png
```

All shots must be ≥ 1600 px on the long edge per CONTENT-GUIDE § 3.
Upload via `/admin/files` or paste GitHub-raw URLs while drafting.
