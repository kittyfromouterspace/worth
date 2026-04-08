# TUI Redesign Proposal

## Overview

A redesign of the Worth TUI inspired by modern, visually polished terminal interfaces like Lazygit, k9s, amux, and the Charmbracelet ecosystem.

## Goals

1. **Better information density** — Show more context without clutter
2. **Visual hierarchy** — Clear distinction between user, assistant, and tool outputs
3. **Streaming clarity** — Progressive tool execution with status indicators
4. **Amux-inspired layout** — Card-based agent panes for parallel context

---

## Reference Designs

| Example | Key Inspiration |
|---------|-------------|
| [amux](https://github.com/andyrewlee/amux) | Card-based parallel agents, branch badges, status dots |
| [Lazygit](https://github.com/jesseduffield/lazygit) | Context help (`?`), inline actions, clear error states |
| [k9s](https://github.com/derailed/k9s) | Real-time monitoring, command palette (`:`), split panes |
| [Charm Bubble Tea](https://github.com/charmbracelet/bubbletea) | Smooth animations, component system |

---

## Proposed Layout

```
┌────────────────────────────────────────────────────────────────────────────┐
│  Worth — workspace [mode]                              [status]  $0.0012      │
├──────────────────────────────────┬───────────────────────────────────────┤
│                                  │                                       │
│  Chat History                    │  Sidebar                               │
│  ────────────────────            │  ─────────                            │
│  > User message                 │  [○] [●] [○] [○] [○]              │
│    Assistant response...           │                                       │
│    ┌─────────────────────┐     │  Workspace: current                     │
│    │ tool: read_file   │     │    ├─ AGENTS.md                        │
│    │ path: foo.ex   │     │    ├─ IDENTITY.md                      │
│    └─────────────────────┘     │    └─ files/                         │
│    ...                         │                                       │
│                                  │  Tools: read_file, write_file, ...      │
│  ┌─ Input ─────────────────┐     │                                       │
│  │ _                   │     │  Skills: core (5), installed (12)     │
│  └─────────────────────┘     │                                       │
├──────────────────────────────────┴───────────────────────────────────────┤
│  ? help  :cmd  /search                                              │
└────────────────────────────────────────────────────────────────────────────┘
```

### Regions

| Region | Current | Redesigned |
|--------|---------|-----------|
| **Header** | Simple status line | Status + cost + model indicator |
| **Chat** | Flat message list | Card-based blocks with syntax highlighting |
| **Sidebar** | Right panel (fixed split) | Tabbed (workspace, tools, skills, status, logs) |
| **Input** | Bottom line | Prominent with keybinding hints |

### Key Changes

1. **Card-based message blocks** — Each assistant turn as a contained "card" with header showing role, timing
2. **Tool execution panel** — Expandable tool calls with status indicators (○ pending, ● running, ✓ done, × failed)
3. **Sidebar tabs** — Replaces sidebar content switching with visual tab dots
4. **Status header** — Real-time cost + turn count + model info
5. **Keybinding bar** — Always-visible command hints at bottom

---

## Current Functionality Mapping

### Brain State → UI

| Brain Field | Current UI | Proposed |
|-----------|-----------|---------|
| `status` | `state.status` (:idle/:running) | Status dot + header indicator |
| `current_workspace` | sidebar tab | Left sidebar: workspace tree |
| `mode` (:code/:research/etc) | hidden | Header badge |
| `cost_total` | sidebar (Status tab) | Header (always visible) |
| `history` | chat messages | Card-styled chat area |
| `tool_permissions` | implicit | Tools tab in sidebar |
| `pending_approval` | input block | Tool card with " Approve? " prompt |

### Commands → Keybindings

Current slash commands mapped to vim-style keybindings:

| Current | Proposed | Action |
|---------|----------|--------|
| `/mode code` | `mc` | Switch to code mode |
| `/mode research` | `mr` | Switch to research mode |
| `/workspace switch <name>` | `mw` | Switch workspace |
| `/session resume <id>` | `ms` | Resume session |
| `/skill list` | sidebar | Skills tab |
| `/tool list` | sidebar | Tools tab |
| `/help` | `?` | Show help overlay |

### New Keybindings (Amux/Lazygit inspired)

| Key | Action |
|-----|--------|
| `?` | Show help/command reference |
| `:` | Command palette (k9s style) |
| `/` | Search within chat |
| `Tab` | Cycle sidebar tabs |
| `Esc` | Cancel / clear input / back |
| `Ctrl-l` | Clear screen / redraw |
| `gg` / `G` | Jump to top/bottom of chat |

---

## Visual Design

### Color Palette

Inspired by Charm's dark theme (slate/charcoal):

| Element | Color |
|---------|-------|
| Background | `#1a1b26` (deep slate) |
| Card BG | `#24283b` (elevated slate) |
| Border | `#414868` (muted blue-gray) |
| Text | `#c0caf5` (soft white) |
| Accent | `#7aa2f7` (bright blue) |
| Success | `#9ece6a` (soft green) |
| Warning | `#e0af68` (soft orange) |
| Error | `#f7768e` (soft red) |
| User | `#bb9af7` (purple) |
| Assistant | `#7aa2f7` (blue) |

### Status Indicators

```
○  idle/pending    (hollow circle)
●  running       (filled circle)  
✓  success       (checkmark)
×  failed        (X)
⚠  warning       (warning)
```

### Typography

- **Font**: System monospace (terminal default)
- **Headings**: Bold + uppercase
- **Code/Tools**: Brackets: `[tool_name args]`
- **Timestamps**: Dimmed, right-aligned

---

## Implementation Plan

### Phase 1: Visual Foundation

1. **Theme module** — Define color palette and style constants
2. **Update Chat rendering** — Card-based message blocks
3. **Add status indicators** — Tool execution states

### Phase 2: Layout Improvements

4. **Redesign Header** — Status + cost + model in header
5. **Sidebar tab dots** — Visual tab indicators
6. **Keybinding bar** — Bottom hint line

### Phase 3: Interaction

7. **Command palette** — `:` to open
8. **Help overlay** — `?` key
9. **Search within chat** — `/` key

---

## Component Mapping

### Existing → Redesigned

```
Worth.UI.Root          → Worth.UI.Root
  ├─ Header.render    → Header.render (enhanced)
  ├─ Chat.render    → Chat.render (cards)
  ├─ Sidebar.render → Sidebar.render (tabs)
  └─ Input.render  → Input.render (keyhint)

Worth.UI.Message    → Worth.UI.Message
  ├─ to_blocks     → to_blocks (card wrapper)

Worth.UI.Theme     → Worth.UI.Theme
  ├─ style_for   → style_for (expand palette)
  └─ (new)     → card_style, tool_status_style
```

### New Components

```
Worth.UI.Keybinds
  ├─ render/1      — Bottom keyhint bar
  ├─ help/0       — Help overlay  
  ├─ palette/0     — Command palette
  └─ search/1     — Search within chat

Worth.UI.ToolPane
  ├─ render/1      — Tool execution card
  ├─ status/1      — Status indicator
  └─ expand/1      — Expandable details
```

---

## File Structure

```
lib/worth/ui/
  ├── root.ex           # Main Elm (minimal changes)
  ├── chat.ex          # Card-based rendering
  ├── header.ex        # Enhanced header
  ├── sidebar.ex       # Tab dot navigation
  ├── input.ex        # Keyhint bar support
  ├── message.ex      # Card wrapper
  ├── theme.ex        # Expanded palette
  ├── keybinds.ex    # NEW: keybinding management
  └── tool_pane.ex    # NEW: tool execution cards
```

---

## Backwards Compatibility

- All existing keybindings remain functional
- Slash commands (`/mode`, `/workspace`, etc.) continue to work
- UI adapts gracefully to narrow terminals (falls back to current layout)

---

## References

- [amux](https://github.com/andyrewlee/amux) — Parallel agent TUI
- [Lazygit](https://github.com/jesseduffield/lazygit) — Git TUI reference
- [k9s](https://github.com/derailed/k9s) — Kubernetes TUI reference
- [Charmbracelet/bubbletea](https://github.com/charmbracelet/bubbletea) — Go TUI framework
- [Charmbracelet/lipgloss](https://github.com/charmbracelet/lipgloss) — Styling system