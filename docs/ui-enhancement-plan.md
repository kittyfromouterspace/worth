# UI Enhancement Plan — amux-Inspired Redesign

Comprehensive plan to rebuild Worth's TUI with richer visuals, a workspace file
browser, and a live agent/subagent status panel.  Inspired by
[amux](https://github.com/andyrewlee/amux) (multi-agent terminal dashboard).

---

## Design Goals

1. **More colour & visual hierarchy** — true-colour RGB palette, surface layers,
   semantic accent colours, animated spinners for running work.
2. **Workspace file browser** — new sidebar tab showing the file tree of the
   active workspace so the user can see what the agent is touching.
3. **Live agent panel** — new sidebar tab showing the main agent plus any
   subagents spawned for tasks, with real-time status, cost, and elapsed time.
4. **Better tab bar** — replace dot indicators with labelled tabs, colour-coded
   active state.
5. **Tighter information density** — amux-style compact cards for tool calls,
   agent status rows with braille spinners.

---

## Current UI Architecture (as built)

```
Root (TermUI.Elm)
├── Header     — spinner/status + workspace + mode + turns + cost + model + agent count
├── Separator
├── Body (3-panel layout)
│   ├── Left panel  — workspace name, file tree, agents (always-on, no tabs)
│   ├── Divider
│   ├── Chat pane   — messages + streaming text (tinted bg: {35,35,52})
│   ├── Divider
│   └── Right panel — 5 tabs: Status, Usage, Tools, Skills, Logs (keys 1-5)
└── Input      — status-coloured prompt + keyhint bar
```

Files: `root.ex`, `header.ex`, `chat.ex`, `input.ex`, `sidebar.ex`,
`message.ex`, `theme.ex`, `events.ex`, `keybinds.ex`, `commands.ex`,
`log_buffer.ex`, `log_handler.ex`

---

## Phase 1 — Theme & Visual Refresh

**Goal:** Bring the colour palette up to amux quality without changing layout.

### 1.1  True-colour palette in `theme.ex`

Replace the 16-colour `@palette` with an amux-inspired semantic palette using
RGB tuples.  Add surface hierarchy (surface0–surface3) for depth.

```elixir
@palette %{
  bg:             {30, 30, 46},      # base background (Catppuccin Mocha)
  surface0:       {49, 50, 68},      # raised cards / panels
  surface1:       {69, 71, 90},      # hover / selected rows
  surface2:       {88, 91, 112},     # borders
  text:           {205, 214, 244},   # primary text
  subtext:        {166, 173, 200},   # secondary / muted text
  overlay:        {108, 112, 134},   # dim overlays

  accent:         {137, 180, 250},   # blue — primary accent
  accent_alt:     {180, 190, 254},   # lavender — secondary accent
  success:        {166, 227, 161},   # green
  warning:        {249, 226, 175},   # yellow / peach
  error:          {243, 139, 168},   # red / maroon
  info:           {148, 226, 213},   # teal

  user:           {166, 227, 161},   # green — user messages
  assistant:      {137, 180, 250},   # blue — assistant messages
  tool:           {203, 166, 247},   # mauve — tool calls
  thinking:       {108, 112, 134},   # overlay — thinking text
}
```

Add a `:catppuccin` theme variant alongside existing `:dark`, `:light`,
`:minimal`.

### 1.2  Richer header styling

- Use `accent` colour for the "worth" brand text.
- Mode badge gets a subtle background tint (surface0).
- Cost uses `warning` colour.  Model label uses `subtext`.
- Status indicator: idle = `○` in subtext, running = braille spinner in accent,
  error = `×` in error colour.

### 1.3  Message card improvements in `message.ex`

- User messages: green left-bar indicator `▍` + green header.
- Assistant messages: blue left-bar `▍` + blue header.
- Tool calls: mauve `▍`, show tool name bold + input as dim JSON preview.
- Tool results: success green or error red based on status, with `✓`/`×`.
- Thinking: dim italic text with `…` animation.

### 1.4  Braille spinner utility

Add `Worth.UI.Spinner` module:

```elixir
@frames ~w(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
@interval 80  # ms per frame

def frame(tick), do: Enum.at(@frames, rem(tick, length(@frames)))
```

Drive from `Root.update(:check_events, …)` which already fires every 50 ms —
increment a `spinner_tick` counter in state.

**Status:** `[x]` Complete

---

## Phase 2 — Tab Bar Redesign

**Goal:** Replace dot indicators with labelled tabs; add two new tabs (Files,
Agents).

### 2.1  New tab list

```elixir
@tabs [
  {:workspace, "WS",     "1"},
  {:files,     "Files",  "2"},
  {:agents,    "Agents", "3"},
  {:tools,     "Tools",  "4"},
  {:skills,    "Skills", "5"},
  {:status,    "Status", "6"},
  {:usage,     "Usage",  "7"},
  {:logs,      "Logs",   "8"},
]
```

### 2.2  Rendered tab bar

Instead of `● ○ ○ ○ ○ ○` show:

```
 1·WS  2·Files  3·Agents  4·Tools  5·Status  6·Logs
 ─────────────────────────────────────────────────────
```

Active tab gets `accent` colour + bold; inactive tabs get `subtext`.
Number prefix acts as both label and shortcut hint.

### 2.3  Update `root.ex` key handling

Extend numeric key handling from `1-5` → `1-8`.  Map each to the new tab atom.
Arrow keys cycle through the full list.

**Status:** `[x]` Complete

---

## Phase 3 — Workspace File Browser Tab

**Goal:** New `:files` sidebar tab showing the file tree of the current
workspace directory.

### 3.1  File tree data

On tab activation (and periodically — every 2 s while visible), enumerate
workspace files:

```elixir
defp scan_workspace_files(workspace_path) do
  workspace_path
  |> Path.join("**/*")
  |> Path.wildcard()
  |> Enum.reject(&File.dir?/1)
  |> Enum.map(&Path.relative_to(&1, workspace_path))
  |> Enum.sort()
  |> build_tree()
end
```

### 3.2  Tree rendering

Display as indented tree with file-type icons:

```
 Files (personal)
 ─────────────────
  IDENTITY.md
  AGENTS.md
  .worth/
    skills.json
    transcript.jsonl
  src/
    main.ex
    helper.ex
```

- Directories: `subtext` colour, trailing `/`
- Files: `text` colour; `.ex` files get `accent`, `.md` files get `info`
- Hidden files (`.worth/`): `overlay` colour

### 3.3  State additions to `root.ex`

```elixir
workspace_files: [],        # cached file list
files_last_scan: nil,       # monotonic timestamp of last scan
```

Scan on workspace switch, on `:files` tab activation, and every 2 s while the
files tab is selected (driven by the existing `check_events` tick — check
elapsed time, not a separate timer).

### 3.4  New module: `Worth.UI.FileBrowser`

Render function takes `(state, opts)`, returns a vertical stack of file lines.
Keeps rendering pure — scanning happens in `update/2`.

**Status:** `[x]` Complete

---

## Phase 4 — Agent Tracking Infrastructure

**Goal:** Build the backend needed to populate the Agents tab.  This is the
heaviest phase because Worth currently has no agent registry.

### 4.1  `Worth.Agent.Tracker` GenServer

New module at `lib/worth/agent/tracker.ex`.  Single named process.

```elixir
defmodule Worth.Agent.Tracker do
  use GenServer

  # State: %{agents: %{session_id => agent_info}}
  # agent_info: %{
  #   session_id: String.t(),
  #   parent_session_id: String.t() | nil,
  #   depth: non_neg_integer(),
  #   status: :running | :idle | :done | :error,
  #   mode: atom(),
  #   workspace: String.t(),
  #   started_at: integer(),      # System.monotonic_time(:millisecond)
  #   cost: float(),
  #   turns: non_neg_integer(),
  #   current_tool: String.t() | nil,
  #   label: String.t() | nil,    # human-readable task description
  # }

  def register(session_id, opts)
  def update_status(session_id, status)
  def update_tool(session_id, tool_name)
  def update_cost(session_id, cost)
  def unregister(session_id)
  def list_active() :: [agent_info]
  def list_active(workspace) :: [agent_info]
end
```

### 4.2  Telemetry hooks

Attach to existing AgentEx telemetry events in `Worth.Telemetry` (or a new
`Worth.Agent.TelemetryHandler`):

| Telemetry event | Handler action |
|-----------------|----------------|
| `[:agent_ex, :session, :start]` | `Tracker.register/2` |
| `[:agent_ex, :session, :stop]` | `Tracker.unregister/1` |
| `[:agent_ex, :subagent, :spawn]` | `Tracker.register/2` with parent_session_id |
| `[:agent_ex, :subagent, :complete]` | `Tracker.unregister/1` |
| `[:agent_ex, :subagent, :error]` | `Tracker.update_status/2` → :error |
| `[:agent_ex, :tool, :start]` | `Tracker.update_tool/2` |
| `[:agent_ex, :tool, :stop]` | `Tracker.update_tool/2` → nil |

### 4.3  PubSub broadcast

On every Tracker state change, broadcast to `"agents:updates"` via
`Worth.PubSub`.  The UI subscribes in `init/1`.

### 4.4  Wire into Brain

When `Worth.Brain` calls `AgentEx.run/1`, pass a `:session_id` and ensure the
brain's callbacks forward tool events with the session_id so the Tracker can
correlate.

**Status:** `[x]` Complete

---

## Phase 5 — Agents Sidebar Tab

**Goal:** Render the live agent panel using data from `Worth.Agent.Tracker`.

### 5.1  New module: `Worth.UI.AgentsPanel`

```elixir
def render(state, opts \\ []) do
  agents = Worth.Agent.Tracker.list_active(state.workspace)

  if agents == [] do
    [text("  No active agents", Style.new(fg: subtext))]
  else
    agents
    |> Enum.sort_by(& &1.depth)
    |> Enum.flat_map(&agent_row(&1, state.spinner_tick))
  end
end
```

### 5.2  Agent row layout

```
 Agents
 ─────────────────
  ⠹ main agent         00:42  $0.0312
      mode: code  turn: 5
      tool: read_file
  ⠸ ├─ subagent-1      00:12  $0.0045
      task: "explore test files"
      tool: bash
  ✓ └─ subagent-2      00:08  $0.0021
      done
```

- Running agents: braille spinner (from Phase 1.4) in `accent` colour
- Completed: `✓` in `success`
- Errored: `×` in `error`
- Subagent indentation uses tree lines `├─` / `└─` based on depth
- Elapsed time right-aligned, cost at far right
- Current tool shown as dim subtext line

### 5.3  State additions

```elixir
active_agents: [],     # cached from Tracker, refreshed on PubSub or poll
```

Subscribe to `"agents:updates"` in `init/1`.  On each PubSub message,
re-fetch `Tracker.list_active/1` and update state.

**Status:** `[x]` Complete

---

## Phase 6 — Header & Input Polish

**Goal:** Refine header and input bar with the new palette and layout.

### 6.1  Header redesign

Current: `○ worth │ workspace │ [code] │ t5 │ $0.0012 (model)`

New layout with coloured segments:

```
 ● worth  personal  [code]  t5  $0.0312  claude-opus-4  ⠹ 2 agents
```

- Add agent count badge at the right (from Tracker).
- Status indicator uses spinner when running.
- Each segment uses its semantic colour from the new palette.
- Segments separated by spaces (no `│` — cleaner).

### 6.2  Input bar

- Prompt indicator changes colour based on status:
  idle → `subtext`, running → `accent` (pulsing), error → `error`.
- Keyhints use `surface1` background tint for key badges: `[?]` in a box.

### 6.3  Separator

Replace solid `─` with a subtle double-line or gradient using `surface2` colour.

**Status:** `[x]` Complete

---

## Phase 7 — Chat Pane Improvements

**Goal:** Better message rendering, scrolling, and density.

### 7.1  Message grouping

Group consecutive tool_call + tool_result pairs into collapsible cards.
Show only the tool name + status inline; expand on selection.

### 7.2  Scroll position tracking

Add `chat_scroll_offset` to state.  Page Up/Down and mouse wheel (if TermUI
supports it) scroll through message history.  Auto-scroll to bottom on new
messages unless the user has scrolled up.

### 7.3  Markdown rendering (stretch)

Basic markdown support for assistant messages: bold, italic, code blocks with
syntax highlighting using `surface0` background.

**Status:** `[x]` Complete

---

## Implementation Order

| Phase | Description | Dependencies | Estimated effort |
|-------|-------------|-------------|------------------|
| **1** | Theme & visual refresh | None | Small — palette + style changes |
| **2** | Tab bar redesign | Phase 1 (colours) | Small — sidebar.ex + root.ex |
| **3** | File browser tab | Phase 2 (tab slot) | Medium — new module + scanning |
| **4** | Agent tracking infra | None (can parallel with 1-3) | Medium — new GenServer + telemetry |
| **5** | Agents panel tab | Phase 2 + 4 | Medium — new render module |
| **6** | Header & input polish | Phase 1 + 4 (agent count) | Small |
| **7** | Chat improvements | Phase 1 | Medium — scroll state + grouping |

**Recommended order:** 1 → 2 → 3 → 4 → 5 → 6 → 7

Phases 1-3 are pure UI work with no backend changes.  Phase 4 is the only
backend piece.  This lets us ship visual improvements quickly while the tracking
infrastructure bakes.

---

## Files to Create

| File | Purpose |
|------|---------|
| `lib/worth/ui/spinner.ex` | Braille spinner utility |
| `lib/worth/ui/file_browser.ex` | Workspace file tree renderer |
| `lib/worth/ui/agents_panel.ex` | Live agent status renderer |
| `lib/worth/agent/tracker.ex` | Agent session registry GenServer |
| `lib/worth/agent/telemetry_handler.ex` | Telemetry → Tracker bridge |

## Files to Modify

| File | Changes |
|------|---------|
| `lib/worth/ui/theme.ex` | New RGB palette, surface hierarchy, catppuccin variant |
| `lib/worth/ui/sidebar.ex` | Labelled tab bar, two new tab slots, tree rendering |
| `lib/worth/ui/root.ex` | New state fields, 1-8 keys, PubSub subscription, spinner tick |
| `lib/worth/ui/header.ex` | Coloured segments, spinner, agent count badge |
| `lib/worth/ui/input.ex` | Status-aware prompt colour, styled key badges |
| `lib/worth/ui/message.ex` | Left-bar indicators, tool call cards, colour upgrade |
| `lib/worth/ui/events.ex` | Handle agent tracker PubSub messages |
| `lib/worth/ui/keybinds.ex` | Update tab references for new count |
| `lib/worth/application.ex` | Start Agent.Tracker in supervision tree |
| `lib/worth/brain.ex` | Pass session_id to callbacks, register with Tracker |
