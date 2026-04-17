defmodule WorthWeb.LLMGatewayController do
  @moduledoc """
  HTTP proxy endpoints for external coding agents.

  Mounts Anthropic-compatible and OpenAI-compatible routes so that
  Claude Code, OpenCode, Kimi, Codex and other agent CLIs can route
  their LLM traffic through Worth.  Every request/response is logged
  to the X-Ray telemetry panel via `AgentEx.LLM.Gateway`.
  """

  use WorthWeb, :controller

  require Logger

  @doc """
  Anthropic Messages API proxy.
  Path: POST /proxy/anthropic/v1/messages
  """
  def anthropic(conn, _params) do
    body = read_body!(conn)
    {status, headers, resp_body} = AgentEx.LLM.Gateway.proxy(:anthropic, conn.request_path, conn.req_headers, body)
    send_response(conn, status, headers, resp_body)
  end

  @doc """
  OpenAI Chat Completions API proxy.
  Path: POST /proxy/openai/v1/chat/completions
  """
  def openai(conn, _params) do
    body = read_body!(conn)
    {status, headers, resp_body} = AgentEx.LLM.Gateway.proxy(:openai, conn.request_path, conn.req_headers, body)
    send_response(conn, status, headers, resp_body)
  end

  # ── Helpers ─────────────────────────────────────────────────────

  defp read_body!(conn) do
    case Plug.Conn.read_body(conn) do
      {:ok, body, _conn} -> body
      {:more, _data, _conn} -> raise "Request body too large"
      {:error, :timeout} -> raise "Request body read timeout"
    end
  end

  defp send_response(conn, status, headers, body) when is_binary(body) do
    conn = put_status(conn, status)

    conn =
      Enum.reduce(headers, conn, fn {k, v}, c ->
        Plug.Conn.put_resp_header(c, k, v)
      end)

    send_resp(conn, status, body)
  end

  defp send_response(conn, status, headers, stream) do
    conn = put_status(conn, status)

    conn =
      Enum.reduce(headers, conn, fn {k, v}, c ->
        Plug.Conn.put_resp_header(c, k, v)
      end)

    # For SSE streams we need to send headers immediately
    conn = Plug.Conn.send_chunked(conn, status)

    Enum.reduce(stream, conn, fn chunk, c ->
      case Plug.Conn.chunk(c, chunk) do
        {:ok, c2} -> c2
        {:error, :closed} -> c
      end
    end)
  end
end
