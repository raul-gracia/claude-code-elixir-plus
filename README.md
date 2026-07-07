# claude-code-elixir-plus

A Claude Code plugin that grants Claude runtime capabilities for Elixir, Phoenix, Ecto, OTP, Oban, and Ash work. It bundles one capability skill (`elixir-runtime`), four automated hooks (format, compile, credo, session context injection), and ElixirLS integration.

The skill is deliberately thin. General Elixir/OTP/Phoenix/Ecto/Ash pedagogy already lives in the model's training data, so the plugin carries only what a frontier model *can't* reliably know on its own: the Tidewave MCP runtime-introspection grant, a reference for the closed-source Oban Pro library, and a handful of version-gated facts (each annotated with a sunset note for when the model's training catches up).

## Installation

```bash
# Add from marketplace
claude plugin add claude-code-elixir-plus

# Or install from source
claude plugin install /path/to/claude-code-elixir-plus
```

## Skill

The plugin ships one capability skill: `elixir-runtime`. It triggers on Elixir/Phoenix work (`.ex`/`.exs` files, `mix.exs` present, or mentions of Elixir/Phoenix/OTP/Ecto/Ash/Oban) and carries only the durable, non-training-data payload.

| Skill | Triggers When You... | Grants |
|-------|---------------------|--------|
| `elixir-runtime` | Work on an Elixir/Phoenix project (`mix.exs` present) | Tidewave MCP runtime-introspection guidance (`project_eval`, `get_docs`, `get_source_location`, `execute_sql_query`, `get_logs`, schema discovery), version-gated facts with sunset notes, and a pointer to the Oban Pro reference. |

### Reference files

| File | Skill | Why it's here |
|------|-------|---------------|
| `elixir-runtime/references/oban-pro.md` | `elixir-runtime` | Oban Pro (workflows, grafts, cascades, batches) is commercial/closed-source and under-represented in training data. |

### Why one thin skill

Earlier versions shipped seven "thinking" skills covering Elixir/OTP/Phoenix/Ecto/Ash/Oban pedagogy plus a router. A frontier model already knows that material from its training data, and version-pinned rule tables rot as the ecosystem moves. The plugin now keeps only what the model genuinely lacks: a runtime capability grant (Tidewave), a closed-source library reference (Oban Pro), and a few version facts — each carrying a sunset note for when to delete it. Skill dispatch is handled natively by the model reading the skill's `description`; no hand-coded router is needed.

## Hooks

Four hooks run automatically -- no configuration needed after install.

| Hook | Event | Fires When | What It Does | Timeout |
|------|-------|------------|-------------|---------|
| `session-start.sh` | `SessionStart` | Session starts, resumes, clears, or compacts | Injects the `elixir-runtime` skill into context (only if `mix.exs` exists) | default |
| `format-elixir.sh` | `PostToolUse` (Edit/Write) | After any file edit or write | Runs `mix format` on the changed `.ex`/`.exs` file | 15s |
| `compile-elixir.sh` | `PostToolUse` (Edit/Write) | After any file edit or write | Runs `mix compile --warnings-as-errors` on changed `.ex` files (skips `.exs`) | 60s |
| `credo-elixir.sh` | `PreToolUse` (Commit) | Before a git commit | Runs `mix credo` on the file; blocks commit if issues found | 30s |

All hooks walk up from the edited file to find `mix.exs`, so they work in umbrella apps and nested project structures. The credo hook silently skips if credo is not installed in the project.

## LSP

The plugin configures ElixirLS as the language server for `.ex`, `.exs`, `.heex`, and `.leex` files:

- **Dialyzer**: enabled
- **Fetch deps**: disabled (does not auto-run `mix deps.get`)
- **Suggest specs**: enabled

ElixirLS must be installed and available on your PATH as `elixir-ls`.

## Updating

```bash
claude plugin update claude-code-elixir-plus
```

## License

MIT
