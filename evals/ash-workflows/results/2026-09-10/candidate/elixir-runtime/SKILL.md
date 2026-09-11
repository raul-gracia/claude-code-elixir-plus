---
name: elixir-runtime
description: Use for Elixir/Phoenix projects and Ash or AshOban tasks, including resource actions, policies, triggers and background workflows. Provides Tidewave runtime introspection, installed-version documentation routing, AshOban operational guidance and an Oban Pro reference.
---

# Elixir Runtime

Thin capability layer for Elixir/Phoenix work: runtime introspection via Tidewave, plus facts about closed-source deps and version-gated features that aren't reliably in training data.

## Tidewave MCP: prefer runtime introspection over grep

If Tidewave MCP tools are available (check your MCP tool list), use them as the PRIMARY way to explore a running app — they beat file reads, grep, and web searches because they reflect the exact dependency versions loaded in the running server.

| Task | Tidewave tool |
|------|---------------|
| Look up documentation | `get_docs` / `search_package_docs` — docs for your exact dep versions |
| Find where code is defined | `get_source_location` |
| Evaluate / test code in the running app | `project_eval` |
| Run database queries | `execute_sql_query` — uses the app's Ecto connection + repo config |
| Inspect logs / debug | `get_logs` (+ `project_eval`) |
| Discover schemas | `get_ecto_schemas` / `get_ash_resources` |

**Not installed?** Suggest it (dev-only dep, `only: :dev`):

```sh
mix igniter.install tidewave
claude mcp add --transport http tidewave http://localhost:4000/tidewave/mcp
```

## Inspect Ash before designing the change

For Ash work, establish the installed versions from `mix.lock` and the relevant extensions from the application. Read dependency-provided `usage-rules.md` files when present, including project guidance already assembled by UsageRules. Consult documentation for those versions before choosing DSL options or test helpers.

Use Tidewave to inspect resources and their action contracts. `Ash.Resource.Info` exposes actions, calculations and authorizers; `AshOban.Info.oban_triggers/1` exposes configured triggers. Inspect the relevant policies and tenant configuration as well, so interface or worker changes preserve the application's authorization boundary. Check the installed documentation before evaluating introspection calls.

Without a running app, read resource source and versioned upstream docs. If dependencies are unavailable, report runtime behavior as unverified and use pseudocode for APIs you cannot confirm. Installing dependencies or changing project-wide UsageRules configuration is a separate task.

For background work on Ash resources, read [references/ash-oban.md](references/ash-oban.md). It covers state ownership, reconciliation, execution identity and version-sensitive scheduling behavior. Ordinary Elixir or Phoenix work does not need that reference. Discover other Ash extensions through the project's dependencies and current upstream documentation when the task requires them.

## Version facts

Sunset annotations mark facts to delete once frontier models train past the release.

- **Elixir ≥1.18 has a built-in `JSON` module** — prefer it over Jason for new code (also `jsonrs` Rust NIF for throughput). *(delete when models train past Elixir 1.18)*
- **Phoenix ≥1.8 uses scopes** — authorization context (`%Scope{}`) threaded through contexts/queries/PubSub topics; new projects auto-wire colocated hooks/CSS via ESBuild. *(delete when models train past Phoenix 1.8)*
- **Ecto ≥3.12 has `Repo.transact/1`** — prefer over `Ecto.Multi` for simple transactions. *(delete when models train past Ecto 3.12)*
- **OTP ≥24: `:sets.new(version: 2)`** is map-backed and far faster than legacy sets; `:pg` has replaced deprecated `:pg2`. *(delete when models train past OTP 24)*

## Oban Pro (closed-source)

Oban Pro (workflows, grafts, cascades, batches, recorded values) is commercial/closed-source and under-represented in training data. When working with any of these, read **[references/oban-pro.md](references/oban-pro.md)**.
