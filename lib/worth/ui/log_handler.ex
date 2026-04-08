defmodule Worth.UI.LogHandler do
  @moduledoc """
  Erlang `:logger` handler that forwards events into `Worth.UI.LogBuffer`
  AND tees them to a plain-text file for external inspection.

  Installed by `Worth.CLI` before `TermUI.Runtime.run/1` and paired with
  removing the default handler so nothing writes log output to stdout
  while the TUI owns the screen.

      :logger.add_handler(:worth_tui, Worth.UI.LogHandler, %{})

  ## File log

  Every event is also appended to `~/.worth/logs/worth.log` (path can be
  overridden by setting `WORTH_LOG_FILE`). This is the place to look when
  something goes wrong inside the TUI — you can `tail -f` it from another
  terminal, or `grep` it after the fact, since the in-TUI Logs panel
  isn't mouse-selectable while the alternate screen is active.

  The path of the file log is logged at info level on every boot so it's
  visible in the Logs panel as well.
  """

  @default_relpath "~/.worth/logs/worth.log"

  @doc false
  def log(%{level: level, msg: msg, meta: meta}, _config) do
    text = format_msg(msg, meta)
    ts = System.system_time(:millisecond)

    Worth.UI.LogBuffer.push(%{level: level, text: text, ts: ts})
    write_to_file(level, text, ts)
  catch
    # A log handler must never crash the emitter. Swallow anything that
    # goes wrong while formatting (e.g. LogBuffer not yet started during
    # boot).
    _kind, _reason -> :ok
  end

  @doc """
  Returns the absolute path of the file log. Honors `WORTH_LOG_FILE`
  if set, otherwise expands `~/.worth/logs/worth.log`.
  """
  def file_path do
    case System.get_env("WORTH_LOG_FILE") do
      nil -> Path.expand(@default_relpath)
      "" -> Path.expand(@default_relpath)
      explicit -> Path.expand(explicit)
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

  # ----- formatting -----

  defp format_msg({:string, chardata}, _meta) do
    chardata |> IO.chardata_to_string() |> String.trim_trailing()
  end

  defp format_msg({:report, report}, %{report_cb: cb}) when is_function(cb, 1) do
    {format, args} = cb.(report)
    format |> :io_lib.format(args) |> IO.chardata_to_string() |> String.trim_trailing()
  end

  defp format_msg({:report, report}, %{report_cb: cb}) when is_function(cb, 2) do
    cb.(report, %{depth: :unlimited, chars_limit: :unlimited, single_line: false})
    |> IO.chardata_to_string()
    |> String.trim_trailing()
  end

  defp format_msg({:report, report}, _meta), do: inspect(report, pretty: false)

  defp format_msg({format, args}, _meta) when is_list(format) or is_binary(format) do
    format |> :io_lib.format(args) |> IO.chardata_to_string() |> String.trim_trailing()
  end

  defp format_msg(other, _meta), do: inspect(other)
end
