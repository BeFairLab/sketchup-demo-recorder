# How-to: produce a SketchUp demo video

This walks through a single end-to-end take from "blank model" to "mp4 on Desktop".

## 0. One-time setup

See [REQUIREMENTS.md](REQUIREMENTS.md) and [QUICKSTART.md](QUICKSTART.md).

## 1. Open the recorder

Hotkey **⌃⌥⌘V** (Control + Option + Cmd + V) opens the Fair SketchUp Demo Recorder window.

The window stays attached to your screen but does not record itself — its area is automatically excluded from event capture (so clicking buttons in the recorder won't end up in your timeline).

## 2. Pick or create a Preset

A **Preset** = viewport size + playback settings (auto-path, speed, easing, click effects, keystrokes, delays) + output settings (rescale / auto-crop). Presets live in `presets/<name>.json` and can be reused across many timelines.

- In the header: **Preset** dropdown → pick an existing one
- Or in the **Preset settings** tab: **New… (defaults)** → enter name → tweak controls → **Save changes**

Common starter preset for cross-platform demos: **Universal Square 1920×1920** + **Auto-crop → YouTube + Reels mp4**. This captures a 1920×1920 area and post-crops both formats.

## 3. Apply the viewport

Click **Apply to SketchUp** in the header. The SketchUp window is centred on screen and its viewport (model area) is resized so the captured pixel dimensions match the preset.

The `region: ...` line shows the recording rect in logical screen points. Click **Show overlay** to see it as a red rectangle.

## 4. Create or load a Timeline

A **Timeline** = recorded events (clicks, key presses, mouse moves) + a link to the preset to use during replay. Files: `sequences/<name>.json`.

- **Timeline** tab → **New… (prompt + save)** → enter name
- The active timeline shows above the timeline event list
- Set the **Linked preset** dropdown so this timeline auto-loads its preset later

## 5. Record clicks

1. Switch to SketchUp and put it in the desired start state (scene open, camera positioned, nothing selected)
2. Hotkey **⌃⌥⌘R** OR click **● Record clicks (fresh)** on the Recording tab
3. Perform the demo: clicks, drags, key presses
4. Hotkey **⌃⌥⌘R** OR click again to stop
5. Recording UI / menubar / hotkey actions themselves are NEVER recorded — only your SketchUp-side interactions

Timeline tab shows the captured events as chips. Edit pause values inline; click a chip to delete or comment it.

**Continue later:** ⌃⌥⌘E adds more events to the same timeline (preserves what's already there).

## 6. Tweak playback

In **Preset settings → Playback**:

- **Auto-path** drops recorded mouse_moves between clicks and substitutes smooth straight-line cursor travel at the chosen speed and easing — perfect for clean, robotic demo replays.
- **Show click circles** draws an expanding ring at every click (captured in mp4)
- **Show keystrokes** shows a `⌘ Z` style pill in the corner for key presses
- **Pre-delay / Post-delay** add silent buffer at the start / end of capture

Click **Apply auto-path to timeline** on the Timeline tab to permanently strip mouse_moves (so the file matches what auto-path replay would produce).

## 7. Test play (no capture)

**▶ Play (no capture)** runs the sequence in SketchUp without recording video. Use this to verify timing and click positions.

## 8. Record the mp4

**⏺ Record + Replay**:
1. Hides the overlay
2. Starts `screencapture -V` on the region
3. Brings SketchUp to the foreground
4. Replays the sequence with the configured pre/post-delay
5. Lets capture run its natural duration so the mov is flushed cleanly
6. If output settings include rescale or auto-crop, runs `ffmpeg` on the result

Output goes to `~/Desktop/<timeline>_<timestamp>.mov` plus any `_youtube_*.mp4` / `_reels_*.mp4` variants.

## 9. Universal-preset workflow

The **Universal** presets (`1920×1920`, `2160×2160`, or **Universal Custom**) record a square area and post-crop two videos:

- `<name>_youtube_*.mp4` — 16:9 centred crop, rescaled to the YouTube target
- `<name>_reels_*.mp4`  — 9:16 centred crop, rescaled to the Reels target

When you align your SketchUp content, make sure the subject stays within the **intersection** of the two safe zones (visible as overlapping rectangles in the overlay). The intersection is the only area guaranteed to appear in BOTH crops.

For odd dimensions, use **Universal Custom** in the Preset settings — set the source square size and the YouTube / Reels crop targets.

## Common pitfalls

- **mp4 empty / 0 KB**: usually the region exceeded the display; check Hammerspoon Console for `screencapture: region clamped` or `region out of sane bounds` warnings.
- **Replay clicks land in the wrong place**: the SketchUp window moved after recording. Reapply preset (re-centres the window) and replay.
- **Cropped video shows wrong area**: SketchUp clamped the requested viewport height to fit your display. Switch to a smaller universal preset (e.g. `1920×1920` instead of `2160×2160`).
- **Recorder click ends up in timeline**: shouldn't happen after the dead-zone fix; report with Hammerspoon Console dump.
