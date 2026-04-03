defmodule MembraneVkHls.MixProject do
  use Mix.Project

  def project do
    [
      app: :membrane_vk_hls,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {MembraneVkHls.Application, []}
    ]
  end

  defp deps do
    [
      # Core framework
      {:membrane_core, "~> 1.2"},

      # GPU-accelerated H.264 transcoder via Vulkan Video
      # Requires Linux + NVIDIA/AMD GPU with Vulkan Video extension support
      {:membrane_vk_video_plugin, "~> 0.2.0"},

      # RTMP server / source
      {:membrane_rtmp_plugin, "~> 0.29.3"},

      # HLS output
      {:membrane_http_adaptive_stream_plugin, "~> 0.21.0"},

      # MP4 / CMAF muxer (produces fMP4 segments consumed by HLS sink)
      {:membrane_mp4_plugin, "~> 0.36.0"},

      # H.264 bitstream parser (AVCC → Annex B / AU alignment)
      {:membrane_h26x_plugin, "~> 0.10.5"},

      # AAC parser (strip ADTS framing expected by CMAF muxer)
      {:membrane_aac_plugin, "~> 0.19.0"},

      # HTTP server for serving HLS output
      {:bandit, "~> 1.0"},
      {:plug, "~> 1.14"}
    ]
  end
end
