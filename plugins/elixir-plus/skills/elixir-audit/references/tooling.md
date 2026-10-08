# Elixir Audit Tooling

What each tool catches, how to run it, and how to read the result. Rough Rails equivalents are given because this skill is a sibling of `rg-rails-audit`.

| Tool | Rails equivalent | Catches |
|---|---|---|
| `mix compile` (warnings) | — | Unused vars, unreachable clauses, deprecated calls, undefined functions. The cheapest signal available. |
| `mix format --check-formatted` | `rubocop -a` | Formatting drift. Binary. |
| Credo (`--strict`) | RuboCop + Reek | Readability, consistency, refactoring opportunities, software design suggestions, some warnings (unused results, operations with constant results). |
| Dialyzer (`dialyxir`) | Sorbet/steep (loosely) | Type discrepancies, impossible patterns, functions that can never return, spec mismatches. Slow first run (PLT build). |
| Sobelow | Brakeman | Phoenix security: XSS, SQLi, traversal, config, CSRF, RCE. |
| `mix deps.audit` (`mix_audit`) | bundler-audit | CVEs in dependencies. |
| `mix hex.audit` | — | Retired packages. |
| `mix hex.outdated` | `bundle outdated` | Version drift. |
| ExCoveralls | SimpleCov | Line coverage. |
| `mix xref graph` | — | Module dependency graph, cycles, compile-time coupling. No Rails equivalent; unique and valuable. |
| `mix app.tree` / `mix deps.tree` | — | OTP application dependency tree / Mix dependency tree. Neither shows the supervision tree — read `application.ex` (or introspect the running system) for that. |
| Doctor / `mix doctor` | — | Documentation coverage (`@doc`/`@spec` presence). Optional. |
| Styler | — | Opinionated auto-formatting beyond `mix format`. Note if present; its absence is not a finding. |

## Commands worth running by hand during the audit

Mix commands run only in the disposable worktree, before cleanup (`cd /recorded/absolute/workdir && mix ...` in every Bash call, the literal path, never `$WORKDIR`) — never in the audited repo, and not at all with "Skip all". The static-analysis agent already returns the xref output. The `find`/`grep` lines only read files and are fine anywhere.

```bash
# Architecture (in the working copy only; substitute the recorded literal path)
cd /recorded/absolute/workdir && mix xref graph --format cycles                          # circular deps — each cycle is a finding
cd /recorded/absolute/workdir && mix xref graph --label compile-connected --format stats # recompilation hotspots
cd /recorded/absolute/workdir && mix app.tree                                            # OTP application dependency tree (not supervision)

# Size and shape
find lib -name '*.ex' | xargs wc -l | sort -rn | head -30
grep -rn "defmodule" lib --include='*.ex' | wc -l

# Quick smells
grep -rn "String.to_atom\|binary_to_term\|Code.eval" lib --include='*.ex'
grep -rn "spawn(\|spawn_link(\|Task.start(" lib --include='*.ex'
grep -rn "Repo\." lib/*_web --include='*.ex'            # boundary violations
grep -rn "authorize?: false" lib --include='*.ex'       # Ash bypasses
grep -rn "Process.sleep" lib test --include='*.ex*'
grep -rnE '\braw[ (]' lib --include='*.heex' --include='*.ex'   # raw(, raw @x, Phoenix.HTML.raw

# Test posture
grep -rln "async: true" test | wc -l
find test -name '*_test.exs' | wc -l
find lib -name '*.ex' | wc -l
```

## Reading Credo output

Credo's categories map to severity as follows for this audit:

- `Software Design` (e.g. `TagTODO`, `TagFIXME`, `AliasUsage`) → Low/Medium, but a large `TODO` count is itself a signal about how the codebase is maintained
- `Code Readability` → Low
- `Refactoring Opportunities` (`CyclomaticComplexity`, `Nesting`, `LongQuoteBlocks`, `FunctionArity`) → Medium; these correlate directly with the anti-patterns in `elixir_antipatterns.md`
- `Warnings` (`UnusedEnumOperation`, `OperationOnSameValues`, `IExPry`, `RaiseInsideRescue`) → High; these are usually real bugs
- `Consistency` → Low

A `.credo.exs` in the repo that disables large numbers of checks is itself worth reporting.

## Reading Dialyzer output

Dialyzer only reports what it can prove. That makes its findings high-confidence and its silence meaningless.

- `The pattern can never match the type` → dead code or a wrong assumption. Real.
- `Function has no local return` → something in it always raises. Real, often a bug.
- `Invalid type specification` → the `@spec` lies. Fix the spec or the code.
- `The call ... will never return` → cascading from the above.

First run needs a PLT build (several minutes). If the repo has no `.dialyzer_ignore.exs` and Dialyzer produces hundreds of findings, the tool has never been run — that is the finding, and triage the top few rather than listing all.

## Reading Sobelow output

Run `mix sobelow --no-config --exit low --format json` for parseable output on stdout (`.sobelow-conf` is loaded by default since 0.14.1 and may redirect it with `out:`). Confidence levels are `:high`, `:medium`, `:low`; low-confidence findings are frequently false positives (Sobelow is conservative about `raw/1` and `send_file`). Verify each one by reading the code before reporting it — a report padded with unverified Sobelow output is worse than no report.

A `.sobelow-skips` file in the repo lists previously-accepted findings. Read it: it tells you what the team already decided to live with.
