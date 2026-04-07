import Config

# Register HLS-specific MIME types so Plug.Static serves correct Content-Type headers.
config :mime, :types, %{
  "application/vnd.apple.mpegurl" => ["m3u8"],
  "video/mp4" => ["m4s", "mp4"],
  "video/mp2t" => ["ts"]
}

config :ex_broadcaster,
  rtmp_port: 1935,
  hls_output_dir: "output/hls",
  segment_duration_sec: 4,
  http_port: 8080,
  max_concurrent_pipelines: 10
