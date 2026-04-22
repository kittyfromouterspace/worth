# Worth — Brand Guidelines

Worth is a desktop agent, a research bench, and (soon) a mobile companion, held together by a cloud sync layer. This document is the single source of truth for how Worth looks, sounds, and feels. It is opinionated on purpose — when in doubt, choose the quieter option.

---

## 1. Positioning

**Worth is the bedrock for serious AI work.**

Not a toy. Not a chatbot. Not a feed of magical demos. Worth is where power users — engineers, researchers, prompt designers, model evaluators — do the work of building with, measuring, and understanding language models.

### One-liner

> Worth is a desktop agent and research bench for people who take AI seriously.

### What makes Worth different

1. **Desktop-first.** Your models, your data, your machine. Cloud sync is an extension, not a prerequisite.
2. **A bench, not a chat.** Memory, skills, MCP, multi-model routing, cost tracking and transparent tool calls are surfaced, not hidden behind an interface that pretends AI is magic.
3. **Quiet by default.** No motivational copy, no gradients, no sparkles. Signal, not hype.
4. **Stays out of the way.** Keyboard-first, terminal-adjacent, dense. Built for people who already know what they're doing.

### Who Worth is for

- Engineers who ship with LLMs and want to see what's actually happening.
- Researchers doing model analysis, eval, and prompt engineering.
- Power users who grew up in terminals and still live there.
- People who are tired of AI products that treat them like customers instead of operators.

### Who Worth is *not* for

- First-time AI users looking for a gentle onboarding.
- Consumers who want a single magic button.
- Teams who want a no-code automation platform.

---

## 2. Voice & Tone

### Principles

1. **Say the thing.** No throat-clearing. No "empowering." No "revolutionizing."
2. **Respect the reader.** Assume technical literacy. Don't over-explain.
3. **Short sentences do most of the work.**
4. **Show, don't promise.** If the product does X, say it does X. Don't say "intelligent X."
5. **No exclamation marks.** Ever.

### Words we use

working, bench, surface, routing, memory, skills, workspace, signal, depth, measure, inspect, observe, compose, ship.

### Words we don't use

