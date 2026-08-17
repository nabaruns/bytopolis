# Bytopolis — Demo Video Script

**Runtime:** ~2:00 · **Format:** 1920×1080 (or 2560×1600 native), 30 fps · **Tone:** confident, fast, a little playful.
**One-line pitch:** *"Bytopolis turns your disk into a city you can walk through, clean up, and put AI agents to work in."*

---

## Before you record (prep checklist)

- [ ] Point the app at a folder with real substance and at least one **git repo** inside — e.g. `~/work`. Repos become "facilities," so you need one for the workers scene.
- [ ] **Pre-scan once** so the index is warm and the demo shows *instant* browsing (no waiting on `du`). Re-open the app after — it loads from cache immediately.
- [ ] Configure the **Assistant**: set an Anthropic/OpenRouter key (Assistant → gear) so the streaming reply is snappy. If demoing on-device, pre-download the local model.
- [ ] Have **one worker task** in mind that's safe and fast, e.g. Plan mode: *"List the 3 biggest files and suggest a .gitignore."*
- [ ] Clean desktop, hide clutter, set wallpaper neutral. Decide **light or dark** — the script shows a quick toggle, so either start is fine.
- [ ] Window size ~1440×900 so text is legible when scaled.
- [ ] Close other noisy apps (no notification banners). Turn on Do Not Disturb.

---

## Shot list

> Columns: **#** · **⏱ time** · **On-screen action** · **Voiceover (VO)** · **Lower-third / caption**

| # | ⏱ | Action (what you do) | Voiceover | Caption |
|---|-----|----------------------|-----------|---------|
| 1 | 0:00–0:06 | Cold open on the **3D City** already loaded, slowly orbiting. Buildings, a glowing beacon over the newest file. | "This is everything on your disk — as a city." | **Bytopolis** |
| 2 | 0:06–0:14 | Cut to the **List** tab. Point at total size + columns (Size, Kind, Modified, Items) and the ⚡️ *Indexed* badge. | "One scan maps the whole tree. After that, every folder opens instantly — it's all indexed." | *Scan once. Browse instantly.* |
| 3 | 0:14–0:22 | Click into a big folder, then back. Show the footer **index cache** + **Clear Cache**. | "Drill in, jump back — no re-scanning. The index even survives relaunches, with a size cap so it never bloats." | |
| 4 | 0:22–0:32 | Open the **Reclaim** sheet. Hover the keep/caution/safe dots. Click **Select Safe**, show the reclaimable total. | "Bytopolis classifies caches, build output, node_modules, DerivedData — and tells you what's safe to clear, offline." | *Reclaim — 12.4 GB safe* |
| 5 | 0:32–0:42 | Open the **Assistant** pane. Type *"What can I safely delete here?"* — let the reply **stream in**. | "Ask in plain English. It only sees metadata for the folder you're in — never file contents — and streams its answer." | *Assistant · scoped to this folder* |
| 6 | 0:42–0:48 | Click the **history** clock icon → reopen a past chat. | "Every conversation is saved and resumable." | |
| 7 | 0:48–0:58 | Switch to **City**. **Double-click** a district in the "This level" list — camera **flies into** it; the folder's **popup** appears. | "Now the fun part. Double-click to fly into any folder…" | *Double-click to enter* |
| 8 | 0:58–1:06 | Toggle **System appearance** light↔dark (or show both). Select a building — it highlights **white**. | "Day or night, it follows your Mac's theme." | |
| 9 | 1:06–1:16 | Click a **repo facility** (walled plot). Popup shows branch + remote + **Start worker**. | "Git repos become facilities — and you can put an AI coding agent to work inside one." | *Repos = facilities* |
| 10 | 1:16–1:30 | **Start worker** → pick Claude Code, **Plan (read-only)**, paste the task. A **Lego-style figure** appears on the facility; status bulb pulses **green (working)**, then **yellow (waiting)**. | "It runs Claude Code or Codex headlessly in the repo — and you watch it live, as a little worker on the map." | *working… → waiting for response…* |
| 11 | 1:30–1:40 | Open the worker panel; show streaming transcript. Point at the **roster** (left) with the colored status dot. When it ends, dot turns **teal** + "N files changed." | "Working, waiting, done, or stopped — you can see every session's state at a glance. Nothing runs without you, and edits show up in git." | *Plan mode · read-only* |
| 12 | 1:40–1:50 | Back to List. Select a junk folder → **trash** button → confirmation dialog (path + size) → **Move to Trash**. | "And when you're ready to clean up — move to Trash safely, or delete permanently, always with a confirmation." | *Reversible by default* |
| 13 | 1:50–2:00 | Pull back to the orbiting City. Fade to title card. | "Bytopolis. See your disk. Reclaim it. Build in it." | **Bytopolis** · github.com/nabaruns/bytopolis |

