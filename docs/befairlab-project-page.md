# Project page draft for befairlab.com

Drop these values into `/admin` → New Project. Fields below match
`CONTENT-GUIDE.md`. Voice: first-person plural, plain, AI clearly named.

---

## Common fields

| Field | Value |
|---|---|
| `title` | Fair SketchUp Demo Recorder |
| `slug` | fair-sketchup-demo-recorder |
| `subtitle` | Pixel-perfect viewport or whole-window capture, robot-path replay, YouTube + Reels in one take. |
| `type` | Tool |
| `status` | Beta |
| `displayDate` | 2026-05-18 |
| `shortDescription` | macOS tool for SketchUp demo videos. Captures the model viewport at exact target pixels (or the whole window), records clicks, replays as smooth robot motion, outputs YouTube + Reels mp4 from one take. |
| `tags` | macos, hammerspoon, sketchup, automation, ai-built, video |
| `icon` | upload `befairlab-icon.svg` (in this folder) |
| `cta.primary` | `{ label: "Source on GitHub", url: "https://github.com/BeFairLab/sketchup-demo-recorder" }` |
| `cta.secondary[]` | `[ { label: "Quickstart", url: "https://github.com/BeFairLab/sketchup-demo-recorder/blob/main/QUICKSTART.md" }, { label: "How-to", url: "https://github.com/BeFairLab/sketchup-demo-recorder/blob/main/HOWTO.md" } ]` |
| `size` | `md` (or `lg` if it should pop on the home mosaic) |
| `highlightStyle` | `peach` |
| `showOnHome` | yes |
| `seo.title` | Fair SketchUp Demo Recorder — robot-path replay + auto-crop |
| `seo.description` | Open-source Hammerspoon tool by Fair Lab for SketchUp demo videos. Record clicks, replay as smooth robot motion, auto-crop YouTube + Reels mp4. |
| `seo.ogImage` | upload a 1200×630 of the timeline UI (see screenshots below) |

---

## Body — block sequence

> Each row below is one block. Items render top-to-bottom inside a block.

### Block 1 — `What it is`

- `description`: A small recorder that sits in Hammerspoon and lets us record + replay clicks in SketchUp, then save the take as a clean video.
- items:
  - `text` —
    > **Fair SketchUp Demo Recorder** is a macOS tool we built to make SketchUp demo videos repeatable. Click through the demo once. The tool stores every event. Replay any time, capture the screen, and end up with a clean mp4 — including one YouTube cut and one Reels cut from the same take, if you want.
  - `image` — hero shot of the timeline tab with events laid out, retina (see screenshots § 1).

### Block 2 — `Why we built it`

- items:
  - `text` —
    > We make a lot of short demos for our paid SketchUp extensions. Each one used to mean: open SketchUp, screen-record, click through the script, redo when the cursor jittered, export, crop for vertical, redo when the take ran too long. Hours of work to make 20 seconds of video.
    >
    > This tool collapses that loop. Record once. Edit the click timing as plain numbers in a timeline. Replay as smooth, straight-line cursor motion. Capture. If you set up the **Universal** preset, you get both a 16:9 and a 9:16 video from one capture.

### Block 3 — `Viewport or Window mode`

- `description`: One toggle that decides whether the recording captures the clean 3D model area or the whole SketchUp window.
- items:
  - `text` —
    > Every preset chooses one of two capture modes:
    >
    > **Viewport (model area)** — the recorder uses SketchUp's own `Sketchup.resize_viewport(model, w, h)` API to size the model area to *exactly* the target pixel dimensions (e.g. 1920×1080). The capture region locks onto that area only. No title bar, no toolbar, no panels, no menu. The output mp4 is pure 3D content, frame-perfect at the requested resolution.
    >
    > **Window** — the whole SketchUp window is resized to the target W×H and the capture region matches the full window frame. Toolbars, the side panels, and the status bar all end up in the video. Use this for tutorials where you need to show "click *this* button".
    >
    > This is the feature most other screen-record-then-crop tools don't give you. You don't shoot in 4K and crop down hoping the bezel didn't drift; you set the viewport once, hit Apply, and SketchUp resizes itself to make the math exact.
  - `image` — side-by-side: Viewport mode mp4 frame (clean model) vs Window mode mp4 frame (full SU UI). Same camera, same model. Caption: "Same scene, two modes. Pick what your video needs."

### Block 4 — `Tour`

