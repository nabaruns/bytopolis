import React from "react";
import { Composition } from "remotion";
import { BytopolisVideo } from "./BytopolisVideo";
import { FPS, scenes, socialScenes, totalFrames } from "./scenes";

export const RemotionRoot: React.FC = () => {
  return (
    <>
      <Composition
        id="BytopolisDemo"
        component={BytopolisVideo}
        durationInFrames={totalFrames(scenes)}
        fps={FPS}
        width={1920}
        height={1080}
        defaultProps={{ social: false }}
      />
      <Composition
        id="BytopolisSocial"
        component={BytopolisVideo}
        durationInFrames={totalFrames(socialScenes)}
        fps={FPS}
        width={1080}
        height={1080}
        defaultProps={{ social: true }}
      />
    </>
  );
};
