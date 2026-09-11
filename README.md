# claude-code-elixir-plus

A Claude Code plugin that grants Claude runtime capabilities for Elixir, Phoenix, Ecto, OTP, Oban, and Ash work. It bundles one capability skill (`elixir-runtime`), four automated hooks (format, compile, credo, session context injection), and ElixirLS integration.

The skill provides runtime introspection and directs Ash work to documentation for the application's installed versions. General framework tutorials stay upstream. An optional AshOban reference covers workflow decisions and version-sensitive operational behavior, while the existing Oban Pro reference supplies details for the commercial library.

## Installation

```bash
# Add from marketplace
claude plugin add claude-code-elixir-plus

# Or install from source
claude plugin install /path/to/claude-code-elixir-plus
```

## Skill

The plugin ships one capability skill, `elixir-runtime`, for Elixir/Phoenix projects and explicit Ash/AshOban tasks. Its description supports native selection; the session hook injects it when `mix.exs` exists in the working directory.

| Skill | Triggers When You... | Grants |
|-------|---------------------|--------|
| `elixir-runtime` | Work on Elixir/Phoenix projects or Ash resources, policies and background workflows | Tidewave introspection, installed-version documentation routing, optional AshOban workflow guidance and an Oban Pro reference. |

### Reference files

| File | Skill | Why it's here |
|------|-------|---------------|
| `elixir-runtime/references/oban-pro.md` | `elixir-runtime` | Oban Pro (workflows, grafts, cascades, batches) is commercial/closed-source and under-represented in training data. |
| `elixir-runtime/references/ash-oban.md` | `elixir-runtime` | Conditional guidance for Ash background work, including domain state, reconciliation, identity and version-sensitive scheduling. |

### Why one thin skill

Earlier versions shipped seven "thinking" skills and a router. The current entrypoint stays small and loads detailed references when a task needs them. Ash background work gets a focused review procedure, with verified version facts and concrete revisit conditions; ordinary Phoenix work does not load it. The [current evaluation procedure](evals/ash-workflows/README.md) measures the resulting decisions and distinguishes reasoning evidence from application execution tests.

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
