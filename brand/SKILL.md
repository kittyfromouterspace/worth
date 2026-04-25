---
name: worth-design
description: Use this skill to generate well-branded interfaces and assets for Worth (a desktop AI agent for power users, with Bedrock and Fifth Element themes). Apply for production code, slides, mockups, prototypes, or any visual artifact that should look and feel like Worth.
license: Proprietary — internal Worth use only
---

# worth-design

The full Worth design system. Read `README.md` first — it has product context, voice rules, visual foundations, iconography guidance, and an index of every other file.

## What's here

- **`README.md`** — product context, content fundamentals (voice, tone, casing), visual foundations (colors, type, spacing, animation, hover/press, borders, shadows), iconography. Read this first.
- **`colors_and_type.css`** — every token. CSS custom properties for both themes (`.theme-bedrock` and `.theme-fifth-element`), the semantic role mapping, the `.spinner` keyframes (W-pulse), and font imports.
- **`assets/`** — logomarks (flat + textured), brand-ideas reference. Copy these; never redraw them.
- **`preview/`** — one HTML card per design-system token or state. The reference implementation for every visual decision — when in doubt, open the relevant card.
- **`ui_kits/worth_desktop_bedrock/`** — canonical interactive Worth desktop. Copy components and patterns out of `index.html`.
- **`ui_kits/worth_desktop_fifth_element/`** — retro-futurist alt theme of the same surface. Showcase only; don't ship as default.

## How to use this skill

### When producing visual artifacts (slides, marketing, mockups, throwaway prototypes)
Copy the assets you need into your artifact, link `colors_and_type.css`, and write standalone HTML. Default to `.theme-bedrock` — it's the product's daily face. Use `.theme-fifth-element` only when the user explicitly asks for the alt theme.

### When working on production code
Treat the tokens and voice rules as constraints. Don't copy `ui_kits/` component implementations into the real app — they're cosmetic recreations. Instead, match the existing Elixir/LiveView components in the Worth codebase, and use this skill's tokens as the source of truth for color, type, spacing, and copy voice.

### When invoked without other guidance
Ask the user what they want to build — a slide, a marketing page, a feature mock, a doc cover, a code component — and which theme (Bedrock by default). Ask 3–5 sharp questions, then output HTML or code.

## Hard rules

- Never use emoji in product surfaces. Status is a character (`●` `○` `×` `✓` `■`) or the W-pulse spinner.
- Never redraw the Worth mark. If a file in `assets/` covers the case, copy it.
- Never write SaaS marketing voice. Voice is terse, declarative, and anti-hype — see README's content fundamentals.
- Never apply the Fifth Element chassis to a Bedrock surface. Themes don't mix within one screen.
- Molten red is for action and warning, not large surfaces. The biggest molten thing on any default screen is the Send button.
