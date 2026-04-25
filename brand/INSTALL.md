# Installing the Worth design system in Claude Code

This folder is two things at once:

1. A **Claude Code Agent Skill** named `worth-design`
2. A **standalone reference** any agent (or human) can read

You can install it either way. Pick whichever fits your workflow.

---

## Option A — Install as an Agent Skill (recommended)

This makes the design system available across every Claude Code session, and it's invokable on demand with `/skill worth-design`.

### Personal install (just you, all your projects)

```bash
# from the folder containing this INSTALL.md
mkdir -p ~/.claude/skills
cp -R . ~/.claude/skills/worth-design
```

Restart Claude Code (or run `/skills reload`). You should see `worth-design` listed in `/skills`.

### Per-project install (whole team, checked into the repo)

```bash
# from your project root
mkdir -p .claude/skills
cp -R /path/to/worth-design .claude/skills/worth-design
git add .claude/skills/worth-design
git commit -m "vendor: worth-design skill"
```

Now everyone on the team has the skill loaded automatically when they open the repo in Claude Code.

### Verify

```bash
ls ~/.claude/skills/worth-design/SKILL.md   # personal
ls .claude/skills/worth-design/SKILL.md     # per-project
```

In Claude Code:

```
/skills
```

Look for `worth-design` in the list. Try:

```
/skill worth-design
```

It should load the skill and Claude will read `SKILL.md` followed by `README.md`.

---

## Option B — Vendor as a plain folder

If you don't want to use the Skills mechanism, just drop this folder anywhere in your repo (e.g. `design/` or `docs/design-system/`). Then point Claude at it:

```
read design/SKILL.md and follow it
```

Or in `CLAUDE.md` at the repo root:

```markdown
## Design system

Worth's design system lives in `design/`. Always start by reading
`design/SKILL.md` before producing any visual or copy work.
```

The skill is self-contained — no install step required.

---

## What you get

```
worth-design/
├── SKILL.md                    # frontmatter + entry point for Claude Code
├── README.md                   # full design system doc
├── colors_and_type.css         # all tokens, both themes, W-pulse spinner
├── assets/                     # logo files (flat + textured), brand reference
├── brand/                      # brand idea reference imagery
├── preview/                    # one HTML card per token / component state
└── ui_kits/
    ├── worth_desktop_bedrock/      # canonical interactive desktop
    └── worth_desktop_fifth_element/# retro-futurist alt theme
```

## Caveats

- **Fonts** load from Google Fonts (Space Grotesk, Inter, JetBrains Mono, Orbitron, Fira Code) via `colors_and_type.css`. If you need offline / self-hosted, drop `.woff2` files into a `fonts/` folder and update the `@import` block at the top of the stylesheet.
- **The `ui_kits/`** are visual references, not production components. Copy patterns and tokens out of them; do not lift the React-less HTML into a real app.
- **The Fifth Element theme** is a showcase variant. Default to Bedrock unless the user explicitly asks for the alt theme.

## Updating

When the upstream design system changes, re-run the copy step from Option A or pull the latest folder. SKILL.md and README.md are the only files Claude Code reads on init — everything else is read on demand.
