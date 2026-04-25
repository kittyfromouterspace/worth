defmodule Worth.Theme.Bedrock do
  @moduledoc """
  Bedrock theme — Worth's flagship brand theme.

  Obsidian base, molten red as the single action color, and a disciplined
  grayscale hierarchy. Space Grotesk for display, Inter for UI, JetBrains
  Mono for code. See BRAND.md for the full rationale.
  """

  @behaviour Worth.Theme

  def name, do: "bedrock"
  def display_name, do: "Bedrock"
  def description, do: "Worth's flagship theme — obsidian, molten red, minimal bench"

  def colors do
    %{
      background: "bg-[#0B0B0D]",
      surface: "bg-[#1A1A1E]",
      surface_elevated: "bg-[#2A2A2E]",
      border: "border-[#3A3A3F]",
      text: "text-[#E8E8EA]",
      text_muted: "text-[#8A8A8F]",
      text_dim: "text-[#5A5A5F]",
      primary: "text-[#E8E8EA]",
      secondary: "text-[#8A8A8F]",
      accent: "text-[#FF3B2F]",
      success: "text-[#7EC87E]",
      error: "text-[#FF3B2F]",
      warning: "text-[#F0B341]",
      info: "text-[#9E9EA3]",
      # The single molten button. Solid fill, subtle vertical gradient on hover.
      button_primary:
        "bg-[#FF3B2F] text-[#0B0B0D] hover:bg-[#FF6A3D] border border-[#FF6A3D]/40 font-semibold",
      button_secondary:
        "bg-[#2A2A2E] text-[#E8E8EA] hover:bg-[#3A3A3F] border border-[#3A3A3F]",
      # Tabs: molten underline for active, muted text for inactive. No fills.
      tab_active: "border-b-2 border-[#FF3B2F] text-[#E8E8EA]",
      tab_inactive: "text-[#5A5A5F] hover:text-[#8A8A8F]",
      # Status indicators
      status_running: "text-[#F0B341]",
      status_idle: "text-[#5A5A5F]",
      status_error: "text-[#FF3B2F]",
      # Message wrappers — transparent fills, never loud.
      message_user_bg: "bg-[#1A1A1E]",
      message_error_bg: "bg-[#FF3B2F]/10 border border-[#FF3B2F]/30",
      message_thinking_border: "border-l-2 border-[#5A5A5F]",
      message_system_bg: "bg-[#2A2A2E]/40 border border-[#3A3A3F]",
      # Input
      input_placeholder: "placeholder-[#5A5A5F]",
      input_disabled_bg: "bg-[#1A1A1E]",
      input_disabled_text: "text-[#5A5A5F]"
    }
  end

  def css do
    """
    /* Bedrock — Worth's flagship brand theme */

    /* Load brand typography. Variable fonts, cached by the browser. */
    @import url('https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@500;600;700&family=Inter:wght@400;500;600&family=JetBrains+Mono:wght@400;500&display=swap');

    /* Override Catppuccin variables so any legacy ctp-* classes resolve into
       the Bedrock palette. Order of keys matches Worth.Theme.Standard for
       diff clarity. */
    :root {
      --color-ctp-base:      #0B0B0D;
      --color-ctp-mantle:    #1A1A1E;
      --color-ctp-crust:     #050506;
      --color-ctp-surface0:  #1A1A1E;
      --color-ctp-surface1:  #2A2A2E;
      --color-ctp-surface2:  #3A3A3F;
      --color-ctp-overlay0:  #5A5A5F;
      --color-ctp-overlay1:  #6A6A6F;
      --color-ctp-overlay2:  #8A8A8F;
      --color-ctp-text:      #E8E8EA;
      --color-ctp-subtext0:  #9E9EA3;
      --color-ctp-subtext1:  #B8B8BC;
      /* Semantic slots. All non-grayscale colors collapse to molten or
         a narrow palette; no blue, no purple, no teal. */
      --color-ctp-blue:      #E8E8EA;
      --color-ctp-lavender:  #E8E8EA;
      --color-ctp-green:     #7EC87E;
      --color-ctp-yellow:    #F0B341;
      --color-ctp-red:       #FF3B2F;
      --color-ctp-teal:      #9E9EA3;
      --color-ctp-mauve:     #9E9EA3;
      --color-ctp-peach:     #FF6A3D;
      --color-ctp-pink:      #FF6A3D;
      --color-ctp-sky:       #9E9EA3;
      --color-ctp-flamingo:  #FF6A3D;
      --color-ctp-rosewater: #E8E8EA;
      --color-ctp-sapphire:  #9E9EA3;

      /* Brand font stack */
      --font-display: 'Space Grotesk', ui-sans-serif, system-ui, sans-serif;
      --font-ui:      'Inter', ui-sans-serif, system-ui, sans-serif;
      --font-mono:    'JetBrains Mono', ui-monospace, 'Fira Code', monospace;
    }

    body {
      font-family: var(--font-ui);
      font-feature-settings: 'cv11', 'ss01', 'ss03';
      -webkit-font-smoothing: antialiased;
      -moz-osx-font-smoothing: grayscale;
    }

    /* Tabular numerics for anything that updates live. */
    .tabular, code, pre, .markdown-content pre code, [data-numeric] {
      font-variant-numeric: tabular-nums;
    }

    /* Headings — Space Grotesk, tight tracking. */
    h1, h2, h3, h4, h5, h6,
    .heading {
      font-family: var(--font-display);
      letter-spacing: -0.01em;
      font-weight: 600;
    }

    /* Heat seam — the single brand signature in product.
       A 1px molten line that traces the top of the header. */
    .heat-seam {
      position: relative;
    }
    .heat-seam::before {
      content: '';
      position: absolute;
      top: 0;
      left: 0;
      right: 0;
      height: 1px;
      background: linear-gradient(
        90deg,
        rgba(255, 59, 47, 0)   0%,
        rgba(255, 59, 47, 0.5) 20%,
        rgba(255, 59, 47, 0.5) 80%,
        rgba(255, 59, 47, 0)   100%
      );
      pointer-events: none;
    }

    /* Molten button — subtle pressed state, no animation. */
    .btn-molten {
      background: #FF3B2F;
      color: #0B0B0D;
    }
    .btn-molten:hover {
      background: linear-gradient(180deg, #FF6A3D 0%, #FF3B2F 100%);
    }
    .btn-molten:active {
      background: #CC2E24;
    }

    /* Strata divider — thin ash rule. Use sparingly. */
    .strata-divider {
      border: none;
      height: 1px;
      background: #3A3A3F;
    }

    /* Selection */
    ::selection {
      background: rgba(255, 59, 47, 0.35);
      color: #E8E8EA;
    }

    /* Scrollbar — narrow, graphite, no hover bloom. */
    ::-webkit-scrollbar {
      width: 6px;
      height: 6px;
    }
    ::-webkit-scrollbar-track {
      background: #0B0B0D;
    }
    ::-webkit-scrollbar-thumb {
      background: #2A2A2E;
      border-radius: 0;
    }
    ::-webkit-scrollbar-thumb:hover {
      background: #3A3A3F;
    }

    /* Focus rings — molten at 40%, never blue. */
    *:focus-visible {
      outline: 1px solid rgba(255, 59, 47, 0.6);
      outline-offset: 1px;
    }

    /* Inputs — flat, graphite, molten focus. */
    input, textarea, select {
      background: #1A1A1E;
      color: #E8E8EA;
      border: 1px solid #3A3A3F;
    }
    input:focus, textarea:focus, select:focus {
      border-color: #FF3B2F;
      box-shadow: 0 0 0 1px rgba(255, 59, 47, 0.3);
      outline: none;
    }
    input::placeholder, textarea::placeholder {
      color: #5A5A5F;
    }

    /* Chat input — terminal-flavored, fully transparent. Auto-grows up to
       240px tall via the ChatInput hook (rows starts at 1, JS bumps height
       to scrollHeight on input). Overrides the generic input chrome above. */
    textarea.chat-input-textarea,
    textarea.chat-input-textarea:focus {
      background: transparent;
      color: #E8E8EA;
      border: none;
      outline: none;
      box-shadow: none;
      resize: none;
      padding: 0;
      margin: 0;
      font-family: var(--font-mono);
      font-size: 13px;
      line-height: 20px;
      min-height: 20px;
      max-height: 240px;
      overflow-y: auto;
      width: 100%;
      caret-color: #FF3B2F;
    }
    textarea.chat-input-textarea::placeholder {
      color: #5A5A5F;
      font-style: normal;
    }
    textarea.chat-input-textarea:disabled {
      color: #5A5A5F;
      cursor: not-allowed;
    }

    /* W-pulse spinner — the four wedges of the Worth mark light up in
       sequence. Replaces the braille-dot spinner. Scales with font-size,
       inherits currentColor. Requires inline SVG child (see <.w_spinner />). */
    .spinner {
      display: inline-block;
      width: 1em;
      height: 1em;
      position: relative;
      vertical-align: -0.15em;
      line-height: 1;
    }
    .spinner svg {
      width: 100%;
      height: 100%;
      display: block;
    }
    .spinner svg polygon {
      fill: currentColor;
      opacity: 0.22;
      animation: w-pulse 1.2s steps(1, end) infinite;
      transform-origin: center;
    }
    .spinner svg polygon:nth-child(1) { animation-delay: 0s; }
    .spinner svg polygon:nth-child(2) { animation-delay: 0.15s; }
    .spinner svg polygon:nth-child(3) { animation-delay: 0.30s; }
    .spinner svg polygon:nth-child(4) { animation-delay: 0.45s; }
    @keyframes w-pulse {
      0%, 50%, 100% { opacity: 0.22; }
      8%, 20%       { opacity: 1; }
    }

    /* Inline `code` per the UI kit — graphite chip, JetBrains Mono 12px,
       2px radius. Markdown content uses .markdown-content > code. */
    code, .markdown-content code {
      background: #2A2A2E;
      color: #E8E8EA;
      padding: 1px 5px;
      border-radius: 2px;
      font-family: var(--font-mono);
      font-size: 12px;
    }
    pre, .markdown-content pre {
      background: #1A1A1E;
      border: 1px solid #3A3A3F;
      border-radius: 4px;
      padding: 10px 12px;
      overflow-x: auto;
      font-size: 12px;
      line-height: 1.5;
    }
    pre code, .markdown-content pre code {
      background: transparent;
      padding: 0;
      border-radius: 0;
      font-size: 12px;
    }

    /* Tool-call block — terminal-flavored card.
       Amber name, muted args, ore-green result. Tight padding so consecutive
       tool_call + tool_result entries read as one block. */
    .tool-call {
      font-family: var(--font-mono);
      font-size: 12px;
      background: rgba(42, 42, 46, 0.4);
      border: 1px solid #3A3A3F;
      border-radius: 4px;
      padding: 8px 10px;
    }
    .tool-call-name   { color: #F0B341; }
    .tool-call-args   { color: #8A8A8F; }
    .tool-call-result { color: #7EC87E; margin-top: 4px; }
    .tool-call-output {
      color: #5A5A5F;
      margin-top: 4px;
      max-height: 12rem;
      overflow-y: auto;
      white-space: pre-wrap;
      font-size: 11px;
    }

    /* Message meta line — JetBrains Mono, 10px, dim.
       e.g. `you · 14:22`, `worth · claude-sonnet-4`. */
    .msg-meta {
      font-family: var(--font-mono);
      font-size: 10px;
      color: #5A5A5F;
      margin-bottom: 3px;
    }

    /* User message card — subtle dark surface with ash border. */
    .msg-user {
      background: #1A1A1E;
      border: 1px solid #3A3A3F;
      border-radius: 4px;
      padding: 12px 14px;
    }

    /* Thinking strip — italic dim with molten-adjacent left rule. */
    .msg-thinking {
      border-left: 2px solid #5A5A5F;
      padding: 4px 12px;
      color: #8A8A8F;
      font-style: italic;
      font-size: 12px;
    }
    """
  end

  def has_template?(_), do: false
  def render(_, _), do: {:error, :not_found}
end
