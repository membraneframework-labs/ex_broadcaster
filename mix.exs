defmodule ExBroadcaster.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_broadcaster,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {ExBroadcaster.Application, []}
    ]
  end

  defp deps do
    [
      {:membrane_core, "~> 1.2"},
      {:membrane_vk_video_plugin, "~> 0.2.1"},
      {:membrane_rtmp_plugin, "~> 0.29.3"},
      {:membrane_http_adaptive_stream_plugin, "~> 0.21.0"},
      {:membrane_mp4_plugin, "~> 0.36.0"},
      {:membrane_h26x_plugin, "~> 0.10.5"},
      {:membrane_aac_plugin, "~> 0.19.0"},
      {:bandit, "~> 1.0"},
      {:plug, "~> 1.14"}
    ]
  end
end
