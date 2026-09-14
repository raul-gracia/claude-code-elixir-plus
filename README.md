# claude-code-elixir-plus

A Claude Code plugin that grants Claude runtime capabilities for Elixir, Phoenix, Ecto, OTP, Oban, and Ash work. It bundles two skills — the `elixir-runtime` capability grant and the `elixir-audit` workflow — four automated hooks (format, compile, credo, session context injection), and ElixirLS integration.

The `elixir-runtime` skill provides runtime introspection and directs Ash work to documentation for the application's installed versions. General framework tutorials stay upstream. An optional AshOban reference covers workflow decisions and version-sensitive operational behavior, while the existing Oban Pro reference supplies details for the commercial library.

## Installation

```bash
# Add from marketplace
claude plugin add claude-code-elixir-plus

# Or install from source
claude plugin install /path/to/claude-code-elixir-plus
```

## Skills

The plugin ships two skills. `elixir-runtime` is a capability grant for Elixir/Phoenix projects and explicit Ash/AshOban tasks; its description supports native selection, and the session hook injects it when `mix.exs` exists in the working directory. `elixir-audit` is a workflow you invoke explicitly.

| Skill | Triggers When You... | Grants |
|-------|---------------------|--------|
| `elixir-runtime` | Work on Elixir/Phoenix projects or Ash resources, policies and background workflows | Tidewave introspection, installed-version documentation routing, optional AshOban workflow guidance and an Oban Pro reference. |
| `elixir-audit` | Run `/elixir-audit`, or `/elixir-audit lib/my_app/accounts` for a targeted pass | Full or targeted codebase audit: architecture and context boundaries, the official Elixir anti-patterns, OTP and process design, Ecto queries/indexes/migrations, security, ExUnit posture, and LiveView or Ash sections gated on stack detection from `mix.exs`. Optional ExCoveralls, Credo/Dialyzer and Sobelow subagents add measured data, run inside a disposable git worktree so the audited repo is never modified. Orientation mode produces private onboarding notes; review mode produces `ELIXIR_AUDIT_REPORT.md`. |

### Reference files

| File | Skill | Why it's here |
|------|-------|---------------|
| `elixir-runtime/references/oban-pro.md` | `elixir-runtime` | Oban Pro (workflows, grafts, cascades, batches) is commercial/closed-source and under-represented in training data. |
| `elixir-runtime/references/performance.md` | `elixir-runtime` | Measured request-path performance traps for Bandit/Plug, SQLite and websocket fan-out on OTP 28+, plus how to profile a release. |
| `elixir-runtime/references/ash-oban.md` | `elixir-runtime` | Conditional guidance for Ash background work, including domain state, reconciliation, identity and version-sensitive scheduling. |
| `elixir-audit/references/*.md` (9 files) | `elixir-audit` | Audit checklists loaded on demand by detected stack: anti-patterns, OTP design, Ecto, Phoenix, LiveView, Ash, security, testing, tooling. |
| `elixir-audit/agents/*.md` (3 files) | `elixir-audit` | Subagent specs for the ExCoveralls, Credo/Dialyzer and Sobelow metric passes. |

### Why these two, and nothing else

Earlier versions shipped seven "thinking" skills and a router. The current entrypoint stays small and loads detailed references when a task needs them. Ash background work gets a focused review procedure, with verified version facts and concrete revisit conditions; ordinary Phoenix work does not load it. The [current evaluation procedure](evals/ash-workflows/README.md) measures the resulting decisions and distinguishes reasoning evidence from application execution tests.

`elixir-audit` earns its place on different grounds: it is a workflow, not pedagogy. Knowing what an N+1 is does not produce a consistent audit; the skill supplies the execution order, the stack-gated checklists, the subagent specs, and the report shape, so the same repo gets the same passes every time.

## Hooks

Six hooks run automatically -- no configuration needed after install.

