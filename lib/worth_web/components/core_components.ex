defmodule WorthWeb.CoreComponents do
  @moduledoc """
  Core UI components for Worth.
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error]
  attr :rest, :global

  slot :inner_block

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class={[
        "fixed top-4 right-4 z-50 w-80 rounded-md border px-4 py-3 text-sm shadow-lg",
        @kind == :info && "flash-info",
        @kind == :error && "flash-error"
      ]}
      {@rest}
    >
      <div class="flex items-start gap-2">
        <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 shrink-0 text-ctp-blue" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle" class="size-5 shrink-0 text-ctp-red" />
        <div class="flex-1">
          <p :if={@title} class="font-semibold">{@title}</p>
          <p>{msg}</p>
        </div>
        <button type="button" class="group cursor-pointer" aria-label="close">
          <.icon name="hero-x-mark" class="size-5 text-ctp-overlay0 group-hover:text-ctp-text" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300", "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  def translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end

  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end

  # ── Form primitives ────────────────────────────────────────────

  @doc """
  Renders a text input with the app's standard styling.
  """
  attr :name, :string, default: nil
  attr :type, :string, default: "text"
  attr :value, :any, default: nil
  attr :placeholder, :string, default: nil
  attr :rest, :global

  def input(assigns) do
    ~H"""
    <input
      type={@type}
      name={@name}
      value={@value}
      placeholder={@placeholder}
      class="w-full bg-ctp-surface0 border border-ctp-surface1 rounded px-3 py-2 text-sm text-ctp-text placeholder-ctp-overlay0 focus:outline-none focus:border-ctp-blue"
      {@rest}
    />
    """
  end

  @doc """
  Renders a primary button.
  """
  attr :type, :string, default: "button"
  attr :rest, :global

  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button
      type={@type}
      class="px-4 py-2 rounded text-xs font-semibold bg-ctp-blue text-ctp-base hover:bg-ctp-lavender cursor-pointer"
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  Renders a secondary button.
  """
  attr :type, :string, default: "button"
  attr :rest, :global

  slot :inner_block, required: true

  def button_secondary(assigns) do
    ~H"""
    <button
      type={@type}
      class="px-4 py-2 rounded text-xs font-semibold bg-ctp-surface0 text-ctp-text border border-ctp-surface1 hover:bg-ctp-surface1 cursor-pointer"
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  Renders a select dropdown with standard styling.
  """
  attr :name, :string, default: nil
  attr :value, :any, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  def select(assigns) do
    ~H"""
    <select
      name={@name}
      class="w-full bg-ctp-surface0 border border-ctp-surface1 rounded px-3 py-2 text-sm text-ctp-text focus:outline-none focus:border-ctp-blue"
      {@rest}
    >
      {render_slot(@inner_block)}
    </select>
    """
  end

  @doc """
  Renders a form section container.
  """
  attr :title, :string, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  def form_section(assigns) do
    ~H"""
    <div class="rounded-lg border border-ctp-surface0 bg-ctp-mantle p-4" {@rest}>
      <h2 :if={@title} class="text-sm font-semibold text-ctp-lavender uppercase tracking-wider mb-3">
        {@title}
      </h2>
      {render_slot(@inner_block)}
    </div>
    """
  end
end