- `description`: The recorder is four tabs.
- items:
  - `image` — Timeline tab (with a recorded sequence visible). Caption: "Timeline · click pause chips to edit milliseconds; click events for delete / skip / insert pause / comment."
  - `image` — Preset Settings → Viewport. Caption: "One preset bundles viewport size, playback behaviour, and output settings."
  - `image` — Preset Settings → Playback (auto-path on, click circles + keystrokes on). Caption: "Auto-path replaces recorded jitter with a straight-line robot cursor at your speed and easing."
  - `image` — Preset Settings → Output (universal + auto-crop). Caption: "Universal presets capture a square area; ffmpeg crops YouTube and Reels variants automatically."
  - `image` — Manage tab. Caption: "List, rename, export, delete presets and timelines."

### Block 5 — `Auto-path, click circles, keystrokes`

- items:
  - `text` —
    > Auto-path drops every recorded `mouse_move` between two clicks and substitutes smooth cursor interpolation — configurable speed in pixels/second, with quintic ease-in-out by default. Click + drag is preserved (we only drop moves *between* clicks, not *during* drags).
    >
    > Click circles render an expanding ring at every click, in the captured video. The keystroke overlay shows a `⌘ Z` style pill in the corner — using a fixed English ANSI keymap so it reads the same whether the input layout was Cyrillic, Hebrew, anything.
  - `video` — short clip (3-5 s) of replay with circles + keystrokes visible. Caption: "Replay with click circles and keystroke overlay, captured straight from screencapture."

### Block 6 — `Universal preset + auto-crop`

- items:
  - `text` —
    > The Universal presets record a square area. After capture, ffmpeg auto-centres a 16:9 crop for YouTube and a 9:16 crop for Reels. The overlay shows both safe zones during recording so you can align your subject inside the intersection.
    >
    > For sizes the display can't fit (4K, 2880-tall Reels) we removed those presets — SketchUp clamps the viewport and you end up with off-centre crops. **Universal Custom** lets you set the source square + any crop targets.
  - `image` — overlay screenshot showing the two safe zones inside a 1920×1920 square.
  - `image` — side-by-side: full source mp4, YouTube crop, Reels crop. Caption: "One capture, three files."

### Block 7 — `How it talks to SketchUp`

- items:
  - `text` —
    > **Hammerspoon** does the heavy lifting: event capture, replay, window sizing, screen recording, the local HTTP bridge that serves the HTML UI to a `hs.webview` window.
    >
    > A tiny Ruby companion plugin lives inside SketchUp. It polls a file in `/tmp/`. When Hammerspoon needs to set the viewport to an exact pixel size, it writes a JSON command; the companion calls `Sketchup.resize_viewport(model, w, h)`. No sockets, no permissions to grant on the SketchUp side beyond enabling the extension.
  - `image` — small architecture diagram (optional; defer if no time).

### Block 8 — `Let's be fair: how AI helped`

- items:
  - `text` —
    > This project was paired with **Claude Sonnet 4.6 (1M context)**. The human held the design direction — what should the UI feel like, which workflows matter, what is good enough to ship. Claude wrote the bulk of the Lua, JS, Ruby, and ffmpeg pipelines.
    >
    > Concrete examples of the split:
    >
    > - **Human**: decide that timelines are linked to presets, not the other way around. Decide that the Preset Settings tab is a pure editor with explicit save. Decide which presets to remove because they don't fit on a MacBook display.
    > - **AI**: write `recorder.lua`, `replayer.lua`, the file-IPC bridge, the screencapture wrapper with the ffmpeg fallback, the post-process pipeline with adaptive ffmpeg crop expressions that survived a real "centre crop is off by 24 pixels" bug.
    > - **Together**: every UI iteration — propose → screenshot → critique → adjust. The current tab structure is the fourth or fifth attempt.
    >
    > We didn't ship anything until the human had run the full take end-to-end. The AI didn't know the SketchUp pixel-vs-point Retina trap until the human saw a 480×270 region when it should have been 960×540 and reported it. The AI fixed it in the next message.

### Block 9 — `Get it`

- items:
  - `text` —
    > MIT-licensed. Source on GitHub: <https://github.com/BeFairLab/sketchup-demo-recorder>.
    >
    > See [QUICKSTART.md](https://github.com/BeFairLab/sketchup-demo-recorder/blob/main/QUICKSTART.md) for a 5-minute install, [HOWTO.md](https://github.com/BeFairLab/sketchup-demo-recorder/blob/main/HOWTO.md) for an end-to-end demo, and [REQUIREMENTS.md](https://github.com/BeFairLab/sketchup-demo-recorder/blob/main/REQUIREMENTS.md) for system needs.
    >
    > Tested on macOS 15 + SketchUp 2026. Hammerspoon, ffmpeg, and the SDR Companion plugin are the only dependencies.

---

## relatedBlogSlugs

Leave empty for first publish. When we ship demo videos that USE this tool, link them back here.
