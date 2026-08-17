import { Config } from "@remotion/cli/config";

Config.setVideoImageFormat("jpeg");
Config.setOverwriteOutput(true);
// H.264, high quality. Bump CRF lower for higher quality / larger files.
Config.setCodec("h264");
Config.setCrf(18);
