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

**IMPORTANT**: Always use `@impl true` annotation for TermUI callbacks.

```elixir
@impl true
def event_to_msg(%Event.Key{key: :enter}, _state) do
  {:msg, {:submit, state.input}}
end

@impl true
def event_to_msg(%Event.Key{key: :escape}, _state) do
  {:msg, :cancel}
end

@impl true
def event_to_msg(_event, _state), do: :ignore
```

#### Understanding Event.Key

The `Event.Key` struct has two mutually exclusive fields:
- `key` - atom (`:enter`, `:left`, `:backspace`, etc.)
- `char` - string (`"a"`, `"1"`, etc.)

When `char` is present, `key` is `nil`, and vice versa.

```elixir
# Match on character keys using ~w() for strings
@impl true
def event_to_msg(%Event.Key{char: char}, _state) when char in ~w(1 2 3 4 5) do
  {:msg, {:select_tab, String.to_integer(char)}}
end

# Match on key atoms
@impl true
def event_to_msg(%Event.Key{key: k}, _state) when k in ~w(left right up down) do
  {:msg, {:navigate, k}}
end
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
@impl true
def update(:increment, state) do
  {%{state | count: state.count + 1}, []}
end

@impl true
def update({:set_name, name}, state) do
  {%{state | name: name}, []}
end

# Commands for side effects (async operations)
@impl true
def update(:load_data, state) do
  {state, [Command.timer(0, :do_load_data)]}
end

@impl true
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
@impl true
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
```

### Rendering Helpers

Import helpers in your module:

```elixir
import TermUI.Component.Helpers
alias TermUI.Renderer.Style

# Create render nodes
text("Hello", Style.new(fg: :cyan))
box([content], width: 80, style: Style.new(bg: :black))
stack(:vertical, [a, b, c])
```

**IMPORTANT**: Use keyword lists for optional arguments, not maps:

```elixir
# Correct
box([content], width: 80, style: Style.new(bg: :black))
Sidebar.render(state, sidebar_width: 30)

# Incorrect - will cause BadMapError
box([content], %{width: 80})
Sidebar.render(state, %{width: 30})
```

### Component-Based Design

Break UI into independent, reusable components:

```elixir
defmodule MyApp.Sidebar do
  use TermUI.Elm
  
  import TermUI.Component.Helpers
  
  @tabs [:workspace, :tools, :skills, :status]
  
  def render(state, opts \\ []) do
    width = Keyword.get(opts, :sidebar_width, 30)
    active = Map.get(state, :selected_tab, :status)
    
    header = box([text("[#{tab_indicator(active)}]")], width: width)
    content = box(tab_content(state, active), width: width)
    
    stack(:vertical, [header, content])
  end
  
  defp tab_indicator(active) do
    Enum.map_join(@tabs, "", fn t -> if t == active, do: "●", else: "○" end)
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
@impl true
def event_to_msg(%Event.Key{key: "q"}, _state), do: {:msg, :quit_request}

@impl true
def update(:quit_request, state) do
  {state, [:quit]}  # Command to actually quit
end
```

#### Building Custom Tab Navigation

Instead of using TermUI's Tabs widget directly (which requires complex integration), build your own:

```elixir
# In your component
def init(opts) do
  %{
    selected_tab: :status,
    tabs: [:workspace, :tools, :skills, :status, :logs]
  }
end

# Handle number keys for direct tab access
@impl true
def event_to_msg(%Event.Key{char: char}, _state) when char in ~w(1 2 3 4 5) do
  tab = Enum.at([:workspace, :tools, :skills, :status, :logs], String.to_integer(char) - 1)
  {:msg, {:sidebar_tab, tab}}
end

# Handle arrow keys for tab navigation
@impl true
def event_to_msg(%Event.Key{key: :left}, _state), do: {:msg, {:tabs_event, :left}}
@impl true
def event_to_msg(%Event.Key{key: :right}, _state), do: {:msg, {:tabs_event, :right}}

@impl true
def update({:tabs_event, %Event.Key{key: :left}}, state) do
  tabs = state.tabs
  idx = Enum.find_index(tabs, &(&1 == state.selected_tab))
  new_idx = if idx > 0, do: idx - 1, else: length(tabs) - 1
  %{state | selected_tab: Enum.at(tabs, new_idx)}
end

@impl true
def update({:tabs_event, %Event.Key{key: :right}}, state) do
  tabs = state.tabs
  idx = Enum.find_index(tabs, &(&1 == state.selected_tab))
  new_idx = rem(idx + 1, length(tabs))
  %{state | selected_tab: Enum.at(tabs, new_idx)}
end

@impl true
def update({:sidebar_tab, tab}, state), do: { %{state | selected_tab: tab}, [] }
```

