export const FPS = 30;
const s = (sec: number) => Math.round(sec * FPS);

export type Scene = {
  id: number;
  /** Clip in public/, e.g. "scene02.mp4". Used when USE_PLACEHOLDERS is false. */
  src?: string;
  /** Lower-third caption. */
  caption: string;
  /** Short action label shown on the placeholder card. */
  action: string;
  /** Voiceover line (reference + optional burned-in subtitle). */
  vo: string;
  durationInFrames: number;
  /** Overlay the big Bytopolis title instead of a caption. */
  bigTitle?: boolean;
  /** Render the programmatic outro card instead of a clip slot. */
  outro?: boolean;
};

// Timings mirror DEMO_SCRIPT.md (total = 120s @ 30fps = 3600 frames).
export const scenes: Scene[] = [
  { id: 1, src: "scene01.mp4", durationInFrames: s(6), bigTitle: true,
    action: "3D City, slow orbit + beacon over the newest file",
    caption: "Bytopolis",
    vo: "This is everything on your disk — as a city." },
  { id: 2, src: "scene02.mp4", durationInFrames: s(8),
    action: "List tab — total size, columns, ⚡️ Indexed badge",
    caption: "Scan once. Browse instantly.",
    vo: "One scan maps the whole tree. After that, every folder opens instantly — it's all indexed." },
  { id: 3, src: "scene03.mp4", durationInFrames: s(8),
    action: "Drill in / back · index cache + Clear Cache footer",
    caption: "The index persists across launches.",
    vo: "Drill in, jump back — no re-scanning. The index even survives relaunches, with a size cap so it never bloats." },
  { id: 4, src: "scene04.mp4", durationInFrames: s(10),
    action: "Reclaim sheet — keep/caution/safe dots, Select Safe",
    caption: "Reclaim — offline, deterministic.",
    vo: "Bytopolis classifies caches, build output, node_modules, DerivedData — and tells you what's safe to clear, completely offline." },
  { id: 5, src: "scene05.mp4", durationInFrames: s(10),
    action: "Assistant — ask, reply streams in token by token",
    caption: "Ask in plain English — it streams.",
    vo: "Ask in plain English. It only sees metadata for the folder you're in — never your file contents — and streams its answer." },
  { id: 6, src: "scene06.mp4", durationInFrames: s(6),
    action: "History clock icon → reopen a past chat",
    caption: "Every chat is saved & resumable.",
    vo: "Every conversation is saved and resumable." },
  { id: 7, src: "scene07.mp4", durationInFrames: s(10),
    action: "City — double-click a district, camera flies in, popup appears",
    caption: "Double-click to fly into any folder.",
    vo: "Now the fun part. Double-click to fly into any folder." },
  { id: 8, src: "scene08.mp4", durationInFrames: s(8),
    action: "Toggle light/dark · selected building highlights white",
    caption: "Follows your Mac's theme.",
    vo: "Day or night, it follows your Mac's theme." },
  { id: 9, src: "scene09.mp4", durationInFrames: s(10),
    action: "Click a repo facility — branch, remote, Start worker",
    caption: "Git repos become facilities.",
    vo: "Git repos become facilities — and you can put an AI coding agent to work inside one." },
  { id: 10, src: "scene10.mp4", durationInFrames: s(14),
    action: "Start worker (Plan) — Lego figure, bulb green → yellow",
    caption: "Claude Code / Codex, running live.",
    vo: "It runs Claude Code or Codex headlessly in the repo — and you watch it live, as a little worker on the map." },
  { id: 11, src: "scene11.mp4", durationInFrames: s(10),
    action: "Worker panel transcript + roster dot turns teal (done)",
    caption: "Working · waiting · done · stopped.",
    vo: "Working, waiting, done, or stopped — you can see every session's state at a glance. Nothing runs without you, and edits show up in git." },
  { id: 12, src: "scene12.mp4", durationInFrames: s(10),
    action: "Trash button → confirmation (path + size) → Move to Trash",
    caption: "Reversible by default.",
    vo: "And when you're ready to clean up — move to Trash safely, or delete permanently, always with a confirmation." },
  { id: 13, durationInFrames: s(10), outro: true,
    action: "Outro card",
    caption: "Bytopolis",
    vo: "Bytopolis. See your disk. Reclaim it. Build in it." },
];

// A short social cut (scenes 1 → 7 → 10 → 13).
export const socialScenes: Scene[] = [
  { ...scenes[0], durationInFrames: s(3) },
  { ...scenes[6], durationInFrames: s(4) },
  { ...scenes[9], durationInFrames: s(5) },
  { ...scenes[12], durationInFrames: s(3) },
];

export const totalFrames = (list: Scene[]) =>
  list.reduce((a, sc) => a + sc.durationInFrames, 0);
