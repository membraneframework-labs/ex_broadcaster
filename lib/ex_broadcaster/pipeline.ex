defmodule ExBroadcaster.Pipeline do
  @moduledoc """
  Membrane pipeline that receives a single RTMP stream, transcodes it to
  multiple H.264 variants using the GPU (via `Membrane.VKVideo.Transcoder`),
  and writes an adaptive HLS manifest + fMP4 segments to disk.

  Topology
  --------

    RTMP.SourceBin
      │
      ├─ :video ──► H264.Parser ──► VKVideo.Transcoder ─┬─ :output(1080p) ─► CMAF.Muxer(1080p) ─► HLS.Sink
      │                                                  ├─ :output(720p)  ─► CMAF.Muxer(720p)  ─►   │
      │                                                  └─ :output(480p)  ─► CMAF.Muxer(480p)  ─►   │
      │                                                                                               │
      └─ :audio ──► AAC.Parser ──► Tee ─── :output(1080p) ──────────────────► CMAF.Muxer(1080p) ─►   │
                                       ├─ :output(720p)  ──────────────────► CMAF.Muxer(720p)  ─►   │
                                       └─ :output(480p)  ──────────────────► CMAF.Muxer(480p)  ─►   │

  Each CMAF muxer produces a single muxed audio+video CMAF track delivered
  to the shared HLS sink, which writes segments and a master playlist.

  GPU requirements
  ----------------
  `Membrane.VKVideo.Transcoder` requires Linux with a Vulkan-capable GPU
  (NVIDIA or AMD with Mesa) and the Vulkan Video extension.
  """

  use Membrane.Pipeline

  require Membrane.Logger, as: Logger

  alias Membrane.VKVideo
  alias Membrane.MP4.Muxer.CMAF, as: CMAFMuxer
  alias Membrane.HTTPAdaptiveStream

  @variants [
    %{
      id: :p1080,
      track_name: "1080p",
      width: 1920,
      height: 1080,
      bitrate: 4_000_000,
      framerate: {30, 1}
    },
    %{
      id: :p720,
      track_name: "720p",
      width: 1280,
      height: 720,
      bitrate: 2_500_000,
      framerate: {30, 1}
    },
    %{
      id: :p480,
      track_name: "480p",
      width: 854,
      height: 480,
      bitrate: 1_000_000,
      framerate: {30, 1}
    }
  ]

  def start_link(opts) do
    Membrane.Pipeline.start_link(__MODULE__, opts)
  end

  @impl true
  def handle_init(_ctx, opts) do
    client_ref = Keyword.fetch!(opts, :client_ref)
    output_dir = Keyword.fetch!(opts, :output_dir)
    segment_duration = Keyword.get(opts, :segment_duration, Membrane.Time.seconds(4))

    File.mkdir_p!(output_dir)
    Logger.info("Starting HLS output in #{output_dir}")

    spec = build_spec(client_ref, output_dir, segment_duration)

    {[spec: spec], %{output_dir: output_dir}}
  end

  @impl true
  def handle_element_end_of_stream(:hls_sink, _pad, _ctx, state) do
    Logger.info("HLS sink finished. Terminating pipeline.")
    {[terminate: :normal], state}
  end

  def handle_element_end_of_stream(_child, _pad, _ctx, state) do
    {[], state}
  end

  defp build_spec(client_ref, output_dir, segment_duration) do
    rtmp_source =
      child(:rtmp_source, %Membrane.RTMP.SourceBin{client_ref: client_ref})

    video_branch =
      get_child(:rtmp_source)
      |> via_out(:video)
      |> child(:h264_parser, %Membrane.H264.Parser{
        output_alignment: :au,
        output_stream_structure: :annexb
      })
      |> child(:transcoder, Membrane.VKVideo.Transcoder)

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
        storage: %HTTPAdaptiveStream.Storages.FileStorage{directory: output_dir}
      })

    variant_specs = Enum.flat_map(@variants, &build_variant_spec(&1, segment_duration))

    [rtmp_source, video_branch, audio_branch, hls_sink | variant_specs]
  end

  defp build_variant_spec(variant, segment_duration) do
    %{id: id, track_name: name, width: w, height: h, bitrate: br, framerate: fps} = variant

    video_to_muxer =
      get_child(:transcoder)
      |> via_out(Pad.ref(:output, id),
        options: [
          width: w,
          height: h,
          tune: :low_latency,
          rate_control:
            {:constant_bitrate,
             %VKVideo.Encoder.ConstantBitrate{
               bitrate: br
             }},
          scaling_algorithm: :bilinear
        ]
      )
      |> child({:h264_parser_out, id}, %Membrane.H264.Parser{
        output_alignment: :au,
        output_stream_structure: :avc1
      })
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