---

## Voiceover — clean read (for a VO artist or TTS)

1. "This is everything on your disk — as a city."
2. "One scan maps the whole tree. After that, every folder opens instantly — it's all indexed."
3. "Drill in, jump back — no re-scanning. The index even survives relaunches, with a size cap so it never bloats."
4. "Bytopolis classifies caches, build output, node_modules, DerivedData — and tells you what's safe to clear, completely offline."
5. "Ask in plain English. It only sees metadata for the folder you're in — never your file contents — and streams its answer."
6. "Every conversation is saved and resumable."
7. "Now the fun part. Double-click to fly into any folder."
8. "Day or night, it follows your Mac's theme."
9. "Git repos become facilities — and you can put an AI coding agent to work inside one."
10. "It runs Claude Code or Codex headlessly in the repo — and you watch it live, as a little worker on the map."
11. "Working, waiting, done, or stopped — you can see every session's state at a glance. Nothing runs without you, and edits show up in git."
12. "And when you're ready to clean up — move to Trash safely, or delete permanently, always with a confirmation."
13. "Bytopolis. See your disk. Reclaim it. Build in it."

---

## Pacing notes

- Keep the camera **always subtly moving** in City shots — a slow orbit reads better than a static frame.
- Scenes 10–11 (workers) are the hero moment. If the agent finishes too fast to show the green→yellow→teal arc, pick a slightly bigger task, or **trim in post** to keep each state on screen ~2 s.
- Cut on action (click → cut) to keep energy up. Target ~13 cuts in 2 minutes.
- No music over the VO reads if using TTS; add a light electronic bed at ~-18 dB otherwise.

---

## Recording cheat-sheet (macOS, no extra apps)

**Screen record a region/window** — press **⌘⇧5**, choose *Record Selected Portion* or a window, set a 5-second timer, record. Save as `.mov`.

**Or from the terminal** (interactive UI; runs in your shell):

```sh
# Full interactive capture UI (pick region/window, then click record):
screencapture -i -v ~/Desktop/bytopolis-demo.mov
```

**Trim / concatenate / export** with ffmpeg (`brew install ffmpeg`):

```sh
# Trim a clip (from 3s, 12s long), re-encode clean:
ffmpeg -ss 3 -i raw.mov -t 12 -c:v libx264 -crf 18 -pix_fmt yuv420p scene07.mp4

# Scale to 1080p:
ffmpeg -i in.mov -vf "scale=1920:-2:flags=lanczos" -c:v libx264 -crf 18 -pix_fmt yuv420p out1080.mp4

# Make a shareable GIF of one moment (e.g. the worker figure), 12 fps, 900px wide:
ffmpeg -ss 76 -t 8 -i raw.mov -vf "fps=12,scale=900:-1:flags=lanczos" -loop 0 worker.gif

# Stitch scenes in order (create files.txt: one `file 'sceneNN.mp4'` line each):
ffmpeg -f concat -safe 0 -i files.txt -c copy bytopolis-demo.mp4
```

**Add the voiceover track** (recorded separately as `vo.m4a`):

```sh
ffmpeg -i bytopolis-demo.mp4 -i vo.m4a -c:v copy -c:a aac -shortest final.mp4
```

**Tips**
- Record at the display's native resolution, then scale down once at the end — sharper than recording small.
- Hide the cursor when it's not the subject; enable **Show mouse clicks** (in ⌘⇧5 *Options*) for the click-through moments.
- For a silent product loop (e.g. website hero), export the City orbit + a couple of drill-ins as a 10-second muted GIF/MP4.

---

## 15-second cut (for social)

Scenes **1 → 7 → 10 → 13**: cold-open city → fly into a folder → a worker figure lights up green → title card. Same VO lines 1, 7, 10 (trimmed), 13.