*empower, unleash, revolutionize, transform, seamlessly, magical, effortless, intelligent, smart, cutting-edge, next-gen, game-changing, AI-powered* (it's obviously AI-powered), *synergy, leverage (as a verb)*.

### Voice examples

**Instead of** "Worth empowers you to unlock the full potential of your AI workflows."
**Write** "Worth runs the agent loop. You inspect what it did."

**Instead of** "Intelligent memory that learns from every conversation."
**Write** "Memory: vector + knowledge graph. Queryable. Local."

**Instead of** "Experience the future of AI development."
**Write** "A bench for serious AI work."

---

## 3. Messaging

### Primary tagline

> **Make it worth it.**

### Support lines (use contextually)

- *A bench for serious AI work.*
- *Desktop agent. Research bench. No hype.*
- *Built for people who take AI seriously.*
- *Signal. Not hype.*

### Pillars

| Pillar | One-liner |
|---|---|
| **Depth** | Worth surfaces what other tools hide — memory, routing, costs, tool traces. |
| **Reliability** | Desktop-first, local-first, load-bearing. |
| **Leverage** | Skills, multi-model routing, and MCP compose into real workflows. |
| **Respect** | Keyboard-first. Opinionated defaults. No condescension. |

---

## 4. The "Bedrock" metaphor

Worth's metaphor is **bedrock**, not "rock as aesthetic." Bedrock is:

- **Foundational** — what everything else rests on.
- **Layered** — strata of capability, stacked and legible.
- **Load-bearing** — dependable under pressure.
- **Quiet** — it doesn't advertise itself; it just holds.

This is the north star when a design or copy decision is unclear: does this feel like bedrock, or does it feel like flash? Choose bedrock.

The fractured W in the logo reads as **strata** — geological cross-section, not shattered metal. Same mark, different meaning.

---

## 5. Color system

All colors in hex. CSS variables live in `lib/worth/theme/bedrock.ex`.

### Primary palette

| Role | Name | Hex | Notes |
|---|---|---|---|
| Base | **Obsidian** | `#0B0B0D` | 80% of surfaces. The void. |
| Surface | **Dark Steel** | `#1A1A1E` | Panels, cards, sidebars. |
| Surface elevated | **Graphite** | `#2A2A2E` | Buttons, inputs, hover states. |
| Border | **Ash** | `#3A3A3F` | Dividers, outlines. |
| Action | **Molten** | `#FF3B2F` | The only "loud" color. Used sparingly. |
| Highlight | **Heat Glow** | `#FF6A3D` | Hover on molten. That's it. |

### Text

| Role | Hex | Use |
|---|---|---|
| Primary | `#E8E8EA` | Body copy, titles |
| Muted | `#8A8A8F` | Secondary labels, metadata |
| Dim | `#5A5A5F` | Inactive, placeholders, separators |

### Semantic

| Role | Name | Hex | Notes |
|---|---|---|---|
| Success | Ore Green | `#7EC87E` | Muted forest, never neon. |
| Warning | Amber | `#F0B341` | For caution, not celebration. |
| Error | Molten | `#FF3B2F` | Same as action. Context makes it clear. |
| Info | Ash Light | `#9E9EA3` | Neutral. Info is not a color. |

### Usage rules

1. **Molten is a budget.** One or two molten elements per screen, maximum. Send button. Stop button. Active error. That's it. If everything is molten, nothing is.
2. **Heat glow is for hover only.** Never a resting state.
3. **Red is not paint.** It's energy inside the rock. Glows, gradients, and solid fills all work — but never drop-shadow splatters or neon outlines.
4. **Grayscale carries the UI.** Most elements live in the obsidian → graphite → ash range with text variation.
5. **No rainbow.** Success green, warning amber, and error red are the only non-grayscale semantic colors. No blue, no purple, no teal, no lavender.

### Accessibility

All text/background combinations meet WCAG AA (4.5:1) at the minimum. Body text (`#E8E8EA` on `#0B0B0D`) hits AAA.

---

## 6. Typography

### Stack

| Role | Font | Weights |
|---|---|---|
| Display / Headlines | **Space Grotesk** | 500, 600, 700 |
| UI / Body | **Inter** | 400, 500, 600 |
| Code / Monospace | **JetBrains Mono** | 400, 500 |

All three are free, variable, and load from Google Fonts. They're declared in the theme CSS, not in `assets/css/app.css`.

### Scale

Stick to a small scale. Dense, not spacious.

```
xs    11 / 16   metadata, labels
sm    13 / 18   UI default, sidebar rows
base  14 / 20   body copy, messages
md    16 / 22   section headings
lg    20 / 26   page titles
xl    28 / 34   hero (marketing only)
2xl   44 / 48   hero display (marketing only)
```

### Rules

1. **Headings use Space Grotesk, tight tracking (-0.01em), never all-caps in product** (all-caps is a marketing-only choice, for hero lockups).
2. **Body uses Inter.** Code, IDs, paths, and numbers use JetBrains Mono.
3. **Numbers in the UI use `font-variant-numeric: tabular-nums`** so costs and token counts don't jitter when they update.
4. **No letter-spacing on body text.** Tight tracking only on display and small-caps labels.
5. **Italics only for two things:** inline citations and "thinking" text from the agent. Never for emphasis (use weight instead).

---

## 7. Logo & wordmark

### Assets

- **Textured mark** (`brand/logo.png`) — stone + molten seam W. Marketing, hero, merch. **Never in product UI.**
- **Flat mark** — geometric W, single-color, reads as strata. In-product header, favicon, app icons. Lives as an SVG component (`<.worth_mark />`).
- **Wordmark** — "WORTH" in Space Grotesk 700, `.ROCKS` in 500 at 60% alpha, offset. Optional for large surfaces.

### Rules

1. **Flat is the default in product.** Textured is the exception, for marketing only.
2. **The W has clear space** equal to the height of its left arm on all sides.
3. **Minimum size:** 16px for the flat W. Below that, use the pure silhouette (`priv/static/images/worth-16.svg`).
4. **Never recolor** outside the palette. If a surface doesn't support molten red, use text-primary white.
5. **Never tilt, shadow, outline, or animate** the mark outside of the marketing splash.

### In-product usage

- **Header:** flat W + "worth" wordmark, small, left-aligned.
- **Empty state:** flat W centered, wordmark under it, tagline under that.
- **Onboarding:** same as empty state, with step indicator.
- **Vault unlock:** same as empty state.
- **Favicon & app icon:** flat W silhouette.

---

## 8. Visual language

### Motifs (use sparingly)

- **Strata dividers.** Thin horizontal rules, 1px, ash color. Occasionally stacked with tight spacing to evoke rock layers — only for marketing.
- **Heat seam.** A 1px molten line at 20% alpha as a top-border signature on the header. One line, one brand moment, nothing more.
- **Dense grids.** Sidebar rows, metrics columns, tight leading. Reference: `bat`, `htop`, Linear's tables, TUI dashboards.

### What we don't do

- No glass morphism, no blur backgrounds.
- No gradients except on the molten action button (top-to-bottom, subtle).
- No drop shadows except on the molten button press state.
- No "AI sparkles" iconography. No gradient orbs. No generative visuals.
- No animation beyond the existing spinner and the input cursor. Status updates are instant; they don't fade in.

### Iconography

Heroicons outline, 16px and 20px only. Single color (usually text-muted), never filled unless they're representing "active." No custom illustrations in product.

---

## 9. UI principles — "minimal bench"

Every UI decision gets tested against these:

1. **Quiet by default, loud on purpose.** Red only for actions that commit or halt. Everything else is grayscale.
2. **Density over whitespace.** Sidebar rows are 18px tall, not 44px. Info should be scannable like a terminal, not read like a blog.
3. **Keyboard-first.** Every action has a shortcut. The input bar is always focused on load. Escape cancels. `/` opens commands.
4. **Monospace for data, sans for prose.** Paths, tokens, IDs, costs → mono. Descriptions, copy, headings → Inter/Space Grotesk.
5. **State is visible.** If the agent is thinking, you can see what it's thinking. If a tool is running, you see the tool name. Nothing is hidden to "reduce clutter."
6. **No empty celebrations.** No "Nice!", no checkmark bursts, no confetti. Success is a quiet green glyph and a return to idle.
7. **The app doesn't talk about itself.** No product tours, no "Pro tip!" overlays, no feature announcements in-product.

---

## 10. Surface-specific direction

### In product (desktop / LiveView)

- Obsidian background, dark steel sidebars.
- Heat-seam line on the top edge of the header.
- Flat W + wordmark, no tagline.
- All text in Inter/Space Grotesk. JBM for mono blocks (code, paths, IDs).
- Red is rare. If you're reading this and considering adding another red element, don't.

### Marketing (the homunculus → worth.rocks redesign)

- Textured W allowed in hero.
- Molten red glow and heat seam as the signature.
- Space Grotesk display, tight tracking, occasional all-caps for hero.
- Strata motifs as section dividers.
- Keep it dense. No hero image sliders, no testimonial carousels. Product screenshots do the heavy lifting.

### Mobile (future)

- Same palette, same fonts.
- The flat W becomes a compact mark for the nav bar.
- Minimal bench translates to sparse taps — no bottom nav overflow, no animated tab transitions.

---

## 11. Brand extensions (naming)

| Name | Role |
|---|---|
| **worth** | The product. |
| **worth.desktop** | The local app. |
| **worth.cloud** | Sync layer + server components. |
| **worth.bench** | Research surface (model eval, prompt tooling). |
| **worth.mobile** | Future mobile companion. |

`worth.rocks` is the primary web domain. `worth.engine`, `worth.agent`, `worth.core` from the original brief are deprecated — they don't map to real modules.

---

## 12. When to break these rules

The only reason to break a rule in this document is that doing so serves "bedrock" — making Worth feel more load-bearing, more quiet, more respected by the people who use it. If a rule makes the product feel hypier, not quieter, the rule was wrong.

When in doubt: fewer colors. Fewer words. Fewer animations. That's it.
