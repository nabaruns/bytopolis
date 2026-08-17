import React from "react";
import { AbsoluteFill, Audio, interpolate, Sequence, staticFile, useCurrentFrame } from "remotion";
import { Scene, scenes as fullScenes, socialScenes } from "./scenes";
import { theme } from "./theme";
import { HAS_VO, VO_FILE, SHOW_SUBTITLES } from "./config";
import { SceneSlot } from "./components/SceneSlot";
import { Caption } from "./components/Caption";
import { TitleOverlay } from "./components/TitleOverlay";
import { Outro } from "./components/Outro";

const SceneView: React.FC<{ scene: Scene }> = ({ scene }) => {
  const frame = useCurrentFrame();
  const fade = interpolate(frame, [0, 12], [0, 1], { extrapolateRight: "clamp" });
  if (scene.outro) return <Outro />;
  return (
    <AbsoluteFill style={{ opacity: fade }}>
      <SceneSlot scene={scene} />
      {scene.bigTitle ? (
        <TitleOverlay />
      ) : (
        <Caption text={scene.caption} total={scene.durationInFrames} />
      )}
      {SHOW_SUBTITLES && !scene.bigTitle && <Subtitle text={scene.vo} />}
    </AbsoluteFill>
  );
};

const Subtitle: React.FC<{ text: string }> = ({ text }) => (
  <div style={{ position: "absolute", left: 0, right: 0, bottom: 28, textAlign: "center" }}>
    <span
      style={{
        fontFamily: theme.font,
        fontSize: 26,
        color: theme.ink,
        background: "rgba(0,0,0,0.45)",
        padding: "6px 14px",
        borderRadius: 8,
      }}
    >
      {text}
    </span>
  </div>
);

export const BytopolisVideo: React.FC<{ social?: boolean }> = ({ social = false }) => {
  const list = social ? socialScenes : fullScenes;
  let from = 0;
  return (
    <AbsoluteFill style={{ background: theme.bg }}>
      {HAS_VO && !social && <Audio src={staticFile(VO_FILE)} />}
      {list.map((scene) => {
        const start = from;
        from += scene.durationInFrames;
        return (
          <Sequence key={scene.id} from={start} durationInFrames={scene.durationInFrames}>
            <SceneView scene={scene} />
          </Sequence>
        );
      })}
    </AbsoluteFill>
  );
};
