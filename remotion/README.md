# Bytopolis — Remotion video

Assembles the Bytopolis demo: an animated title, lower-third captions timed to
[`../DEMO_SCRIPT.md`](../DEMO_SCRIPT.md), a programmatic intro/outro, and slots for your
**Screen Studio** recordings. It renders end-to-end **with animated placeholders**, so you
can preview the whole thing before recording a single clip.

## Quick start

```sh
cd remotion
npm install
npm run dev        # opens Remotion Studio — scrub the whole 2-min timeline
```

You'll see every scene as a branded placeholder card (Scene NN + the action + the caption).
Nothing else needed to preview.

## Drop in your recordings

1. Export each scene from Screen Studio as **MP4 (H.264)**.
2. Put them in `public/` as `scene01.mp4 … scene12.mp4` (scene 13 is the generated outro).
3. In `src/config.ts` set `USE_PLACEHOLDERS = false`.
4. (Optional) add a voiceover at `public/vo.m4a` and set `HAS_VO = true`.

Trim each clip to about its scene length (see `src/scenes.ts` / `DEMO_SCRIPT.md`), or edit
`durationInFrames` in `src/scenes.ts` to match the exact length of your clips — the
composition length and caption fades recompute automatically.

> Tip: Screen Studio already adds zoom + cursor polish, so keep those recordings clean and
> let Remotion own the titles, captions, and transitions. Don't burn captions in Screen
> Studio — this project draws them.

## Render

```sh
npm run render          # → out/bytopolis-demo.mp4  (1920×1080)
npm run render:social   # → out/bytopolis-social.mp4 (1080×1080 short cut)
npm run still           # → out/poster.png (thumbnail)
```

## Structure

```
src/
  Root.tsx              # registers BytopolisDemo (16:9) + BytopolisSocial (1:1)
  BytopolisVideo.tsx    # sequences scenes, VO audio, optional subtitles
  scenes.ts             # the shot list as data (edit timings/captions here)
  theme.ts              # palette pulled from the app's CityScene
  config.ts             # USE_PLACEHOLDERS / HAS_VO / SHOW_SUBTITLES flags
  components/
    TitleOverlay.tsx    # big "Bytopolis" wordmark over the opener
    Caption.tsx         # lower-third pill
    SceneSlot.tsx       # real clip OR placeholder card
    Outro.tsx           # closing card
    Skyline.tsx         # deterministic animated skyline (title/outro/placeholder bg)
public/                 # your recordings go here (git-ignored)
```

## Customizing

- **Change wording / timing:** edit `src/scenes.ts` — one object per scene.
- **Colors / font:** `src/theme.ts`.
- **Burned-in subtitles** (for silent autoplay): `SHOW_SUBTITLES = true` in `src/config.ts`.
- **Add/remove a scene:** add an entry to `scenes` and a `sceneNN.mp4`; totals update on their own.

Requires Node 18+. Remotion renders via headless Chromium (downloaded on first render).
