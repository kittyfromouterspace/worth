# Worth Design System

> **Make it worth it.**

This is the design system for **Worth** — a desktop AI agent and research bench for power users. It documents two living visual systems:

1. **Bedrock** — Worth's flagship, canonical brand theme (obsidian, molten red, quiet).
2. **Fifth Element** — an opinionated alt theme: industrial retro-futurism inspired by Jean-Paul Gaultier's 23rd-century New York in Luc Besson's 1997 film. Orange chassis, terminal green text, CRT scanlines.

Both themes ship in-product; users pick one via `~/.worth/config.exs` → `theme: :bedrock` or `theme: :fifth_element`. This design system mirrors the production code — it is not invented.

---

## What is Worth?

Worth is two things at once:

- **A desktop agent for power users.** Native app (Tauri + Phoenix LiveView), workspace-scoped, keyboard-first. Memory, skills, MCP, multi-model routing, cost tracking and tool traces are surfaced — not hidden.
- **A research bench.** An "x-ray" mode lets users trace calls, inspect context windows, swap system prompts, and watch how an agent and model behave under different setups.

There is also a **cloud sync** offering (`worth.cloud`), but desktop is the primary surface today.

### Who it's for

Engineers who ship with LLMs. Researchers doing eval and prompt engineering. People who grew up in terminals and still live there. **Not** a gentle-onboarding consumer chatbot.

---

## Sources (for the reader)

This system was built from the following sources. You may not have access — they are recorded for traceability.

