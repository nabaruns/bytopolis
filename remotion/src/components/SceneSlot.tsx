import React from "react";
import { AbsoluteFill, OffthreadVideo, staticFile } from "remotion";
import { Scene } from "../scenes";
import { theme } from "../theme";
import { USE_PLACEHOLDERS } from "../config";
import { Skyline } from "./Skyline";

/** Renders the real Screen Studio clip, or a branded placeholder card when clips
 *  aren't in place yet (so the whole video previews from frame one). */
export const SceneSlot: React.FC<{ scene: Scene }> = ({ scene }) => {
  if (scene.src && !USE_PLACEHOLDERS) {
    return (
      <AbsoluteFill style={{ background: theme.bg }}>
        <OffthreadVideo
          src={staticFile(scene.src)}
          style={{ width: "100%", height: "100%", objectFit: "cover" }}
        />
      </AbsoluteFill>
    );
  }

  const num = String(scene.id).padStart(2, "0");
  return (
    <AbsoluteFill
      style={{ background: `radial-gradient(1200px 720px at 50% 18%, #1a1f2e, ${theme.bg})` }}
    >
      <Skyline base={0.32} />
      <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", padding: 120 }}>
        <div style={{ fontFamily: theme.font, textAlign: "center" }}>
          <div style={{ fontSize: 26, letterSpacing: 6, color: theme.sub, textTransform: "uppercase" }}>
            Scene {num}
          </div>
          <div style={{ fontSize: 44, color: theme.ink, margin: "16px 0 20px", maxWidth: 1200, lineHeight: 1.2 }}>
            {scene.action}
          </div>
          <div style={{ fontSize: 24, color: theme.clay }}>
            drop recording → public/{scene.src ?? `scene${num}.mp4`}
          </div>
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
