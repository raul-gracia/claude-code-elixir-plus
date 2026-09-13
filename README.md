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

Six hooks run automatically -- no configuration needed after install.

| Hook | Event | Fires When | What It Does | Timeout |
|------|-------|------------|-------------|---------|
| `session-start.sh` | `SessionStart` | Session starts, resumes, clears, or compacts | Injects the `elixir-runtime` skill into context (only if `mix.exs` exists) | default |
| `format-elixir.sh` | `PostToolUse` (Edit/Write) | After any file edit or write | Runs `mix format` on the changed `.ex`/`.exs` file | 15s |
| `compile-elixir.sh` | `PostToolUse` (Edit/Write) | After any file edit or write | Runs `mix compile --warnings-as-errors` on changed `.ex` files (skips `.exs`) | 60s |
| `credo-elixir.sh` | `PreToolUse` (Commit) | Before a git commit | Runs `mix credo` on the file; blocks commit if issues found | 30s |
| `block-dangerous-ops.sh` | `PreToolUse` (Bash) | Before any shell command | Denies `mix ecto.drop`/`ecto.reset`, `MIX_ENV=prod`, and `git push --force` | 10s |
| `error-critic.sh` | `PostToolUseFailure` (Bash/Edit/Write) | After a tool call fails | Counts identical failures; on the 3rd, injects the attempt history and tells the model to stop and escalate | 10s |

The first four hooks walk up from the edited file to find `mix.exs`, so they work in umbrella apps and nested project structures. The credo hook silently skips if credo is not installed in the project.

### Guardrail hooks

`block-dangerous-ops` and `error-critic` exist because prose rules in `CLAUDE.md` fire unreliably -- a shell script on a hook event always runs. Both are adapted from the enforcement-hook design in [oliver-kriska/claude-elixir-phoenix](https://github.com/oliver-kriska/claude-elixir-phoenix).

**`block-dangerous-ops`** splits the command on `&&`, `||`, `;` and `|` and tests each segment independently, so a flag in one segment is never attributed to a command in another (`grep -f pats.txt && git push` is not a force push). `--force-with-lease` stays allowed; `mix ecto.rollback` stays allowed. The deny is returned as a `permissionDecision`, and it holds even under `--permission-mode bypassPermissions`.

**`error-critic`** hashes a normalised signature of each failure (lowercased, absolute paths stripped, digits collapsed) so the same error at shifting line numbers counts as one repeat rather than three distinct ones. State is per-session and lives in the session scratchpad or `$TMPDIR` -- never in the project directory. Threshold defaults to 3 and is configurable:

```bash
export ELIXIR_PLUS_ERROR_CRITIC_THRESHOLD=2
```

Both scripts are deliberately **fail-open**: no `set -e`, every error path exits 0. A broken guardrail hook must never wedge a session. Denials are expressed as JSON data rather than exit codes.

### Testing the hooks

```bash
tests/hooks/run.sh
```

39 assertions covering deny/allow cases, failure-signature collapsing, session isolation, and the fail-open contract on malformed input.

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
