defmodule WorthWeb.Components.Brand do
  @moduledoc """
  Brand components: the flat W mark and the wordmark lockup.

  The textured stone mark (`brand/logo.png`) is marketing-only. In-product
  we use these flat SVG components so the brand is crisp at every size and
  inherits the active theme.

  See BRAND.md for usage rules.
  """
  use Phoenix.Component

  @doc """
  The flat Worth mark — four faceted wedges with three molten seams.

  Distilled from the sculpted textured logo: two outer uprights and two
  inner descenders meeting below the baseline (the inner V drops lower
  than the outer uprights — that asymmetric stance is the silhouette and
  the reason this reads as a W, not a zigzag). Three molten seams sit
  between the wedges and echo the lava cracks in the textured version.

  ## Attributes

    * `:size` — pixel size. Defaults to 20.
    * `:seam` — render the molten seams. Defaults to true. Set to false
      for monochrome contexts (favicons, mono knockouts).
    * `:class` — extra classes for the `<svg>` element.

  Wedges use `currentColor` so the mark inherits the surrounding text
  color; seams are always molten red.
  """
  attr :size, :integer, default: 20
  attr :seam, :boolean, default: true
  attr :class, :string, default: nil

  def worth_mark(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 64 64"
      width={@size}
      height={@size}
      class={["shrink-0", @class]}
      aria-hidden="true"
    >
      <g :if={@seam} fill="#FF3B2F">
        <polygon points="17,10 21,10 29,46 26,46" />
        <polygon points="31,14 33,14 33,48 31,48" />
        <polygon points="43,10 47,10 38,46 35,46" />
      </g>
      <g fill="currentColor">
        <polygon points="4,10 16,10 28,46 18,52" />
        <polygon points="22,10 30,10 32,48 28,46" />
        <polygon points="34,10 42,10 36,46 32,48" />
        <polygon points="48,10 60,10 46,52 36,46" />
      </g>
    </svg>
    """
  end

  @doc """
  The Worth wordmark lockup — flat mark + "worth" text in Space Grotesk.

  ## Attributes

    * `:size` — one of `:xs`, `:sm`, `:md`, `:lg`, `:xl`. Defaults to `:md`.
    * `:show_tagline` — when true, renders the positioning line beneath the
      wordmark. Defaults to false. Used in onboarding and vault unlock.
    * `:class` — extra classes for the wrapper.
  """
  attr :size, :atom, default: :md, values: [:xs, :sm, :md, :lg, :xl]
  attr :show_tagline, :boolean, default: false
  attr :class, :string, default: nil

  def worth_wordmark(assigns) do
    ~H"""
    <div class={["inline-flex flex-col items-center", @class]}>
      <div class="inline-flex items-center gap-2">
        <.worth_mark size={mark_px(@size)} seam={@size not in [:xs]} />
        <span
          class="font-semibold tracking-tight"
          style={"font-family: 'Space Grotesk', sans-serif; font-size: #{text_px(@size)}px; line-height: 1;"}
        >worth</span>
      </div>
      <div
        :if={@show_tagline}
        class="text-xs text-[#8A8A8F] mt-2"
        style="font-family: 'Inter', sans-serif;"
      >
        a bench for serious AI work
      </div>
    </div>
    """
  end

  defp mark_px(:xs), do: 14
  defp mark_px(:sm), do: 18
  defp mark_px(:md), do: 22
  defp mark_px(:lg), do: 32
  defp mark_px(:xl), do: 48

  defp text_px(:xs), do: 13
  defp text_px(:sm), do: 16
  defp text_px(:md), do: 20
  defp text_px(:lg), do: 28
  defp text_px(:xl), do: 40

  @doc """
  The Worth W-pulse spinner.

  Renders the four wedges of the W mark as inline SVG so the polygons can
  light up in sequence (1.2s loop, 150ms stagger). Inherits `currentColor`
  and scales with `font-size` (1em x 1em). Use in any state where the agent
  is working — header status glyph, tool-call running badge, sidebar agent
  rows.
  """
  attr :class, :string, default: nil

  def w_spinner(assigns) do
    ~H"""
    <span class={["spinner", @class]} aria-hidden="true">
      <svg viewBox="0 0 64 64">
        <polygon points="4,10 16,10 28,46 18,52" />
        <polygon points="22,10 30,10 32,48 28,46" />
        <polygon points="34,10 42,10 36,46 32,48" />
        <polygon points="48,10 60,10 46,52 36,46" />
      </svg>
    </span>
    """
  end
end
