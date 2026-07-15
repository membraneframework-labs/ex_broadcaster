defmodule ExBroadcaster.Pipeline do
  @moduledoc """
  Membrane pipeline that receives a single RTMP stream, transcodes it to
  multiple H.264 variants using a single `Membrane.Transcoder` with multiple outputs
  (v0.4.0+ feature) and Vulkan Video native acceleration via `membrane_vk_video_plugin`,
  and uploads an adaptive HLS manifest + fMP4 segments.

  Topology
  --------

    RTMP.SourceBin
      │
      ├─ :video ──► H264.Parser ──► Transcoder ──┬─ :output(:p1080) ──► CMAF.Muxer(1080p) ─►
      │                                     ├─ :output(:p720)  ──► CMAF.Muxer(720p)  ─► HLS.Sink
      │                                     └─ :output(:p480)  ──► CMAF.Muxer(480p)  ─►
      │
      └─ :audio ──► AAC.Parser ──► Tee ──────────┬─ :output(:p1080) ─► CMAF.Muxer(1080p) ─►
                                                  ├─ :output(:p720)  ─► CMAF.Muxer(720p)  ─►
                                                  └─ :output(:p480)  ─► CMAF.Muxer(480p)  ─►

  Each CMAF muxer produces a single muxed audio+video CMAF track delivered
  to the shared HLS sink, which writes segments and a master playlist.

  Each output pad also carries its own target bitrate (`Membrane.Transcoder.Video.VariableBitrate`),
  so the transcoder encodes a proper bitrate ladder alongside the resolution ladder instead of
  leaving every variant at the encoder's default rate control.

  GPU requirements
  ----------------
  When `native_acceleration: :if_available` is set and `membrane_vk_video_plugin` is present,
  `Membrane.Transcoder` uses Vulkan Video hardware acceleration for encoding/decoding.
  This requires Linux with a Vulkan-capable GPU (NVIDIA or AMD with Mesa) and the Vulkan Video extension.
  """

  use Membrane.Pipeline

  require Membrane.Logger, as: Logger
  require Membrane.Pad

  alias Membrane.HTTPAdaptiveStream
  alias Membrane.MP4.Muxer.CMAF, as: CMAFMuxer
  alias Membrane.Pad
  alias Membrane.Transcoder.Video.VariableBitrate

  @variants [
    %{
      id: :p1080,
      track_name: "1080p",
      width: 1920,
      height: 1080,
      framerate: {30, 1},
      bitrate: %VariableBitrate{average_bitrate: 5_000_000, max_bitrate: 6_000_000}
    },
    %{
      id: :p720,
      track_name: "720p",
      width: 1280,
      height: 720,
      framerate: {30, 1},
      bitrate: %VariableBitrate{average_bitrate: 2_800_000, max_bitrate: 3_500_000}
    },
    %{
      id: :p480,
      track_name: "480p",
      width: 854,
      height: 480,
      framerate: {30, 1},
      bitrate: %VariableBitrate{average_bitrate: 1_400_000, max_bitrate: 1_750_000}
    }
  ]

  @spec start_link([
          {:client_ref, pid()},
          {:storage, HTTPAdaptiveStream.Storage.t()},
          {:segment_duration, Membrane.Time.t()}
        ]) :: Membrane.Pipeline.on_start()
  def start_link(opts) do
    Membrane.Pipeline.start_link(__MODULE__, opts)
  end

  @impl true
  def handle_init(_ctx, opts) do
    client_ref = Keyword.fetch!(opts, :client_ref)
    storage = Keyword.fetch!(opts, :storage)
    segment_duration = Keyword.get(opts, :segment_duration, Membrane.Time.seconds(4))

    spec = build_spec(client_ref, storage, segment_duration)

    {[spec: spec], %{}}
  end

  @impl true
  def handle_element_end_of_stream(:hls_sink, _pad, _ctx, state) do
    Logger.info("HLS sink finished. Terminating pipeline.")
    {[terminate: :normal], state}
  end

  def handle_element_end_of_stream(_child, _pad, _ctx, state) do
    {[], state}
  end

  defp build_spec(client_ref, storage, segment_duration) do
    rtmp_source =
      child(:rtmp_source, %Membrane.RTMP.SourceBin{client_ref: client_ref})

    video_branch =
      get_child(:rtmp_source)
      |> via_out(:video)
      |> child(:h264_parser, %Membrane.H264.Parser{
        output_alignment: :au,
        output_stream_structure: :annexb
      })
      |> child(:transcoder, %Membrane.Transcoder{
        transcoding_policy: :always,
        native_acceleration: :if_available
      })

    audio_branch =
      get_child(:rtmp_source)
      |> via_out(:audio)
      |> child(:aac_parser, %Membrane.AAC.Parser{out_encapsulation: :none, output_config: :esds})
      |> child(:audio_tee, Membrane.Tee)

    hls_sink =
      child(:hls_sink, %HTTPAdaptiveStream.Sink{
        manifest_config: %HTTPAdaptiveStream.Sink.ManifestConfig{
          name: "index",
          module: HTTPAdaptiveStream.HLS
        },
        track_config: %HTTPAdaptiveStream.Sink.TrackConfig{},
        storage: storage
      })

    variant_specs = Enum.flat_map(@variants, &build_variant_spec(&1, segment_duration))

    [rtmp_source, video_branch, audio_branch, hls_sink | variant_specs]
  end

  defp build_variant_spec(variant, segment_duration) do
    %{id: id, track_name: name, width: w, height: h, framerate: fps, bitrate: bitrate} = variant

    video_to_muxer =
      get_child(:transcoder)
      |> via_out(Pad.ref(:output, id),
        options: [
          output_stream_format: %Membrane.H264{
            width: w,
            height: h,
            framerate: fps,
            alignment: :au,
            stream_structure: :avc1
          },
          bitrate: bitrate
        ]
      )
      |> via_in(Pad.ref(:input, {:video, id}))
      |> child({:cmaf_muxer, id}, %CMAFMuxer{segment_min_duration: segment_duration})
      |> via_in(Pad.ref(:input, id),
        options: [
          track_name: name,
          segment_duration: segment_duration,
          max_framerate: fps
        ]
      )
      |> get_child(:hls_sink)

    audio_to_muxer =
      get_child(:audio_tee)
      |> via_out(Pad.ref(:output, id))
      |> via_in(Pad.ref(:input, {:audio, id}))
      |> get_child({:cmaf_muxer, id})

    [video_to_muxer, audio_to_muxer]
  end
end
