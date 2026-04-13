defmodule Worth.Theme.Daylight do
  @moduledoc """
  Daylight theme - Catppuccin Latte (light).

  A warm light theme with soft pastel accents, the natural light
  counterpart to the Standard (Mocha) dark theme.
  """

  @behaviour Worth.Theme

  def name, do: "daylight"
  def display_name, do: "Daylight"
  def description, do: "Catppuccin Latte - warm light theme with pastel accents"

  def colors do
    %{
      background: "bg-[#eff1f5]",
      surface: "bg-[#e6e9ef]",
      surface_elevated: "bg-[#ccd0da]",
      border: "border-[#bcc0cc]",
      text: "text-[#4c4f69]",
      text_muted: "text-[#5c5f77]",
      text_dim: "text-[#7c7f93]",
      primary: "text-[#1e66f5]",
      secondary: "text-[#7287fd]",
      accent: "text-[#df8e1d]",
      success: "text-[#40a02b]",
      error: "text-[#d20f39]",
      warning: "text-[#fe640b]",
      info: "text-[#8839ef]",
      button_primary: "bg-[#1e66f5] text-[#eff1f5] hover:bg-[#4c7cf5]",
      button_secondary: "bg-[#ccd0da] text-[#4c4f69] hover:bg-[#bcc0cc]",
      tab_active: "bg-[#1e66f5] text-[#eff1f5]",
      tab_inactive: "text-[#7c7f93] hover:text-[#4c4f69] hover:bg-[#ccd0da]",
      status_running: "text-[#1e66f5]",
      status_idle: "text-[#7c7f93]",
      status_error: "text-[#d20f39]",
      message_user_bg: "bg-[#ccd0da]/50",
      message_error_bg: "bg-[#d20f39]/10 border border-[#d20f39]/30",
      message_thinking_border: "border-l-2 border-[#8839ef]/30",
      message_system_bg: "bg-[#8839ef]/5 border border-[#8839ef]/20",
      input_placeholder: "placeholder-[#7c7f93]",
      input_disabled_bg: "bg-[#e6e9ef]",
      input_disabled_text: "text-[#7c7f93]"
    }
  end

  def css do
    """
    /* Daylight Theme - Catppuccin Latte */
    :root {
      --color-ctp-base: #eff1f5;
      --color-ctp-mantle: #e6e9ef;
      --color-ctp-crust: #dce0e8;
      --color-ctp-surface0: #ccd0da;
      --color-ctp-surface1: #bcc0cc;
      --color-ctp-surface2: #acb0be;
      --color-ctp-overlay0: #7c7f93;
      --color-ctp-overlay1: #6c6f85;
      --color-ctp-overlay2: #5c5f77;
      --color-ctp-text: #4c4f69;
      --color-ctp-subtext0: #5c5f77;
      --color-ctp-subtext1: #6c6f85;
      --color-ctp-blue: #1e66f5;
      --color-ctp-lavender: #7287fd;
      --color-ctp-green: #40a02b;
      --color-ctp-yellow: #df8e1d;
      --color-ctp-red: #d20f39;
      --color-ctp-teal: #179299;
      --color-ctp-mauve: #8839ef;
      --color-ctp-peach: #fe640b;
      --color-ctp-pink: #ea76cb;
      --color-ctp-sky: #04a5e5;
      --color-ctp-flamingo: #dd7878;
      --color-ctp-rosewater: #dc8a78;
      --color-ctp-sapphire: #209fb5;
    }

    ::selection {
      background: rgba(30, 102, 245, 0.2);
      color: #4c4f69;
    }

    ::-webkit-scrollbar {
      width: 6px;
      height: 6px;
    }

    ::-webkit-scrollbar-track {
      background: #e6e9ef;
    }

    ::-webkit-scrollbar-thumb {
      background: #bcc0cc;
      border-radius: 3px;
    }

    ::-webkit-scrollbar-thumb:hover {
      background: #acb0be;
    }
    """
  end

  def has_template?(_), do: false
  def render(_, _), do: {:error, :not_found}
end
