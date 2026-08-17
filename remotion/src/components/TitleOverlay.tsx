import React from "react";
import { AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { theme } from "../theme";

/** Big "Bytopolis" wordmark that rises in over the opening shot. */
export const TitleOverlay: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const rise = spring({ frame, fps, config: { damping: 200 } });
  const y = interpolate(rise, [0, 1], [40, 0]);
  const op = interpolate(frame, [4, 20], [0, 1], { extrapolateRight: "clamp" });

  return (
    <AbsoluteFill style={{ justifyContent: "flex-end", padding: 90 }}>
      <div style={{ transform: `translateY(${y}px)`, opacity: op }}>
        <div
          style={{
            fontFamily: theme.font,
            fontWeight: 800,
            fontSize: 128,
            color: theme.ink,
            letterSpacing: -2,
            textShadow: "0 10px 50px rgba(0,0,0,0.55)",
          }}
        >
          Bytopolis
        </div>
        <div style={{ fontFamily: theme.font, fontSize: 36, color: theme.sub, marginTop: 4 }}>
          Your disk, as a city.
        </div>
      </div>
    </AbsoluteFill>
  );
};
