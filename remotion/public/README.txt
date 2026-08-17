Drop your Screen Studio exports here, named to match the scenes:

  scene01.mp4 … scene12.mp4   (scene 13 is the programmatic outro)
  vo.m4a                      (optional voiceover for the full cut)

Then in src/config.ts:
  USE_PLACEHOLDERS = false    (use the clips instead of the placeholder cards)
  HAS_VO = true               (if you added vo.m4a)

Scene durations are in src/scenes.ts. Trim each recording to roughly the scene
length in DEMO_SCRIPT.md, or adjust durationInFrames there to match your clips.

These files are git-ignored (they're large) — they live only on your machine.
