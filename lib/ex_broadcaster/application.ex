defmodule ExBroadcaster.Application do
  @moduledoc """
  OTP application entry point.

  Starts an RTMP server and a `DynamicSupervisor` for per-client pipelines.
  Each connecting RTMP client (e.g. OBS) spawns a dedicated
  `ExBroadcaster.Pipeline` that transcodes the stream to HLS.

  Push a stream with FFmpeg or OBS to:
    rtmp://localhost:<port>/<app>/<stream_key>

  The storage backend is selected via `config :ex_broadcaster, :storage`:

  - `:file` — writes HLS output to `<hls_output_dir>/<stream_key>/`
  - `:s3`   — uploads HLS output to `s3://<s3_bucket>/<s3_prefix>/<year>/<month>/<day>/<hour>/<stream_key>/`

  AWS credentials for the S3 backend are resolved by ExAws from environment
  variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`).
  """

  use Application

  require Logger

  alias Membrane.HTTPAdaptiveStream.Storages.FileStorage
  alias ExBroadcaster.Storages.S3Storage

  @max_concurrent_pipelines Application.compile_env(:ex_broadcaster, :max_concurrent_pipelines, 10)

  @impl true
  def start(_type, _args) do
    rtmp_port = Application.get_env(:ex_broadcaster, :rtmp_port, 1935)
    http_port = Application.get_env(:ex_broadcaster, :http_port, 8080)

    children = [
      {Membrane.RTMPServer, port: rtmp_port, handle_new_client: &__MODULE__.handle_new_client/3},
      {DynamicSupervisor, name: __MODULE__.PipelineSupervisor, strategy: :one_for_one},
      {Bandit, plug: ExBroadcaster.HTTPServer, port: http_port}
    ]

    Logger.info("[App] RTMP server listening on port #{rtmp_port}")
    Logger.info("[App] HTTP server listening on port #{http_port}")

    Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__)
  end

  @doc """
  Called by `Membrane.RTMPServer` whenever a new RTMP publisher connects.

  Starts a supervised `ExBroadcaster.Pipeline` for the connection.
  Each pipeline uploads HLS output to its own S3 prefix named after
  the stream key, allowing multiple simultaneous streams.
  """
  def handle_new_client(client_ref, app, stream_key) do
    Logger.info("[App] New RTMP client: app=#{app}, stream_key=#{stream_key}")

    segment_duration_sec = Application.get_env(:ex_broadcaster, :segment_duration_sec, 4)

    pipeline_opts = [
      client_ref: client_ref,
      storage: build_storage(stream_key),
      segment_duration: Membrane.Time.seconds(segment_duration_sec)
    ]

    %{active: active} = DynamicSupervisor.count_children(__MODULE__.PipelineSupervisor)

    if active >= @max_concurrent_pipelines do
      Logger.warning("[App] Rejecting client (stream_key=#{stream_key}): reached limit of #{@max_concurrent_pipelines} concurrent pipelines")
    else
      case DynamicSupervisor.start_child(
             __MODULE__.PipelineSupervisor,
             Supervisor.child_spec({ExBroadcaster.Pipeline, pipeline_opts}, restart: :temporary)
           ) do
        {:ok, _supervisor, pid} ->
          Logger.info("[App] Pipeline started (pid=#{inspect(pid)}) for stream_key=#{stream_key}")

        {:error, reason} ->
          Logger.error("[App] Failed to start pipeline: #{inspect(reason)}")
      end
    end

    Membrane.RTMP.Source.ClientHandlerImpl
  end

  defp date_path do
    %{year: y, month: m, day: d, hour: h} = DateTime.utc_now()
    "#{y}/#{m}/#{d}/#{h}"
  end

  defp build_storage(stream_key) do
    case Application.get_env(:ex_broadcaster, :storage, :file) do
      :s3 ->
        bucket = Application.fetch_env!(:ex_broadcaster, :s3_bucket)
        prefix = Application.get_env(:ex_broadcaster, :s3_prefix, "hls")
        %S3Storage{bucket: bucket, prefix: Enum.join([prefix, date_path(), stream_key], "/")}

      :file ->
        base_dir = Application.get_env(:ex_broadcaster, :hls_output_dir, "output/hls")
        output_dir = Path.join(base_dir, stream_key)
        File.mkdir_p!(output_dir)
        %FileStorage{directory: output_dir}
    end
  end
end
