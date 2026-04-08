---
name: term-ui
description: Unified skill for building terminal user interfaces with TermUI (Elixir/BEAM), incorporating general TUI best practices and framework-specific patterns.
loading: auto
model_tier: any
provenance: human
trust_level: installed
---

# TermUI (Elixir/BEAM)

## When to Use
Use this skill when building terminal user interfaces in Elixir using the TermUI framework. This skill combines TermUI-specific patterns with general TUI best practices for creating production-grade applications.

## Overview

TermUI is a direct-mode Terminal UI framework for Elixir/BEAM, inspired by BubbleTea (Go) and Ratatui (Rust). It leverages BEAM's unique strengths—fault tolerance, actor model, hot code reloading—to build robust terminal applications using The Elm Architecture.

## Elm Architecture (Core Pattern)

TermUI uses The Elm Architecture adapted for OTP with three core components:

```
Model → View → Message → Update → New Model
```

### 1. `init/1` - Initialize State

```elixir
def init(opts) do
  %{
    name: Keyword.get(opts, :name, "World"),
    count: 0,
    items: [],
    # UI State
    selected_index: 0,
    loading: false,
    error: nil
  }
end
```

State should contain only what's needed for rendering and event handling.

### 2. `event_to_msg/2` - Convert Events to Messages

Transform terminal events into application-specific messages:

```elixir
def event_to_msg(%Event.Key{key: :enter}, state) do
  {:msg, {:submit, state.input}}
end

def event_to_msg(%Event.Key{key: :escape}, _state) do
  {:msg, :cancel}
end

def event_to_msg(%Event.Mouse{action: :click, x: x, y: y}, _state) do
  {:msg, {:clicked, x, y}}
end

def event_to_msg(_event, _state), do: :ignore
```

Return values:
| Return | Effect |
|--------|--------|
| `{:msg, message}` | Send message to `update/2` |
| `:ignore` | Discard the event |
| `:propagate` | Pass to parent component |

### 3. `update/2` - Handle Messages

Process messages and return new state with optional commands:

```elixir
def update(:increment, state) do
  {%{state | count: state.count + 1}, []}
end

def update({:set_name, name}, state) do
  {%{state | name: name}, []}
end

# Commands for side effects (async operations)
def update(:load_data, state) do
  {state, [Command.timer(0, :do_load_data)]}
end

def update(:do_load_data, state) do
  case fetch_data() do
    {:ok, data} -> 
      {%{state | data: data, loading: false}, []}
    {:error, reason} -> 
      {%{state | error: reason, loading: false}, []}
  end
end
```

Return format: `{new_state, commands}`

### 4. `view/1` - Render State

Pure function that transforms state into render tree:

```elixir
def view(state) do
  stack(:vertical, [
    header(state),
    main_content(state),
    footer(state)
  ])
end
```

The view function must be pure - same input state always produces same output.

## TUI Design Principles

### Layout Patterns

Use TermUI's layout primitives for responsive designs:

```elixir
# Vertical stack
stack(:vertical, [widget1, widget2, widget3])

# Horizontal stack  
stack(:horizontal, [sidebar, main_panel])

# Grid layout
grid([ 
  [header, header],
  [sidebar, main]
], 
  [Constraint::Percentage(20), Constraint::Percentage(80)],
  [Constraint::Percentage(30), Constraint::Percentage(70)]
)
```

### Component-Based Design

Break UI into independent, reusable components:

```elixir
defmodule MyApp.DataTable do
  use TermUI.Elm
  
  # Each component manages its own state
  def init(opts) do
    %{data: opts.data, selected: nil, sort: :asc}
  end
  
  # Components communicate via messages
  def event_to_msg(%Event.Key{key: "s"}, _state), do: {:msg, :toggle_sort}
  def update(:toggle_sort, state) do
    sort = if state.sort == :asc, do: :desc, else: :asc
    %{state | sort: sort}
  end
end
```

### State Management Best Practices

- Keep all mutable state in central Model structs
- Never modify state directly in view functions
- Use message passing for all state changes
- Derive computed values in view rather than storing them
- Normalize complex state updates with helper functions

### Event Handling Patterns

#### Non-blocking Event Processing
```elixir
# Separate input handling from state updates
def event_to_msg(%Event.Key{key: "q"}, _state), do: {:msg, :quit_request}
def update(:quit_request, state) do
  {state, [:quit]}  # Command to actually quit
end
```

#### Keyboard Navigation Standards
- `q` / `Esc`: Quit or cancel
- `Enter`: Confirm/Select
- `Space`: Toggle/select
- `Tab` / `Shift+Tab`: Navigate between fields
- Arrow keys: Navigate within lists/grids
- `g`: Go to top
- `G`: Go to bottom
- `/`: Start search/filter
- `n` / `N`: Next/previous search match

#### Modal Dialogs
```elixir
def update(:request_delete, state) do
  {%{state | show_confirm_delete: true}, []}
end

def update(:confirm_delete, state) do
  # Perform deletion
  {%{state | items: List.delete(state.items, state.item_to_delete), 
           show_confirm_delete: false}, []}
end

def update(:cancel_delete, state) do
  %{state | show_confirm_delete: false}
end
```

## TermUI-Specific Features

### Available Widgets

TermUI provides a rich widget library:

