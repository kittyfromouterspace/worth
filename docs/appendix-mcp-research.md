# Appendix B: MCP Research & Design Rationale

## B.1 MCP Specification Summary

The Model Context Protocol (MCP) is a JSON-RPC 2.0 protocol published by Anthropic and now hosted by The Linux Foundation. Latest protocol version: `2025-11-25`.

### Three Server Primitives

| Primitive | Control | Purpose |
|-----------|---------|---------|
| **Tools** | Model-controlled | Executable functions the LLM decides to call |
| **Resources** | Application-driven | Readable data sources (files, schemas) |
| **Prompts** | User-controlled | Reusable prompt templates |

### Transport Options

| Transport | Use Case |
|-----------|----------|
| **stdio** | Local tools (subprocess communication) |
| **Streamable HTTP** | Remote services (HTTP POST + SSE for streaming) |
| **WebSocket** | Long-lived connections |
| **SSE** | Legacy (deprecated) |

### Method Registry (25+ methods)

Key requests:
- `initialize` -- version/capability negotiation
- `tools/list`, `tools/call` -- tool discovery and execution
- `resources/list`, `resources/read` -- data source access
- `prompts/list`, `prompts/get` -- prompt templates
- `completion/complete` -- autocompletion suggestions
- `sampling/createMessage` -- server requests LLM generation from client
- `elicitation/create` -- server requests user input from client
- `roots/list` -- server requests filesystem roots from client
- `tasks/get`, `tasks/result`, `tasks/list`, `tasks/cancel` -- durable task tracking (2025-11-25)

### Authorization (OAuth 2.1)

MCP supports optional OAuth 2.1 for remote HTTP servers. Features PKCE, audience validation, incremental scope consent. Worth can implement this for commercial MCP servers.

## B.2 hermes_mcp Library

hermes_mcp (~0.14.1, 107k+ hex downloads) is the Elixir MCP library used by homunculus and worth.

Capabilities:
- Full client + server support via `use Hermes.Client` / `use Hermes.Server` macros
- All transports: stdio, Streamable HTTP, WebSocket, SSE (deprecated)
- Protocol versions: `2024-11-05`, `2025-03-26`, `2025-06-18`
- JSON-RPC 2.0: full message encoding/decoding, error handling
- Session management with capability negotiation
- Request timeout/cancellation with progress notifications
- Component system for registering tools/resources/prompts at runtime

This library is already a transitive dependency through agentic -- no additional hex dependency needed.

## B.3 MCP Server Ecosystem

### Official Reference Servers
- filesystem, fetch, git, memory, sequential-thinking

### Major Third-Party Servers
- GitHub, GitLab, Bitbucket (source control)
- Slack, Discord, Teams (messaging)
- PostgreSQL, Supabase, Neon, PlanetScale (databases)
- Brave Search, Tavily, Exa, Perplexity (search)
- AWS, Azure, GCP (cloud platforms)
- Stripe, PayPal, HubSpot (fintech)
- Sentry, Datadog, Grafana (observability)

### Registry
- MCP Registry (https://registry.modelcontextprotocol.io/) -- community-driven server registry
- Supports GitHub OAuth, DNS verification, HTTP verification for publishing

### Elixir Ecosystem
- **hermes_mcp** (107k downloads) -- client + server, Phoenix integration, used by homunculus
- **aide** (138k downloads) -- Gleam-based, focused on building MCP servers
- **anubis_mcp** (131k downloads) -- fork/rewrite of hermes_mcp
- **ex_mcp** (1.7k downloads) -- full MCP + ACP support, stdio + HTTP/SSE + BEAM transport
- **ectomancer** (88 downloads) -- auto-expose Ecto schemas as MCP tools
- **codicil** (649 downloads) -- semantic code search for Elixir via MCP

No official Elixir SDK from modelcontextprotocol.

## B.4 MCP and Agent Skills Complementarity

| Aspect | MCP | Skills |
|--------|-----|--------|
| Granularity | Individual functions | Bundled expertise |
| Discovery | Listed at connection time | Loaded on-demand |
| Composition | Tools from different servers | Skills stack automatically |
| Code execution | No native support | Can include executable scripts |
| Portability | Server-specific | Same format everywhere |

Skills document how to use MCP tools effectively. MCP provides the tools. They're complementary layers.
