# Worth Desktop — Bedrock UI Kit

Canonical dark, terminal-flavored Worth desktop. Opens to the agent transcript view, the default surface for power users.

## Files
- `index.html` — assembled Worth desktop (header · sidebar · transcript · metrics rail · input bar). Interactive: the input bar accepts text and replies.

## Components surfaced
- Header bar (status glyph, wordmark, breadcrumb `workspace | mode | turn | cost (model)`, x-ray + quit)
- Left sidebar: Workspaces · Agents · Model · Tools · Skills · Memory
- Transcript: user message · assistant message · thinking · tool-call block with result
- Input bar with `code >` prompt + Send
- Right sidebar: Session · Tokens · Cache/Embeddings · Providers · Coding Agents

## Design contract
- Background `#0B0B0D` throughout; borders `#3A3A3F`; dividers `|` in `#5A5A5F`
- Sidebar section titles: 10px uppercase, `#8A8A8F`, letter-spacing 0.08em
- Rows: 12px JetBrains Mono, `#8A8A8F` idle → `#E8E8EA` hover/active
- Metric values are tabular numerals; cost lines use molten `#FF3B2F`
- Molten never fills large surfaces — only the Send button, tiny dots, and the 1px heat seam across the header top

Do not invent new surfaces. Everything here maps to a concept already visible in the Worth elixir app (`lib/worth_cli/app/*` and the UI composer).
