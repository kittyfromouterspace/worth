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

## Viewport (Scrollable Regions)

TermUI has a native Viewport render node for clipped/scrollable content.
The renderer rasterizes the full content into a temporary buffer, then copies
only the visible region based on scroll offsets.

```elixir
# Viewport render node — use this for chat scroll, log panels, etc.
%{
  type: :viewport,
  content: stack(:vertical, all_message_blocks),
  scroll_x: 0,
  scroll_y: state.chat_scroll,   # offset into content
  width: panel_width,
  height: panel_height
}
```

### Scroll state management

```elixir
# In state
%{chat_scroll: 0, chat_content_height: 0}

# In event_to_msg
def event_to_msg(%Event.Key{key: :page_up}, _state), do: {:msg, :scroll_up}
def event_to_msg(%Event.Key{key: :page_down}, _state), do: {:msg, :scroll_down}

# In update
def update(:scroll_up, state) do
  new_scroll = max(0, state.chat_scroll - div(state.height, 2))
  {%{state | chat_scroll: new_scroll}, []}
end

def update(:scroll_down, state) do
  max_scroll = max(0, state.chat_content_height - state.height + 4)
  new_scroll = min(state.chat_scroll + div(state.height, 2), max_scroll)
  {%{state | chat_scroll: new_scroll}, []}
end
```

### Auto-scroll to bottom on new messages

```elixir
# After appending a message, snap scroll to bottom unless user scrolled up
defp auto_scroll(state) do
  if state.chat_scroll >= state.chat_content_height - state.height do
    %{state | chat_scroll: max(0, length(state.messages) * 2 - state.height + 4)}
  else
    state  # user scrolled up — don't override
  end
end
```

## Background Fills

**IMPORTANT**: `box` with `style: Style.new(bg: color)` does NOT fill empty
space — it only passes the bg to child text nodes. Only the `:overlay` node
type calls `fill_background` (and it requires absolute positioning).

### Correct approach: pad text lines

```elixir
# Pad each text node to the panel width with bg-coloured spaces
defp pad_line(%{type: :text, content: content, style: style}, width, bg) do
  padding = max(0, width - String.length(content))
  padded = content <> String.duplicate(" ", padding)
  merged = Style.merge(style || Style.new(), Style.new(bg: bg))
  text(padded, merged)
end
```

### Overlay nodes (for floating panels/dialogs only)

```elixir
# Raw map — NOT a RenderNode helper, construct directly
%{
  type: :overlay,
  content: dialog_content,
  x: col,        # 0-indexed absolute screen position
  y: row,
  width: w,
  height: h,
  bg: Style.new(bg: {40, 40, 60})   # fills entire region
}
```

## Vertical Dividers in Horizontal Stacks

**PITFALL**: `text("│\n│\n│", style)` renders as a single text node.
In a horizontal stack, TermUI treats the entire multiline string as one
line — only the first character appears.

```elixir
# WRONG — only first │ shows
text(Enum.join(for _ <- 1..height, do: "│"), "\n"), style)

# CORRECT — each │ is a separate text node in a vertical stack
def vertical_divider(height) do
  lines = for _ <- 1..height, do: text("│", Style.new(fg: palette(:surface2)))
  stack(:vertical, lines)
end
```

## Render Node Types Reference

| Constructor | Type atom | Purpose |
|-------------|-----------|---------|
| `text(content, style)` | `:text` | Styled text |
| `stack(direction, children)` | `:stack` | Layout (`:vertical` / `:horizontal`) |
| `box(children, opts)` | `:box` | Container with width/height constraints |
| `styled(style, child)` | `:styled` | Style wrapper |
| `fragment(children)` | `:fragment` | Multiple nodes without layout |
| `cells([...])` | `:cells` | Raw positioned cells |
| `%{type: :viewport, ...}` | `:viewport` | Scrollable clipped region |
| `%{type: :overlay, ...}` | `:overlay` | Absolute-positioned floating panel |

## Rendering Pipeline (5 stages)

```
view(state) → Render Tree → NodeRenderer → Buffer (ETS) → Diff → ANSI → Terminal
```

1. **View**: component returns render tree (pure function)
2. **Rasterize**: NodeRenderer walks tree, writes cells to ETS buffer
3. **Diff**: compare current vs previous buffer, find changed spans
4. **Serialize**: convert diff ops to ANSI escape sequences (style delta encoding)
5. **Output**: write iodata to terminal

