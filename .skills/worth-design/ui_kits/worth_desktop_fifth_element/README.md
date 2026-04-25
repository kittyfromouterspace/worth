# Worth Desktop — Fifth Element UI Kit

Maximalist retro-futurist Worth, rendered as an industrial control panel. This is the themed variant for showcases, event installs, and aesthetic reviews — not the production target.

## Files
- `index.html` — full Worth desktop rendered in the orange industrial chassis

## Motifs used
- Orange industrial chassis (2px `#FF8C00` border, 12px radius, screw pseudo-elements top + bottom corners, panel gradient `#2C2C2C → #1A1A1A`)
- Terminal-green body text `#00FF41` with soft glow (`text-shadow: 0 0 5px rgba(0,255,65,.5)`)
- Orbitron headers, UPPERCASE, heavy letter-spacing
- CRT scanline overlay on the view-port (2px green stripe, ~6% alpha)
- Backdrop-blurred city-scape view-port (inline SVG placeholder; swap for real imagery)
- `repeating-linear-gradient` hazard strip on chassis edges
- Physical red "emergency button" Send with hard drop-shadow and press compression
- Taxi-yellow `#FDB813` for warnings, ruby-red `#FF3333` for cost/limit breaches

## Reuse
Same component hierarchy as the Bedrock kit — only the visual chassis changes. The two kits share `colors_and_type.css` tokens; the fifth-element surfaces just reach for the `.theme-fifth-element` overrides.

## Caveats
- The city-scape is an inline SVG placeholder because image-generation isn't available in this environment. Replace `.viewport` background with a real Moebius-style render before shipping.
- Orbitron and Fira Code come from Google Fonts via `colors_and_type.css` — flagged substitution if Syncopate is preferred as the display face.
