import Config

# Register HLS-specific MIME types so Plug.Static serves correct Content-Type headers.
config :mime, :types, %{
  "application/vnd.apple.mpegurl" => ["m3u8"],
  "video/mp4" => ["m4s", "mp4"],
  "video/mp2t" => ["ts"]
}

config :membrane_vk_hls,
  # Port OBS / FFmpeg pushes the RTMP stream to
  rtmp_port: 1935,

  # Directory where HLS playlists and segments will be written.
  # A sub-directory named after the stream key is created for each client.
  hls_output_dir: "output/hls",

  # HLS segment target duration in seconds.
  # Lower values reduce latency; higher values improve compression efficiency.
  segment_duration_sec: 4,

  # Port the built-in HTTP server listens on.
  # Streams are available at http://localhost:<http_port>/<stream_key>/index.m3u8
  http_port: 8080