Budget: 16ms per frame (60 FPS). Typical render: 1.4–6.5ms.

## Buffer & Cell Internals

```elixir
# Double-buffered ETS tables for flicker-free updates
# Access via persistent_term (O(1), no GenServer)
:persistent_term.get({BufferManager, :current})

# Cell structure
%Cell{
  char: "A",
  fg: :cyan,                    # atom, 256-int, or {r,g,b} tuple
  bg: :default,
  attrs: MapSet.new([:bold]),
  width: 1                      # 2 for CJK/emoji
}
```

Wide characters (CJK/emoji) occupy 2 cells — primary + placeholder.

## Testing Framework

TermUI ships a full test harness. Use it for UI component tests.

```elixir
defmodule MyComponentTest do
  use ExUnit.Case, async: true
  use TermUI.Test.Assertions

  alias TermUI.Test.{ComponentHarness, EventSimulator, TestRenderer}

  test "renders initial state" do
    {:ok, harness} = ComponentHarness.mount_test(MyComponent, [])
    harness = ComponentHarness.render(harness)
    renderer = ComponentHarness.get_renderer(harness)

    assert_text_exists(renderer, "expected text")
    ComponentHarness.unmount(harness)
  end

  test "handles key events" do
    {:ok, harness} = ComponentHarness.mount_test(MyComponent, [])
    harness = ComponentHarness.event_cycle(harness, EventSimulator.simulate_key(:enter))

    assert ComponentHarness.get_state(harness).submitted == true
    ComponentHarness.unmount(harness)
  end
end
```

### Key test APIs

| Module | Function | Purpose |
|--------|----------|---------|
| `ComponentHarness` | `mount_test/2` | Mount component for testing |
| `ComponentHarness` | `render/1` | Trigger render cycle |
| `ComponentHarness` | `send_event/2` | Send single event |
| `ComponentHarness` | `event_cycle/2` | Send event + render |
| `ComponentHarness` | `get_state/1` | Read component state |
| `EventSimulator` | `simulate_key/1,2` | Create key event |
| `EventSimulator` | `simulate_type/1` | Type string → key events |
| `EventSimulator` | `simulate_click/3` | Mouse click event |
| `EventSimulator` | `simulate_scroll_up/2` | Scroll event |
| `TestRenderer` | `find_text/2` | Find text → `[{row, col}]` |
| Assertions | `assert_text_exists/2` | Text appears somewhere |
| Assertions | `assert_style/3` | Style at position |

## Mouse Events

TermUI supports mouse tracking (click, drag, scroll).

```elixir
%Event.Mouse{
  action: :press | :release | :click | :drag | :scroll_up | :scroll_down,
  button: :left | :middle | :right | nil,
  x: integer,    # 0-indexed
  y: integer,
  modifiers: [:ctrl, :alt, :shift]
}
```

Enable mouse in runtime opts or handle in `event_to_msg`:

```elixir
@impl true
def event_to_msg(%Event.Mouse{action: :scroll_up}, _state), do: {:msg, :scroll_up}
def event_to_msg(%Event.Mouse{action: :scroll_down}, _state), do: {:msg, :scroll_down}
def event_to_msg(%Event.Mouse{action: :click, x: x, y: y}, _state) do
  {:msg, {:click, x, y}}
end
```

## Performance Considerations

1. **Minimize Redraws**: Only update when state actually changes
2. **Efficient Widgets**: Use built-in widgets optimized for diffing
3. **Non-blocking I/O**: Use Commands for async operations
4. **Memoization**: Cache expensive computations
5. **Viewport for Scrolling**: Use native viewport nodes — content outside the visible area is never diffed or serialized
6. **Style Delta Encoding**: Renderer only emits changed SGR attributes between cells

## Common Pitfalls

1. **Missing `@impl true`**: Always annotate callbacks
2. **Using maps instead of keyword lists**: For `box/2`, `stack/2`, etc.
3. **Using `elem/1` on RenderNode**: Access `render_node.content` instead
4. **Matching both key and char**: They're mutually exclusive in Event.Key
5. **Forgetting state fields**: Always initialize all required fields in `init/1`
6. **Box bg doesn't fill**: Use line-padding or overlay nodes, not box style bg
7. **Multiline text in horizontal stacks**: Use `stack(:vertical, ...)` with individual text nodes
8. **Doing I/O in update/2**: Use `{:async, fun, msg}` command instead
9. **Not cleaning up tests**: Always call `ComponentHarness.unmount/1`