| Hook | Event | Fires When | What It Does | Timeout |
|------|-------|------------|-------------|---------|
| `session-start.sh` | `SessionStart` | Session starts, resumes, clears, or compacts | Injects the `elixir-runtime` skill into context (only if `mix.exs` exists) | default |
| `format-elixir.sh` | `PostToolUse` (Edit/Write) | After any file edit or write | Runs `mix format` on the changed `.ex`/`.exs` file | 15s |
| `compile-elixir.sh` | `PostToolUse` (Edit/Write) | After any file edit or write | Runs `mix compile --warnings-as-errors` on changed `.ex` files (skips `.exs`) | 60s |
| `credo-elixir.sh` | `PreToolUse` (Commit) | Before a git commit | Runs `mix credo` on the file; blocks commit if issues found | 30s |
| `block-dangerous-ops.sh` | `PreToolUse` (Bash) | Before any shell command | Denies `mix ecto.drop`/`ecto.reset`, `MIX_ENV=prod`, and force pushes | 10s |
| `error-critic.sh` | `PostToolUseFailure` (Bash/Edit/Write) | After a tool call fails | Counts identical failures; on the 3rd, injects the attempt history and tells the model to stop and escalate | 10s |

The first four hooks walk up from the edited file to find `mix.exs`, so they work in umbrella apps and nested project structures. The credo hook silently skips if credo is not installed in the project.

### Guardrail hooks

`block-dangerous-ops` and `error-critic` exist because prose rules in `CLAUDE.md` fire unreliably -- a shell script on a hook event always runs. Both are adapted from the enforcement-hook design in [oliver-kriska/claude-elixir-phoenix](https://github.com/oliver-kriska/claude-elixir-phoenix).

**`block-dangerous-ops`** splits the command on `&&`, `||`, `;`, `|` **and newline**, then tests each segment independently, so a flag in one segment is never attributed to a command in another (`grep -f pats.txt && git push` is not a force push). Quotes, parens and backticks are flattened before matching, so wrapper forms do not evade the gate:

```
bash -c "mix ecto.drop"              -> denied
eval 'mix ecto.reset'                -> denied
(mix ecto.drop)                      -> denied
git push origin +main               -> denied   (a +refspec is a force push)
git -c core.pager=cat push --force  -> denied

mix ecto.rollback --step 1           -> allowed
git push --force-with-lease   -> allowed
echo "mix ecto.drop"                 -> allowed  (output builtins are skipped)
```

Splitting uses `tr`, not `sed` with a `\n` replacement, because BSD sed (macOS) emits a literal `n` there and would not split at all. The deny is returned as a `permissionDecision`, and it holds even under `--permission-mode bypassPermissions`.

**`error-critic`** hashes a normalised signature of each failure (lowercased, directory prefix dropped but the last two path segments kept, digits collapsed) so the same error at shifting line numbers counts as one repeat -- while `lib/a/user.ex` and `lib/b/user.ex` stay distinct, since fixing one error across several modules is normal work, not a retry loop.

User interruptions and tool rejections are skipped (`is_interrupt`), so pressing Esc three times is not reported back to the model as its own failure loop. After escalating, the counter resets, so the warning does not re-fire on every later attempt once you have said "keep going".

State is per-session, keyed by a sanitised `session_id`, and lives in the session scratchpad or a `0700` dir under `$XDG_STATE_HOME`/`$HOME` -- never in the project directory, and never at a world-predictable `/tmp` path. The read-modify-write is guarded by a `mkdir` lock so parallel tool calls cannot lose an increment. Threshold defaults to 3 and is configurable:

```bash
export ELIXIR_PLUS_ERROR_CRITIC_THRESHOLD=2
```

Both scripts are deliberately **fail-open**: no `set -e`, every error path exits 0. A broken guardrail hook must never wedge a session. Denials are expressed as JSON data rather than exit codes.

### Testing the hooks

```bash
tests/hooks/run.sh
```

59 assertions covering deny/allow cases (including wrapper-bypass and multi-line forms), failure-signature collapsing, session isolation, path traversal, interrupt handling, the `hooks.json` contract, and the fail-open guarantee on malformed input.

Note on `hooks.json`: Claude Code hook `timeout` values are in **seconds**, not milliseconds. The suite asserts no timeout exceeds 300, because a millisecond-style `10000` would let a stalled hook hold up a tool call for nearly three hours.

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
