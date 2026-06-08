defmodule ExBroadcaster do
  @moduledoc """
  RTMP-to-HLS adaptive transcoding application built on the Membrane Framework.

  Receives an RTMP stream (H.264/AAC) and produces multi-variant HLS output
  using `Membrane.Transcoder` with Vulkan Video native acceleration via `membrane_vk_video_plugin`.

  ## Variants

  | Name  | Resolution  |
  |-------|-------------|
  | 1080p | 1920 × 1080 |
  | 720p  | 1280 × 720  |
  | 480p  | 854 × 480   |

  ## Usage

  Start the application:

      mix run --no-halt

  Push a stream with OBS or FFmpeg:

      ffmpeg -re -i input.mp4 \\
        -c:v copy -c:a copy \\
        -f flv rtmp://localhost:1935/ex_broadcaster/stream_key

  HLS output is available at:

      output/hls/<stream_key>/index.m3u8

  Open `http://localhost:8080/index.m3u8` in a player that supports HLS.

  ## Hardware requirements
  - NVIDIA or AMD GPU with Mesa drivers and Vulkan Video extension support
  """
end
