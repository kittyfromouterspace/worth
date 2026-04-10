# Worth Quick Start Guide

Get Worth running in 5 minutes with **zero database setup** using libSQL (SQLite with native vector support).

## Prerequisites

- Elixir 1.19+ installed
- An LLM API key (Anthropic, OpenAI, or OpenRouter)

**Note:** No PostgreSQL installation required! Worth uses libSQL, a single-file database.

---

## 1-Minute Setup

### 1. Clone and Install

```bash
git clone https://github.com/kittyfromouterspace/worth.git
cd worth
mix deps.get
```

### 2. Create Database

```bash
# Creates ~/.worth/worth.db automatically
mix ecto.create
mix ecto.migrate
```

That's it! No PostgreSQL, no server setup, no configuration files.

### 3. Configure API Key

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
# OR
export OPENROUTER_API_KEY="sk-or-..."
```

### 4. Start Worth

```bash
mix phx.server
```

Open http://localhost:4000 in your browser.

Or use the CLI launcher:

```bash
mix worth
```

---

## Your First Conversation

1. Open http://localhost:4000
2. Type: `Create a Python script that fetches weather data`
3. Watch Worth:
   - Search its memory for relevant knowledge
   - Plan the implementation
   - Write the code
   - Save it to your workspace

---

## Understanding the Database

Worth stores everything in a single file:

```
~/.worth/
├── worth.db           # Your data (single SQLite file)
├── config.exs        # Settings (auto-created)
└── workspaces/       # Project workspaces
    └── default/
        └── IDENTITY.md
```

**Backup:** Just copy `worth.db`:

```bash
cp ~/.worth/worth.db ~/worth-backup.db
```

**Restore:**

```bash
cp ~/worth-backup.db ~/.worth/worth.db
```

---

## Switching to PostgreSQL (Optional)

If you need PostgreSQL for multi-user setups or existing infrastructure:

```bash
# Set environment variable
export WORTH_DATABASE_BACKEND=postgres

# Setup PostgreSQL
docker run -d \
  --name worth-db \
  -e POSTGRES_PASSWORD=worth \
  -e POSTGRES_DB=worth \
  -p 5432:5432 \
  pgvector/pgvector:pg16

# Run Worth with PostgreSQL
mix ecto.create
mix ecto.migrate
mix phx.server
```

---

## Common Commands

```bash
# Reset database (libSQL)
rm ~/.worth/worth.db && mix ecto.create && mix ecto.migrate

# View database (SQLite CLI)
sqlite3 ~/.worth/worth.db ".tables"

# Export data
mix worth.export --output ~/backup.jsonl

# Import data
mix worth.import --input ~/backup.jsonl

# Run tests
mix test

# Start with specific workspace
mix worth --workspace my-project --mode code
```

---

## Troubleshooting

### "Database not found"

```bash
mix ecto.create
```

### "Permission denied" on database file

```bash
chmod 644 ~/.worth/worth.db
```

### Want to start fresh?

```bash
rm -rf ~/.worth/
mix ecto.create
mix ecto.migrate
```

---

## Next Steps

- Read [ARCHITECTURE.md](docs/ARCHITECTURE.md) to understand how Worth works
- Check out [SKILLS.md](docs/SKILLS.md) to learn about the skills system
- Configure [MCP servers](docs/MCP.md) to extend capabilities

---

## Need Help?

- Create an issue: https://github.com/kittyfromouterspace/worth/issues
- Check the FAQ: https://github.com/kittyfromouterspace/worth/blob/main/FAQ.md

Happy coding! 🚀
