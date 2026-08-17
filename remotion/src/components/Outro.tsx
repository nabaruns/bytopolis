import React from "react";
import { AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { theme } from "../theme";
import { Skyline } from "./Skyline";

/** Programmatic closing card: skyline + wordmark + tagline + repo URL. */
export const Outro: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const pop = spring({ frame, fps, config: { damping: 200 } });
  const scale = interpolate(pop, [0, 1], [0.94, 1]);
  const op = interpolate(frame, [0, 18], [0, 1], { extrapolateRight: "clamp" });

  return (
    <AbsoluteFill
      style={{
        background: `radial-gradient(1200px 800px at 50% 30%, #171b28, ${theme.bg})`,
        justifyContent: "center",
        alignItems: "center",
      }}
    >
      <Skyline base={0.5} />
      <div style={{ textAlign: "center", opacity: op, transform: `scale(${scale})` }}>
        <div
          style={{
            fontFamily: theme.font,
            fontWeight: 800,
            fontSize: 132,
            color: theme.ink,
            letterSpacing: -2,
            textShadow: "0 10px 50px rgba(0,0,0,0.55)",
          }}
        >
          Bytopolis
        </div>
        <div style={{ fontFamily: theme.font, fontSize: 34, color: theme.sub, marginTop: 8 }}>
          See your disk. Reclaim it. Build in it.
        </div>
        <div style={{ fontFamily: theme.font, fontSize: 28, color: theme.teal, marginTop: 28 }}>
          github.com/nabaruns/bytopolis
        </div>
      </div>
    </AbsoluteFill>
  );
};
