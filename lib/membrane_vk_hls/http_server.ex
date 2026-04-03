defmodule MembraneVkHls.HTTPServer do
  @moduledoc """
  Minimal HTTP server that serves HLS playlists and fMP4 segments from the
  `hls_output_dir` configured in `config/config.exs`.

  Each stream key maps to a sub-directory, so a player can open:

    http://localhost:<http_port>/<stream_key>/index.m3u8

  CORS is allowed from any origin so browser-based players (hls.js, Video.js)
  work without a proxy.

  Cache policy:
  - `.m3u8` playlists  — `no-cache`  (live playlists change every segment)
  - segment files      — `max-age=86400` (immutable once written by the pipeline)
  """

  use Plug.Router

  @hls_dir Application.compile_env(:membrane_vk_hls, :hls_output_dir, "output/hls")

  plug(:put_cors_and_cache_headers)

  plug(Plug.Static,
    at: "/",
    from: @hls_dir
  )

  plug(:match)
  plug(:dispatch)

  get _ do
    send_resp(conn, 404, "Not found")
  end

  match _ do
    send_resp(conn, 405, "Method not allowed")
  end

  defp put_cors_and_cache_headers(conn, _opts) do
    cache_control =
      case Path.extname(conn.request_path) do
        ".m3u8" -> "no-cache, no-store, must-revalidate"
        _segment -> "public, max-age=86400, immutable"
      end

    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-allow-methods", "GET, HEAD, OPTIONS")
    |> put_resp_header("cache-control", cache_control)
  end
end
