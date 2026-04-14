defmodule ExBroadcaster.Storages.S3Storage do
  @moduledoc """
  `Membrane.HTTPAdaptiveStream.Storage` implementation that uploads HLS manifests
  and fMP4 segments to Amazon S3.

  Each file is stored under `<prefix>/<year>/<month>/<day>/<hour>/<stream_key>` inside the configured bucket.

  AWS credentials are resolved by ExAws from environment variables
  (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`).
  """

  @behaviour Membrane.HTTPAdaptiveStream.Storage

  require Logger

  @enforce_keys [:bucket, :prefix]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          bucket: String.t(),
          prefix: String.t()
        }

  @impl true
  def init(%__MODULE__{} = config), do: config

  @impl true
  def store(_parent_id, name, content, _metadata, _ctx, %{bucket: bucket, prefix: prefix} = state) do
    key = prefix <> "/" <> name

    case bucket |> ExAws.S3.put_object(key, content) |> ExAws.request() do
      {:ok, _response} ->
        {:ok, state}

      {:error, reason} ->
        Logger.error("S3 upload failed for #{key}: #{inspect(reason)}")
        {{:error, reason}, state}
    end
  end

  @impl true
  def remove(_parent_id, name, _ctx, %{bucket: bucket, prefix: prefix} = state) do
    key = prefix <> "/" <> name

    case bucket |> ExAws.S3.delete_object(key) |> ExAws.request() do
      {:ok, _response} ->
        {:ok, state}

      {:error, reason} ->
        Logger.warning("S3 delete failed for #{key}: #{inspect(reason)}")
        {{:error, reason}, state}
    end
  end
end
