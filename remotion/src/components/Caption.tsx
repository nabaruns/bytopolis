import React from "react";
import { interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { theme } from "../theme";

/** Lower-third caption pill that springs in and fades out at the end of its scene. */
export const Caption: React.FC<{ text: string; total: number }> = ({ text, total }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const enter = spring({ frame, fps, config: { damping: 200 } });
  const x = interpolate(enter, [0, 1], [-48, 0]);
  const inOp = interpolate(frame, [0, 12], [0, 1], { extrapolateRight: "clamp" });
  const outOp = interpolate(frame, [total - 16, total], [1, 0], { extrapolateLeft: "clamp" });

  return (
    <div
      style={{
        position: "absolute",
        left: 64,
        bottom: 76,
        opacity: Math.min(inOp, outOp),
        transform: `translateX(${x}px)`,
      }}
    >
      <div
        style={{
          display: "inline-flex",
          alignItems: "center",
          gap: 14,
          background: "rgba(21,24,36,0.86)",
          backdropFilter: "blur(8px)",
          border: "1px solid rgba(255,255,255,0.09)",
          borderRadius: 16,
          padding: "16px 24px",
          boxShadow: "0 12px 40px rgba(0,0,0,0.35)",
        }}
      >
        <div
          style={{
            width: 12,
            height: 12,
            borderRadius: 6,
            background: theme.teal,
            boxShadow: `0 0 14px ${theme.teal}`,
          }}
        />
        <div style={{ fontFamily: theme.font, fontSize: 34, color: theme.ink, fontWeight: 600 }}>
          {text}
        </div>
      </div>
    </div>
  );
};
