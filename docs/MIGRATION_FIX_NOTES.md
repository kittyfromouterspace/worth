# Migration Fix Summary

## Issue
All existing migrations are PostgreSQL-specific and fail when using libSQL.

## Solution

### Option 1: Adapter-Aware Migrations (Recommended)
Make each migration detect the adapter and use appropriate SQL.

### Option 2: Separate Migration Sets
Have completely separate migration files for PostgreSQL and libSQL.

## Implementation Plan

I'll update the key migrations to support both backends:

1. **20240101000000_create_mneme_tables.exs** - Make adapter-aware
2. **20260408000000_embedding_model_id_and_1536_dim.exs** - Make adapter-aware
3. **All other migrations** - Check for PostgreSQL-specific syntax

## libSQL-Specific Changes Needed

### Vector Types
- PostgreSQL: `:vector, size: N`
- libSQL: Use raw SQL with `F32_BLOB(N)`

### Vector Indexes
- PostgreSQL: `USING hnsw (embedding vector_cosine_ops)`
- libSQL: `libsql_vector_idx(embedding)`

### UUIDs
- PostgreSQL: `:uuid`
- libSQL: `:string`

### Extensions
- PostgreSQL: `CREATE EXTENSION IF NOT EXISTS vector`
- libSQL: Skip (native support)

### Fragment Functions
- PostgreSQL: `fragment("now()")`
- libSQL: `fragment("datetime('now')")` (but usually not needed)

## Testing

After fixes:
```bash
rm -f worth_test.db* && mix test
```

## Documentation

Users need to know:
1. New installations default to libSQL
2. Existing PostgreSQL users can continue using PostgreSQL
3. Migration tooling exists to convert between backends
