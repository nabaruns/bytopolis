import React from "react";
import { useCurrentFrame } from "remotion";
import { accents } from "../theme";

/** A deterministic animated city skyline for title/outro/placeholder backgrounds.
 *  Uses seeded sin() (no Math.random / Date) so every render is identical. */
export const Skyline: React.FC<{ count?: number; base?: number }> = ({
  count = 28,
  base = 0.5,
}) => {
  const frame = useCurrentFrame();
  return (
    <div
      style={{
        position: "absolute",
        inset: 0,
        display: "flex",
        alignItems: "flex-end",
        gap: 8,
        padding: "0 40px",
      }}
    >
      {Array.from({ length: count }).map((_, i) => {
        const seed = Math.abs((Math.sin(i * 12.9898) * 43758.5453) % 1);
        const height = 160 + seed * 560;
        const sway = Math.sin(frame / 42 + i) * 7;
        const c = accents[i % accents.length];
        return (
          <div
            key={i}
            style={{
              flex: 1,
              height: height + sway,
              background: `linear-gradient(${c}, ${c}00)`,
              borderRadius: "6px 6px 0 0",
              opacity: base,
            }}
          />
        );
      })}
    </div>
  );
};
