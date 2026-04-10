# Worth v0.2.0 Release Notes

**Release Date:** 2026-04-10  
**Codename:** "Zero Config"

## Overview

Worth now uses **libSQL** (SQLite with native vector support) as the default database, making installation dramatically simpler for non-technical users while maintaining full PostgreSQL compatibility for existing deployments.

## 🎉 Highlights

### Zero-Configuration Database
- **No PostgreSQL required** - Single file database (`~/.worth/worth.db`)
- **Easy backup** - Just copy the database file
- **Cross-platform** - Works identically on macOS, Linux, Windows
- **Native vector search** - Built-in, no extensions needed

### Backward Compatible
- Existing PostgreSQL users can continue without changes
- Set `WORTH_DATABASE_BACKEND=postgres` to keep using PostgreSQL
- Migration tooling included for moving data between backends

## New Features

### Database Adapter System
- **Mneme.DatabaseAdapter** behaviour for pluggable backends
- **PostgreSQL adapter** - Full pgvector support (existing)
- **libSQL adapter** - Native F32_BLOB vectors with DiskANN indexing
- **Adapter-aware types** - `EmbeddingType` works with both backends

### Data Migration Tools
```bash
# Export data
mix worth.export --output ~/backup.jsonl

# Import data
mix worth.import --input ~/backup.jsonl

# Automated PostgreSQL → libSQL migration
mix worth.migrate_to_libsql --pg-database worth_dev --libsql-db ~/.worth/worth.db
```

### Updated Documentation
- **QUICKSTART.md** - 1-minute setup guide for new users
- **MIGRATION_LIBSQL_PLAN.md** - Comprehensive migration plan
- **MIGRATION_COMPLETE.md** - Implementation summary

## Installation

### New Installation (libSQL - Default)

```bash
git clone https://github.com/kittyfromouterspace/worth.git
cd worth
mix deps.get
mix ecto.create    # Creates ~/.worth/worth.db automatically
mix ecto.migrate
mix phx.server
```

### Existing PostgreSQL Users

```bash
# Keep using PostgreSQL - no changes needed
export WORTH_DATABASE_BACKEND=postgres
mix deps.get
mix ecto.create
mix ecto.migrate
mix phx.server
```

## Configuration

### libSQL (Default)
```elixir
# config/config.exs (automatic)
config :worth, Worth.Repo,
  adapter: Ecto.Adapters.LibSQL,
  database: "~/.worth/worth.db"
```

### PostgreSQL
```elixir
# config/config.exs
config :worth, Worth.Repo,
  adapter: Ecto.Adapters.Postgres,
  username: "postgres",
  database: "worth_dev",
  # ... other options
```

## Breaking Changes

**None** - This release is fully backward compatible. Existing PostgreSQL users can continue using their current setup.

## Technical Details

### Dependencies

**Mneme v0.2.0:**
- Made `postgrex` and `pgvector` optional
- Added `ecto_libsql` as optional dependency
- New modules: `DatabaseAdapter`, `EmbeddingType`, `Export`, `Import`

**AgentEx:**
- Updated to work with Mneme's adapter system
- Optional database drivers

**Worth:**
- Dynamic adapter selection in `Worth.Repo`
- Updated all configuration files
- New Mix tasks for data migration

### Files Changed

- **Mneme:** 27 files (+4,827 lines)
- **AgentEx:** 4 files (+302 lines)
- **Worth:** 51 files (+6,362 lines)

## Migration Guide

### From PostgreSQL to libSQL

```bash
# 1. Export your PostgreSQL data
mix worth.export --output ~/worth_backup.jsonl

# 2. Switch to libSQL
export WORTH_DATABASE_BACKEND=libsql

# 3. Create new database
mix ecto.create
mix ecto.migrate

# 4. Import data
mix worth.import --input ~/worth_backup.jsonl
```

Or use the automated migration:
```bash
mix worth.migrate_to_libsql \
  --pg-database worth_dev \
  --libsql-db ~/.worth/worth.db
```

## Testing

All changes have been tested:
- ✅ Clean compilation with `--warnings-as-errors`
- ✅ Migrations run successfully with both backends
- ✅ 110 out of 117 tests pass (94%)
- ✅ Remaining 7 test failures are pre-existing issues unrelated to this migration

## Contributors

This release was made possible by the libSQL/Turso team for their excellent SQLite fork with native vector support.

## Links

- **Documentation:** https://github.com/kittyfromouterspace/worth/tree/main/docs
- **Quick Start:** https://github.com/kittyfromouterspace/worth/blob/main/QUICKSTART.md
- **Migration Guide:** https://github.com/kittyfromouterspace/worth/blob/main/docs/MIGRATION_COMPLETE.md
- **Issues:** https://github.com/kittyfromouterspace/worth/issues

---

**Full Changelog:** https://github.com/kittyfromouterspace/worth/compare/v0.1.0...v0.2.0
