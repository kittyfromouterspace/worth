defmodule Worth.LogHandler do
  @moduledoc """
  Erlang `:logger` handler that forwards events into `Worth.LogBuffer`
  and tees them to a plain-text file for external inspection.
  """

  @default_relpath "logs/worth.log"

  def log(%{level: level, msg: msg, meta: meta}, _config) do
    text = format_msg(msg, meta)
    ts = System.system_time(:millisecond)

    Worth.LogBuffer.push(%{level: level, text: text, ts: ts})
    write_to_file(level, text, ts)
  catch
    _kind, _reason -> :ok
  end

  def file_path do
    base =
      case System.get_env("WORTH_LOG_FILE") do
        nil -> Path.expand(@default_relpath, Worth.Paths.data_dir())
        "" -> Path.expand(@default_relpath, Worth.Paths.data_dir())
        explicit -> Path.expand(explicit)
      end

    with_rotation(base)
  end

  def base_path do
    case System.get_env("WORTH_LOG_FILE") do
      nil -> Path.expand(@default_relpath, Worth.Paths.data_dir())
      "" -> Path.expand(@default_relpath, Worth.Paths.data_dir())
      explicit -> Path.expand(explicit)
    end
  end

  defp with_rotation(base_path) do
    case rotation_mode() do
      :daily ->
        date_str = Date.to_iso8601(DateTime.utc_now())
        ext = Path.extname(base_path)
        basename = Path.rootname(base_path)
        "#{basename}-#{date_str}#{ext}"

      _ ->
        base_path
    end
  end

  @log_config Application.compile_env(:worth, :log, nil)

  defp rotation_mode do
    case @log_config do
      nil -> nil
      opts when is_list(opts) -> Keyword.get(opts, :rotation, nil)
      _ -> nil
    end
  end

  defp write_to_file(level, text, ts) do
    path = file_path()
    File.mkdir_p!(Path.dirname(path))

    iso =
      ts
      |> DateTime.from_unix!(:millisecond)
      |> DateTime.to_iso8601()

    line = "#{iso} [#{pad_level(level)}] #{text}\n"
    File.write!(path, line, [:append])
  rescue
    _ -> :ok
  end

  defp pad_level(level) do
    level
    |> Atom.to_string()
    |> String.pad_trailing(8)
  end

  defp format_msg({:string, chardata}, _meta) do
    chardata |> IO.chardata_to_string() |> String.trim_trailing()
  end

  defp format_msg({:report, report}, %{report_cb: cb}) when is_function(cb, 1) do
    {format, args} = cb.(report)
    format |> :io_lib.format(args) |> IO.chardata_to_string() |> String.trim_trailing()
  end

  defp format_msg({:report, report}, %{report_cb: cb}) when is_function(cb, 2) do
    report
    |> cb.(%{depth: :unlimited, chars_limit: :unlimited, single_line: false})
    |> IO.chardata_to_string()
    |> String.trim_trailing()
  end

  defp format_msg({:report, report}, _meta), do: inspect(report, pretty: false)

  defp format_msg({format, args}, _meta) when is_list(format) or is_binary(format) do
    format |> :io_lib.format(args) |> IO.chardata_to_string() |> String.trim_trailing()
  end

  defp format_msg(other, _meta), do: inspect(other)
end