- **Data Display**: Table, Sparkline, Gauge, BarChart, LineChart
- **Navigation**: Menu, Tabs, TreeView, SplitPane, Viewport
- **Input**: TextInput, FormBuilder, CommandPalette, PickList
- **Feedback**: Dialog, AlertDialog, Toast, LogViewer
- **BEAM Integration**: ProcessMonitor, SupervisionTreeViewer, ClusterDashboard
- **Custom**: Canvas for direct drawing

### Styling and Theming

```elixir
alias TermUI.Renderer.Style

# Basic styling
text("Hello", Style.new(fg: :cyan))

# Complex styling
text("Error", Style.new(
  fg: {255, 0, 0},      # True color RGB
  bg: {255, 255, 255}, 
  attrs: [:bold, :blink]
))

# Semantic colors (recommended)
Style.new(fg: :green)   # Success
Style.new(fg: :red)     # Error  
Style.new(fg: :yellow)  # Warning
Style.new(fg: :blue)    # Info
```

### Commands (Side Effects)

Handle async operations without blocking the UI:

```elixir
# Timer-based updates
def update(:start_clock, state) do
  {state, [Command.timer(1000, :tick)]}
end

def update(:tick, state) do
  {%{state | time: DateTime.utc_now()}, []}
end

# Async task execution
def update(:fetch_user_data, state) do
  {state, [Command.async(fn -> 
    HTTPoison.get!("https://api.example.com/user")
  end)]}
end

def update({:http_response, %{status_code: 200, body: body}}, state) do
  {:ok, data} = Jason.decode(body)
  {%{state | user_data: data, loading: false}, []}
end
```

### IEx Compatibility

TermUI applications work directly in IEx:

```elixir
# In IEx session
iex> TermUI.Runtime.run(root: MyApp.Dashboard)
# Use keyboard normally, quit returns to IEx prompt
```

Enable explicitly if needed:
```elixir
# config/config.exs
config :term_ui, iex_compatible: true
# or
export TERM_UI_IEX_MODE=true
```

## Testing Strategies

### Unit Tests

```elixir
defmodule MyApp.CounterTest do
  use ExUnit.Case
  alias TermUI.Event
  alias MyApp.Counter

  test "init sets initial state" do
    state = Counter.init([])
    assert state.count == 0
  end

  test "increment message increases count" do
    state = %{count: 5}
    {new_state, _} = Counter.update(:increment, state)
    assert new_state.count == 6
  end

  test "up arrow sends increment message" do
    event = %Event.Key{key: :up}
    assert {:msg, :increment} = Counter.event_to_msg(event, %{})
  end
end
```

### Integration Tests

Test complete user flows:
```elixir
test "user can navigate and submit form" do
  # Simulate key presses
  assert {:msg, :focus_next} = App.event_to_msg(%Event.Key{key: :tab}, %{})
  assert {:msg, :submit} = App.event_to_msg(%Event.Key{key: :enter}, %{focused: :submit_button})
end
```

## Common Patterns

### Loading States
```elixir
def init(_opts), do: %{status: :loading, data: nil}

def update(:load, state) do
  {%{state | status: :loading}, [Command.timer(0, :do_load)]}
end

def update(:do_load, state) do
  case fetch_data() do
    {:ok, data} -> 
      {%{state | status: :ready, data: data}, []}
    {:error, reason} -> 
      {%{state | status: :error, error: reason}, []}
  end
end

def view(state) do
  cond do
    state.status == :loading -> spinner()
    state.status == :error -> error_message(state.error)
    state.status == :ready -> render_content(state.data)
  end
end
```

### Form Validation
```elixir
def update({:field_changed, :email, value}, state) do
  is_valid = String.match?(value, ~r/^[^@\s]+@[^@\s]+\.[^@\s]+$/)
  error = if is_valid, do: nil, else: "Invalid email format"
  %{state | email: value, email_error: error}
end

def view(state) do
  inputs = [
    text_input(:email, state.email, 
      error: state.email_error,
      validator: &validate_email/1
    )
  ]
  form(inputs)
end
```

### Infinite Lists with Virtual Scrolling
```elixir
def update({:scrolled, offset}, state) do
  visible_start = offset
  visible_end = offset + state.viewport_size
  visible_items = Enum.slice(state.all_items, visible_start, visible_end)
  %{state | 
    scroll_offset: offset,
    visible_items: visible_items
  }
end
```

## Performance Considerations

1. **Minimize Redraws**: Only update when state actually changes
2. **Efficient Widgets**: Use built-in widgets optimized for diffing
3. **Non-blocking I/O**: Use Commands for async operations
4. **Memoization**: Cache expensive computations
5. **Virtual Scrolling**: For large datasets, only render visible items

## Installation

```elixir
# mix.exs
def deps do
  [
    {:term_ui, "~> 0.2.0"}
  ]
end
```

## Requirements

- Elixir 1.15+
- OTP 28+ (required for native raw terminal mode)
- Terminal with Unicode support
- Recommended terminals: Alacritty, Kitty, WezTerm, iTerm2, Windows Terminal

## Running Applications

```bash
# Standard execution
mix run --no-halt

# Direct execution
elixir -S mix run lib/my_app.ex

# In IEx (for development)
iex> TermUI.Runtime.run(root: MyApp.Application)
```

This unified skill provides comprehensive guidance for building terminal applications with TermUI, combining framework-specific patterns with general TUI best practices for creating robust, maintainable, and feature-rich terminal user interfaces.