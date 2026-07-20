---
name: elixir-runtime
description: Use when working on Elixir/Phoenix projects (mix.exs present) — grants runtime introspection tools and facts for closed-source deps. Covers Tidewave MCP usage and Oban Pro.
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

## Version facts

Sunset annotations mark facts to delete once frontier models train past the release.

- **Elixir ≥1.18 has a built-in `JSON` module** — prefer it over Jason for new code (also `jsonrs` Rust NIF for throughput). *(delete when models train past Elixir 1.18)*
- **Phoenix ≥1.8 uses scopes** — authorization context (`%Scope{}`) threaded through contexts/queries/PubSub topics; new projects auto-wire colocated hooks/CSS via ESBuild. *(delete when models train past Phoenix 1.8)*
- **LiveView ≥1.2: `%JS{}` commands encode through `push_event`** — compose UI commands server-side and put them in the payload (auto via `JSON.Encoder`/`Jason.Encoder`; other encoders need `JS.to_encodable/1`); a hook executes them with `this.js().execJS(this.el, cmd)`. Also new: colocated CSS (`<style :type={MyAppWeb.ColocatedCSS}>`, extracted at compile time into `phoenix-colocated/` and imported into app.css; scoped mode is opt-in, not default) and `phx-no-unused-field` to stop `_unused` form params. *(delete when models train past LiveView 1.2)*
- **Ecto ≥3.12 has `Repo.transact/1`** — prefer over `Ecto.Multi` for simple transactions. *(delete when models train past Ecto 3.12)*
- **OTP ≥24: `:sets.new(version: 2)`** is map-backed and far faster than legacy sets; `:pg` has replaced deprecated `:pg2`. *(delete when models train past OTP 24)*

## Oban Pro (closed-source)

Oban Pro (workflows, grafts, cascades, batches, recorded values) is commercial/closed-source and under-represented in training data. When working with any of these, read **[references/oban-pro.md](references/oban-pro.md)**.