#### Keyboard Navigation Standards
- `q` / `Esc`: Quit or cancel
- `Enter`: Confirm/Select
- `Space`: Toggle/select
- Arrow keys: Navigate within lists/grids
- `1-5`: Direct navigation (when building custom tabs)
- `Home` / `End`: Jump to first/last

#### Modal Dialogs
```elixir
@impl true
def update(:request_delete, state) do
  {%{state | show_confirm_delete: true}, []}
end

@impl true
def update(:confirm_delete, state) do
  {%{state | items: List.delete(state.items, state.item_to_delete), 
           show_confirm_delete: false}, []}
end

@impl true
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

**Note on Tabs Widget**: The built-in Tabs widget has a specific API requiring `id`, `label`, and `content` fields for each tab. Integration can be complex. For simpler use cases, building custom tab state as shown above is often easier.

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
@impl true
def update(:start_clock, state) do
  {state, [Command.timer(1000, :tick)]}
end

@impl true
def update(:tick, state) do
  {%{state | time: DateTime.utc_now()}, []}
end

# Async task execution
@impl true
def update(:fetch_user_data, state) do
  {state, [Command.async(fn -> 
    HTTPoison.get!("https://api.example.com/user")
  end)]}
end

@impl true
def update({:http_response, %{status_code: 200, body: body}}, state) do
  {:ok, data} = Jason.decode(body)
  {%{state | user_data: data, loading: false}, []}
end
```

### Focus System

TermUI dispatches keyboard events to the focused component. By default, events go to `:root`.

```elixir
# Events route to focused_component (default :root)
defp dispatch_event(%Event.Key{} = event, state) do
  dispatch_to_component(state.focused_component, event, state)
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

**IMPORTANT**: RenderNode is a struct, not a tuple. Access content via struct fields:

```elixir
defmodule MyApp.CounterTest do
  use ExUnit.Case
  alias TermUI.Event
  alias TermUI.Component.RenderNode
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

  # Testing view functions
  test "render returns text node with correct content" do
    state = %{text: "Hello"}
    [result] = MyApp.View.render(state)
    # Access content as struct field, NOT with elem/1
    assert result.content == "Hello"
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

@impl true
def update(:load, state) do
  {%{state | status: :loading}, [Command.timer(0, :do_load)]}
end

@impl true
def update(:do_load, state) do
  case fetch_data() do
    {:ok, data} -> 
      {%{state | status: :ready, data: data}, []}
    {:error, reason} -> 
      {%{state | status: :error, error: reason}, []}
  end
end

@impl true
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
@impl true
def update({:field_changed, :email, value}, state) do
  is_valid = String.match?(value, ~r/^[^@\s]+@[^@\s]+\.[^@\s]+$/)
  error = if is_valid, do: nil, else: "Invalid email format"
  %{state | email: value, email_error: error}
end
```

### Handling Periodic Updates

Use `Process.send_after` for polling (simpler than Commands for basic polling):

```elixir
@poll_interval 50

def init(opts) do
  Process.send_after(self(), :check_events, @poll_interval)
  %{messages: [], status: :idle}
end

@impl true
def update(:check_events, state) do
  state = drain_messages(state)
  Process.send_after(self(), :check_events, @poll_interval)
  {state, []}
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

# With workspace and mode
mix run --no-halt -- -w my_workspace -m code

# Direct execution
elixir -S mix run lib/my_app.ex

# In IEx (for development)
iex> TermUI.Runtime.run(root: MyApp.Application)
```

## Common Pitfalls

1. **Missing `@impl true`**: Always annotate callbacks
2. **Using maps instead of keyword lists**: For `box/2`, `stack/2`, etc.
3. **Using `elem/1` on RenderNode**: Access `render_node.content` instead
4. **Matching both key and char**: They're mutually exclusive in Event.Key
5. **Forgetting state fields**: Always initialize all required fields in `init/1`

This unified skill provides comprehensive guidance for building terminal applications with TermUI, combining framework-specific patterns with general TUI best practices for creating robust, maintainable, and feature-rich terminal user interfaces.