| Source | Path / URL | What's in it |
|---|---|---|
| Repository | `github.com/kittyfromouterspace/worth` (branch `main`) | The Elixir/Phoenix codebase — `BRAND.md`, `brand/`, `lib/worth/theme/*.ex`, `lib/worth_web/components/*.ex` |
| Brand doc | `worth/BRAND.md` | Canonical Bedrock brand guidelines (colors, type, voice) |
| Brief | `worth/brand/brief.md` | Earlier brand system proposal — some items deprecated |
| Logo | `worth/brand/logo.png` | Textured stone-+-lava "W" — marketing only |
| Moodboard | `worth/brand/brand_ideas.png` | Full brand exploration sheet |
| Theme code | `worth/lib/worth/theme/{bedrock,fifth_element,cyberdeck,standard}.ex` | CSS + color mappings |
| UI components | `worth/lib/worth_web/components/{brand,chat,settings}.ex` | LiveView components — source of truth for UI kit |
| Fifth Element reference | [The Art of Moebius / ASC](https://theasc.com/articles/fantastic-voyage-creating-the-futurescape-for-the-fifth-element) | Moebius-style moodboard |

---

## Index

```
README.md                    # this file
SKILL.md                     # Agent Skill manifest for Claude Code
colors_and_type.css          # all tokens (Bedrock + Fifth Element)
fonts/                       # Space Grotesk, Inter, JetBrains Mono, Orbitron, Fira Code (via @import)
assets/                      # logos, moodboard
preview/                     # one HTML file per design-system card
ui_kits/
  worth_desktop_bedrock/     # canonical Worth desktop UI kit
  worth_desktop_fifth_element/ # Fifth Element alt-theme UI kit
```

Preview cards power the **Design System** tab. UI kits are interactive click-thrus of the product. Open `ui_kits/worth_desktop_bedrock/index.html` for the canonical shell; `ui_kits/worth_desktop_fifth_element/index.html` for the Fifth Element refit.

---

## Content fundamentals

Worth's voice is set by `BRAND.md`. It is tight, declarative, and anti-hype. Use this as a hard constraint — the product does not talk like a SaaS landing page.

### Principles

1. **Say the thing.** No throat-clearing, no "empower", no "revolutionize".
2. **Respect the reader.** Assume technical literacy. Don't over-explain.
3. **Short sentences do most of the work.**
4. **Show, don't promise.** If the product does X, say it does X. Don't say "intelligent X".
5. **No exclamation marks. Ever.**
6. **No emoji in product.** They occasionally appear on the marketing site; never in the app.
7. **Casing:** lowercase for the wordmark ("worth"), Sentence case for headings, lower-case mono for data labels (`input`, `output`, `cache read`).
8. **You / we:** the product is "Worth", not "we". Avoid first-person plural marketing voice. Address the user directly with "you" only when it's functional (button hints, empty states).

### Words we use

*working, bench, surface, routing, memory, skills, workspace, signal, depth, measure, inspect, observe, compose, ship, bedrock, strata, load-bearing.*

### Words we do not use

*empower, unleash, revolutionize, transform, seamlessly, magical, effortless, intelligent, smart, cutting-edge, next-gen, game-changing, AI-powered* (it's obviously AI-powered), *synergy, leverage (as a verb).*

### Voice examples

> **Bad:** "Worth empowers you to unlock the full potential of your AI workflows."
> **Good:** "Worth runs the agent loop. You inspect what it did."

> **Bad:** "Intelligent memory that learns from every conversation."
> **Good:** "Memory: vector + knowledge graph. Queryable. Local."

> **Bad:** "Experience the future of AI development."
> **Good:** "A bench for serious AI work."

### Taglines (in priority order)

1. **Make it worth it.** — primary.
2. *A bench for serious AI work.*
3. *Desktop agent. Research bench. No hype.*
4. *Signal. Not hype.*

### In-product copy

- **Empty sidebar:** `(no files)` — parentheses, lowercase, dim.
- **Waiting state:** `Waiting for response...` — ellipsis char, sentence case.
- **Status:** `o idle` / `● running` / `× error` — terminal glyphs, not emoji.
- **Metrics labels:** `Duration:` `Cost:` `Turns:` `Calls:` — Title Case with trailing colon, followed by tabular-num value.

### The Fifth Element voice

The Fifth Element theme is a costume, not a new voice. Copy stays in Worth's dry, declarative register — only visual chrome changes. Do **not** write `"⚡ POWER ON ⚡"` in Fifth Element; write `power on` or `/* POWER */`.

---

## Visual foundations

### Two themes, one system

Both themes share structure (density, keyboard-first layout, monospace for data) and vary only on **chrome and color**. A component written for Bedrock should port to Fifth Element by swapping CSS custom properties, not by re-implementing.

### Bedrock (canonical)

- **Base:** Obsidian `#0B0B0D`. Dark Steel `#1A1A1E` for panels. Graphite `#2A2A2E` for elevated. Ash `#3A3A3F` for borders.
- **Accent:** Molten `#FF3B2F` — the only loud color. Budget: **one or two molten elements per screen, max.** Send / stop / active error. If everything is molten, nothing is.
- **Typography:** Space Grotesk (display) / Inter (UI) / JetBrains Mono (code, paths, IDs, costs).
- **Backgrounds:** solid obsidian. No gradients. No hero imagery. No glass, no blur.
- **Motifs:** the **heat seam** (1px molten line across the header top, 20% alpha) and **strata dividers** (1px ash rules).
- **Corners:** 4px on cards, 2px on inputs, 2px on buttons. Tight, hardware-adjacent.
- **Shadows:** none by default. The molten button may pick up a subtle shadow on `:active`. That's it.
- **Animation:** the input cursor and the **"W-pulse"** spinner — the four wedges of the Worth mark lighting up in sequence, 1.2s loop, 150ms stagger, inherits `currentColor`. Purpose-built for Worth; replaces the over-used braille-dot spinner. Nothing else fades in. Status updates are instant.
- **Hover:** text-muted → text-primary. Buttons bump to Heat Glow `#FF6A3D`. No glow, no scale.
- **Press:** molten goes 10% darker (`#CC2E24`). That's it.
- **Borders:** 1px ash on cards and inputs. Focus ring: 1px molten at 60%, offset 1px.
- **Transparency & blur:** **forbidden** in the canonical theme. Worth is opaque.
- **Imagery:** product screenshots do the heavy lifting. The textured stone W appears on marketing only.

### Fifth Element (alt theme)

- **Base:** near-black `#0a0a0a`, panels `#1a1a1a`, elevated `#2C2C2C`.
- **Primary (chassis):** Safety Orange `#FF8C00` — chunky frames, screw details, warning stripes. This replaces Bedrock's molten-red budget.
- **Display text:** Terminal Green `#00FF41` with `text-shadow: 0 0 5px rgba(0,255,65,.5)`. This is the monospace body color.
- **Interactive:** Taxi Yellow `#FDB813` (warnings, active agents, diagonal hazard strips).
- **Action / Send:** Emergency Red `#FF3333` on a chunky physical button with an 8px red-cast bottom shadow.
- **Typography:** Orbitron (headings, ALL CAPS allowed), Fira Code (body, mono).
- **Motifs:** the **Multi-Pass chassis** (chunky 2px orange frame, rounded 12px, screw pseudo-elements on corners), **warning strip** (diagonal repeating gradient, taxi-yellow on black, 4px tall), **CRT scanlines** (fixed fullscreen overlay, animated 4px).
- **Glass viewport:** the only surface in the system where `backdrop-filter: blur(4px) brightness(0.8)` is permitted — center content pane only.
- **Corners:** 8–12px on chassis (chunky), 4px on buttons.
- **Shadows:** physical. Emergency button has `0 4px 0 #881111` (hard offset), plus ambient glow. Press state compresses to `0 1px 0`.
- **Animation:** CRT scanlines drift 4px vertically on loop. Status text flickers on a 4s cycle (92–100% opacity). Nothing else moves.
- **Hover:** orange text brightens to `#FFAA00`; green text brightens to `#33FF66`.
- **Imagery:** if a viewport background is used, it is a Moebius-style vertical-NYC skyline at warm sunset. Otherwise solid black.

### Shared rules

- **Grid:** dense. Sidebar rows are 18–24px tall, never 44px. Tight leading.
- **Keyboard-first:** input bar always focused. `/` opens commands. Escape cancels.
- **Numbers:** `font-variant-numeric: tabular-nums` so costs and tokens don't jitter.
- **Italics only for:** inline citations and "thinking" text from the agent. Never for emphasis.
- **No empty celebrations:** no "Nice!", no checkmark bursts, no confetti. Success is a quiet glyph.
- **No glass morphism (Bedrock)** / **glass viewport only (Fifth Element).** Never anywhere else.

### Layout rules (both themes)

- Header is a fixed 40px top bar with mode, status, workspace, turn, cost, active model.
- Left panel (sidebar) is 224px (`w-56`) and scrolls independently. Collapsible by keystroke.
- Right panel (metrics) is 256px (`w-64`). Same behavior.
- Center is the chat transcript + input bar. Always grows.
- Everything outside the center column is chrome; the center is content.

### Protection gradients / scrim

- Bedrock does not use scrims. If content is hard to read, fix the content, not the glass.
- Fifth Element uses a `rgba(10,10,10,0.85)` overlay on the glass viewport — this is the only scrim in either system.

---

## Iconography

### The codebase

Worth ships **Heroicons (outline)** via the `heroicons` Tailwind plugin (`assets/vendor/heroicons`). Only **outline** variants, only **16px** and **20px** (`w-4 h-4` / `w-5 h-5`). Single-color, inheriting the surrounding text color. Filled variants only to signal "active".

Icons used by the product today (from `lib/worth_web/components/*.ex`):

- `hero-eye` — X-ray toggle
- `hero-x-mark` — close / quit
- `hero-chat-bubble-left-right`, `hero-cpu-chip`, `hero-cube`, `hero-book-open`, `hero-squares-2x2`, `hero-wrench`, `hero-arrow-path` — sidebar navigation
- `hero-arrow-right` — send arrow (accents the molten send button)

**Do not use Heroicons solid.** Do not use Lucide or Phosphor — Worth standardized on Heroicons outline.

### CDN fallback

In this design system we load Heroicons SVGs inline per-component (copied from the `@heroicons/react` CDN). If you are authoring against this system in an environment without the plugin, pull them from `https://unpkg.com/@heroicons/[email protected]/24/outline/<name>.svg`.

### Emoji

**Never in product.** A status glyph is a character (`●`, `○`, `×`, `✓`) or the `.spinner` element, not an emoji. The marketing site occasionally uses Unicode symbols (`🪨`) for section anchors but never for functional UI.

### Unicode as icons

Worth leans on terminal-style characters:
- `●` running / selected
- `○` idle / unselected
- `×` error / close
- `✓` done
- `■` stop
- `<span class="spinner">…SVG…</span>` — the Worth **W-pulse** spinner (four wedges staggered; see `colors_and_type.css`)
- `|` column separator in the header

### Fifth Element elementals

The Fifth Element theme *optionally* adds four circular "elemental stone" icons — Earth, Wind, Fire, Water — for the Status / Usage / Tools / Skills tabs. These are drawn as chunky single-weight SVGs inside an orange-bordered circle. They are **additive**, not a replacement for Heroicons.

### Logo usage

- **Textured W** (`brand/logo.png`) — stone + molten seam. Marketing only. Never in product UI.
- **Flat W** — geometric, single-color, renders as SVG via `<.worth_mark />` (see `lib/worth_web/components/brand.ex`). Default in product.
- **Wordmark** — "worth" in Space Grotesk 600, lowercase.
- **Clear space** around the mark = height of the W's left arm on all sides.
- **Minimum size** 16px. Below that, silhouette only.
- **Never** recolor outside the palette. **Never** tilt, shadow, outline or animate (except the marketing splash).

---

## Font substitutions flagged to the user

All typefaces in use are **free Google Fonts** (Space Grotesk, Inter, JetBrains Mono, Orbitron, Fira Code). No substitutions required. If you want self-hosted `.ttf`/`.woff2` files rather than Google Fonts CDN, let me know — I can swap `@import` for local `@font-face`.

---

## Caveats / asks

See the closing summary in the chat after setup.
