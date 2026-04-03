defmodule MembraneVkHls.Application do
  @moduledoc """
  OTP application entry point.

  Starts an RTMP server and a `DynamicSupervisor` for per-client pipelines.
  Each connecting RTMP client (e.g. OBS) spawns a dedicated
  `MembraneVkHls.Pipeline` that transcodes the stream to HLS.

  Push a stream with FFmpeg or OBS to:
    rtmp://localhost:<port>/<app>/<stream_key>

  HLS output is written to:
    <hls_output_dir>/<stream_key>/index.m3u8
  """

  use Application

  require Logger

  @max_concurrent_pipelines Application.compile_env(:membrane_vk_hls, :max_concurrent_pipelines, 10)

  @impl true
  def start(_type, _args) do
    rtmp_port = Application.get_env(:membrane_vk_hls, :rtmp_port, 1935)
    http_port = Application.get_env(:membrane_vk_hls, :http_port, 8080)

    children = [
      {DynamicSupervisor, name: __MODULE__.PipelineSupervisor, strategy: :one_for_one},
      {Membrane.RTMPServer, port: rtmp_port, handle_new_client: &__MODULE__.handle_new_client/3},
      {Bandit, plug: MembraneVkHls.HTTPServer, port: http_port}
    ]

    Logger.info("[App] RTMP server listening on port #{rtmp_port}")
    Logger.info("[App] HTTP server listening on port #{http_port}")

    Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__)
  end

  @doc """
  Called by `Membrane.RTMPServer` whenever a new RTMP publisher connects.

  Starts a supervised `MembraneVkHls.Pipeline` for the connection.
  Each pipeline writes HLS output to its own sub-directory named after
  the stream key, allowing multiple simultaneous streams.
  """
  def handle_new_client(client_ref, app, stream_key) do
    Logger.info("[App] New RTMP client: app=#{app}, stream_key=#{stream_key}")

    base_dir = Application.get_env(:membrane_vk_hls, :hls_output_dir, "output/hls")
    segment_duration_sec = Application.get_env(:membrane_vk_hls, :segment_duration_sec, 4)
    output_dir = Path.join(base_dir, stream_key)

    pipeline_opts = [
      client_ref: client_ref,
      output_dir: output_dir,
      segment_duration: Membrane.Time.seconds(segment_duration_sec)
    ]

    %{active: active} = DynamicSupervisor.count_children(__MODULE__.PipelineSupervisor)

    if active >= @max_concurrent_pipelines do
      Logger.warning("[App] Rejecting client (stream_key=#{stream_key}): reached limit of #{@max_concurrent_pipelines} concurrent pipelines")
    else
      case DynamicSupervisor.start_child(
             __MODULE__.PipelineSupervisor,
             {MembraneVkHls.Pipeline, pipeline_opts}
           ) do
        {:ok, _supervisor, pid} ->
          Logger.info("[App] Pipeline started (pid=#{inspect(pid)}) for stream_key=#{stream_key}")

        {:error, reason} ->
          Logger.error("[App] Failed to start pipeline: #{inspect(reason)}")
      end
    end

    Membrane.RTMP.Source.ClientHandlerImpl
  end
end
