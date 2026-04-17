# Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| TermUI dependency removed | Was new/unstable | Replaced by Phoenix LiveView + Bandit (mature, well-supported) |
| PostgreSQL dependency for local CLI | Setup friction | Document setup clearly; libSQL backend available for zero-dependency mode |
| Agentic callback surface is large | Integration complexity | Start minimal (only `:llm_chat` + `:on_event`), add incrementally |
| Context window management | Quality degradation on long sessions | Agentic ContextGuard handles compaction; worth adds UI feedback |
| Streaming latency in web UI | Perceived slowness | Phoenix LiveView handles real-time diffs efficiently; batch small chunks |
| MCP server reliability | External dependency failures | ConnectionMonitor with health checks + backoff; graceful degradation |
| MCP tool name collisions | Ambiguous tool calls | Namespace with `server_name:tool_name` prefix |
| Self-evolving skill quality | Degradation over time | Trust levels + human promotion gate; version rollback; A/B testing |
| Global memory noise | Irrelevant cross-workspace context | Workspace relevance boosting; outcome feedback; memory decay |
| Security of learned skills | Malicious skill content | Learned skills start restricted; sandboxed testing; human review gate |
| PubSub message storms | UI overwhelmed by events | Topic isolation; debounce rendering at 50ms windows; backpressure via selective subscribe |
