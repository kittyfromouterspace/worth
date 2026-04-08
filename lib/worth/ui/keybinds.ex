defmodule Worth.UI.Keybinds do
  @moduledoc """
  Keybinding reference and command palette.

  Provides:
  - Help overlay triggered by `?`
  - Command palette triggered by `:`
  - Search within chat triggered by `/`

  Inspired by Lazygit's `?` help and k9s command palette.
  """

  import TermUI.Component.Helpers
  alias Worth.UI.Theme

  @bindings %{
    navigation: [
      {"j/↓", "down"},
      {"k/↑", "up"},
      {"Enter", "select"},
      {"Esc", "back/cancel"},
      {"Tab", "cycle sidebar"},
      {"gg", "jump to top"},
      {"G", "jump to bottom"}
    ],
    input: [
      {"Enter", "submit"},
      {"Ctrl-a", "start of line"},
      {"Ctrl-e", "end of line"},
      {"Ctrl-u", "clear line"},
      {"↑/↓", "history"},
      {"Backspace", "delete char"}
    ],
    actions: [
      {"?", "help"},
      {"/", "search"},
      {":", "command palette"},
      {"Ctrl-l", "redraw"},
      {"Ctrl-c", "interrupt"}
    ],
    chat: [
      {"Ctrl-n", "new chat"},
      {"Ctrl-s", "save session"},
      {"Ctrl-r", "resume session"}
    ]
  }

  def help_overlay do
    sections =
      Enum.map(@bindings, fn {category, bindings} ->
        header = text("[#{category}]", Theme.badge_style())

        items =
          Enum.map(bindings, fn {key, desc} ->
            text("  #{pad_key(key)} #{desc}", Theme.keyhint_style())
          end)

        [header | items]
      end)
      |> Enum.intersperse(text(""))

    stack(:vertical, [
      text("KEYBINDINGS", Theme.card_header_style()),
      text("", Theme.keyhint_style())
      | sections
    ])
  end

  def command_palette_commands do
    [
      {"mode code", "Switch to code mode"},
      {"mode research", "Switch to research mode"},
      {"mode planned", "Switch to planned mode"},
      {"workspace switch <name>", "Switch workspace"},
      {"session list", "List sessions"},
      {"session resume <id>", "Resume session"},
      {"skill list", "List skills"},
      {"skill refine <name>", "Refine skill"},
      {"tool list", "List tools"},
      {"clear", "Clear chat"},
      {"quit", "Quit worth"}
    ]
  end

  def command_palette do
    commands = command_palette_commands()

    header = text("COMMAND PALETTE", Theme.card_header_style())

    items =
      Enum.map(commands, fn {cmd, desc} ->
        text("  #{cmd} — #{desc}", Theme.keyhint_style())
      end)

    stack(:vertical, [header, text("", Theme.keyhint_style()) | items])
  end

  def search_prompt do
    text("/ search...", Theme.keyhint_key_style())
  end

  defp pad_key(key) do
    String.pad_trailing(key, 8, " ")
  end
end
