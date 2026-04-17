---
name: use-recollect
description: "Pluggable memory engine with vector search, knowledge graphs, and LLM extraction. Supports PostgreSQL (pgvector), SQLite (sqlite-vec), and libSQL.."
metadata:
  managed-by: usage-rules
---

<!-- usage-rules-skill-start -->
## Additional References

- [embedding](references/embedding.md)
- [extension-points](references/extension-points.md)
- [knowledge](references/knowledge.md)
- [maintenance](references/maintenance.md)
- [pipeline](references/pipeline.md)
- [search](references/search.md)
- [recollect](references/recollect.md)

## Searching Documentation

```sh
mix usage_rules.search_docs "search term" -p recollect
```

## Available Mix Tasks

- `mix recollect.consolidate`
- `mix recollect.gen.migration`
<!-- usage-rules-skill-end -->
