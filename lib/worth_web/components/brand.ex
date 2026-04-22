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
  The flat Worth mark — a geometric W with a molten heat seam.

  ## Attributes

    * `:size` — pixel size. Defaults to 20.
    * `:seam` — whether to render the molten heat seam. Defaults to true.
      Set to false for tiny sizes or monochrome contexts.
    * `:class` — extra classes for the `<svg>` element.

  The strokes use `currentColor` so the mark inherits the surrounding text
  color. The seam is always molten red.
  """
  attr :size, :integer, default: 20
  attr :seam, :boolean, default: true
  attr :class, :string, default: nil

  def worth_mark(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 48 48"
      width={@size}
      height={@size}
      fill="none"
      class={["shrink-0", @class]}
      aria-hidden="true"
    >
      <path
        d="M 8 8 L 18 40 L 24 20 L 30 40 L 40 8"
        stroke="currentColor"
        stroke-width="5"
        stroke-linecap="square"
        stroke-linejoin="miter"
      />
      <rect
        :if={@seam}
        x="4"
        y="26"
        width="40"
        height="1.5"
        fill="#FF3B2F"
        opacity="0.75"
      />
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
end
