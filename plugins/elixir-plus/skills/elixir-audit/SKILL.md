---
name: elixir-audit
description: Perform comprehensive code audits of Elixir, Phoenix, LiveView and Ash applications. Use this skill when the user requests a code audit, architecture review, quality assessment, onboarding review, or "what are the pitfalls" analysis of an Elixir codebase. Analyzes testing (ExUnit, Mox, sandbox), security (Sobelow, atom exhaustion, traversal, unsafe deserialization), OTP and process design (supervision, GenServer bottlenecks, unsupervised tasks), Ecto and query performance (N+1, indexes, transactions, changeset safety), Phoenix boundaries and context design, LiveView state and authorization, Ash resources and policies, and the official Elixir anti-patterns. Outputs a markdown report grouped by category with severity levels (Critical, High, Medium, Low).
---

# Elixir Audit Skill

Comprehensive audit of an Elixir/Phoenix application, based on the official Elixir anti-patterns reference, OTP design principles, Sobelow's security check catalogue, and Ecto/Phoenix/LiveView/Ash idioms.

Execution structure mirrors `rg-rails-audit` in the sister repo `claude-code-raul-skills` (itself ported from thoughtbot, MIT); all Elixir content here is original. Invoke explicitly via `/elixir-audit`.

## When this is an onboarding audit, not a critique

A common use is reading an unfamiliar codebase you have just been given access to — a new client, a new team. In that mode the audience is *you*, not the team that wrote it.

Ask the user which mode applies before generating the report:

- **Orientation mode** — the report is private notes. Lead with an architecture map, the contexts and their boundaries, where the hot paths are, and what would trip up a newcomer's first PR. Findings are framed as "things to know", not "things you did wrong". Do not write the report into the audited repo.
- **Review mode** — the report is a deliverable for the team that owns the code. Standard severity-ranked findings, written to `ELIXIR_AUDIT_REPORT.md` in the project root.

Default to orientation mode when the user says they just got access, are new to the team, or are onboarding.

## Execution Flow

### Step 1: Determine Audit Scope and Mode

- **Mode**: orientation or review (see above).
- **Scope**: full audit covers `lib/`, `test/`, `config/`, `priv/repo/migrations/`, `mix.exs`. Targeted audit covers only the paths given.
- **Stack detection** — read `mix.exs` deps and record which of these are present, because whole sections of this audit only apply if they are:
  - `:phoenix`, `:phoenix_live_view`, `:ecto_sql`, `:ash` / `:ash_postgres` / `:ash_phoenix`, `:oban` / `:oban_pro`, `:broadway`, `:nx` / `:bumblebee`, `:absinthe`
  - umbrella (`apps_path` in `mix.exs`) vs single app
  - Elixir and OTP version from `mix.exs` `elixir:` and `.tool-versions` / `.mise.toml`

### Step 2: Collect Optional Metrics

Ask the user **all three questions upfront** in a single `AskUserQuestion` so they decide once:

- **Question**: "Before starting the audit, collect automated metrics? Each runs tooling against the repo."
  1. **Coverage** — runs the test suite via ExCoveralls to capture real per-module coverage
  2. **Static analysis** — Credo (strict) plus Dialyzer, if a PLT can be built
  3. **Security scan** — Sobelow plus `mix deps.audit` / `mix hex.outdated`
- **Options**: "All three (Recommended)" / "Static + security, no test run" / "Security only" / "Skip all"

Prefer "Static + security" when auditing a client repo you do not yet trust to run locally — the test suite may touch real services, seed data, or require credentials you do not have. Say so when recommending.

#### Set up a disposable working copy first

All three agents install dev-only dependencies and run Mix tasks, which rewrites `mix.exs`, `mix.lock`, `deps/` and `_build/`. **Never do that in the repo being audited** — it is very likely someone else's working tree, possibly with uncommitted changes.

Before spawning anything, create one throwaway copy and record its path as `{{WORKDIR}}`:

```bash
# Preferred: a git worktree at the audited commit. Cheap, and cannot touch the original tree.
AUDIT_DIR=$(mktemp -d)/audit
git -C <repo> worktree add --detach "$AUDIT_DIR" HEAD

# Fallback when the repo is not a git checkout, or worktree creation fails:
cp -R <repo> "$AUDIT_DIR"
```

Note for the report whether the worktree is at `HEAD` while the user's tree has uncommitted changes — in that case the metrics describe committed code, not what is on disk.

**Run the accepted agents sequentially in `{{WORKDIR}}`, not in parallel.** They all mutate the same `mix.exs`/`mix.lock` and all run `mix deps.get`; running them concurrently in one tree corrupts the dependency state, and giving each its own tree means compiling the project three times. Sequential in a shared worktree compiles once and each agent inherits the previous one's `_build`, which makes the second and third agent much faster.

Order them cheapest-first so a failure costs least: **static analysis → security scan → coverage**.

**Static analysis subagent** (if accepted):

> Read the file `agents/static_analysis_agent.md` and follow all steps described in it. Work entirely inside the disposable worktree at {{WORKDIR}} — never in the original repository. The audit scope is: {{SCOPE from Step 1}}. Return the data in the output format specified in that file.

**Security scan subagent** (if accepted):

> Read the file `agents/security_scan_agent.md` and follow all steps described in it. Work entirely inside the disposable worktree at {{WORKDIR}} — never in the original repository. The audit scope is: {{SCOPE from Step 1}}. Return the data in the output format specified in that file.

**Coverage subagent** (if accepted):

> Read the file `agents/coverage_agent.md` and follow all steps described in it. Work entirely inside the disposable worktree at {{WORKDIR}} — never in the original repository. The audit scope is: {{SCOPE from Step 1}}. Return the coverage data in the output format specified in that file.

**After the agents finish**, remove the working copy:

```bash
git -C <repo> worktree remove --force "$AUDIT_DIR"   # or: rm -rf "$AUDIT_DIR"
git -C <repo> worktree prune
```

Then confirm the audited repo is untouched: `git -C <repo> status --short` should show exactly what it showed before the audit started. Say so in the report.


**Interpreting responses:**
- `COVERAGE_FAILED` / `STATIC_FAILED` / `SECURITY_FAILED`: no data for that tool — fall back to manual estimation and note the failure reason in the report. A failure is itself a finding if the cause is that the suite does not run from a clean checkout.
- `COVERAGE_DATA` / `STATIC_DATA` / `SECURITY_DATA`: parse and keep in context for Steps 4 and 5.

### Step 3: Load Reference Materials

Read the reference files that the detected stack makes relevant:

Always:
- `references/elixir_antipatterns.md` — the official code/design/process/macro anti-patterns
- `references/otp_design.md` — supervision, GenServer, concurrency, process boundaries
- `references/testing_guidelines.md` — ExUnit, async, sandbox, Mox, LiveView tests
- `references/security_checklist.md` — Sobelow catalogue plus Elixir-specific classes
- `references/tooling.md` — what each tool catches and how to read its output

If Ecto is present:
- `references/ecto_patterns.md`

If Phoenix is present:
- `references/phoenix_patterns.md` — contexts, boundaries, controllers, plugs, channels

If LiveView is present:
- `references/liveview_patterns.md`

If Ash is present:
- `references/ash_patterns.md`

### Step 4: Analyze Code by Category

Analyze in this order. Skip categories whose stack is absent.

1. **Architecture & Boundaries**
   - Context modules: does `lib/my_app/` separate domain from `lib/my_app_web/`?
   - Web layer calling `Repo` directly, or reaching into another context's schemas
   - Umbrella app dependency direction; cycles (`mix xref graph --format cycles`)
   - Compile-time dependency hotspots (`mix xref graph --label compile-connected`) — a module whose change recompiles most of the app
   - God contexts: a single context module over ~400 lines or covering unrelated concerns
   - Behaviour/protocol use where runtime dispatch is actually needed vs speculative indirection

2. **Testing Coverage & Quality**
   - Use real ExCoveralls numbers if collected; otherwise map each `lib/**/*.ex` to a `test/**/*_test.exs`
   - `async: true` adoption rate, and cases that cannot be async and why
   - Ecto sandbox setup correctness (shared mode leaks, `start_supervised` ownership)
   - `Mox` behaviour-backed mocks vs ad-hoc stubs or `:meck`; `Mox.verify_on_exit!` present
   - `Process.sleep` in tests (flake source) — prefer `assert_receive` / polling helpers
   - Doctests registered (`doctest MyMod`) where `@doc` has examples
   - Property tests (StreamData) on parsing/serialization code
   - LiveView tests using `Phoenix.LiveViewTest` rather than only controller tests
   - Factories: fixtures vs ExMachina; deep factory graphs that hide setup cost

3. **Security**
   - Everything in `references/security_checklist.md`
   - Prioritize: unsafe atom creation from user input, `binary_to_term` without `[:safe]`, `Code.eval_*`, raw SQL fragments with interpolation, `raw/1` on user data, path traversal in `send_file` / `File.read`, missing auth plug on a scope, secrets in `config/*.exs` rather than runtime env

4. **Ecto & Data Layer**
   - N+1: `Repo` calls inside `Enum.map` / comprehensions / `render` / LiveView `render`
   - Missing `preload`, or `preload` inside a loop
   - Unbounded `Repo.all` without `limit`
   - Missing DB indexes: foreign keys, columns in `where`/`order_by` hot paths, polymorphic columns, and every `unique_constraint` without a matching unique index
   - `unsafe_validate_unique` without the DB constraint behind it
   - Changesets: `cast` with an over-broad field list; `cast_assoc` on user-controlled params
   - Transactions: multi-step writes without `Ecto.Multi`/`Repo.transaction`; side effects (email, HTTP) inside a transaction
   - Migrations: references without `on_delete`, `concurrently` indexes without `@disable_ddl_transaction`, data backfills in the same migration as schema change, no `down`
   - `Repo.get!` vs `Repo.get` error-handling mismatch at the boundary

5. **Process & OTP Design**
   - Unsupervised `spawn` / `Task.start` / `Task.async` without a supervisor
   - GenServer as a serialization bottleneck (every request funneling through one process)
   - Blocking work in `init/1` instead of `handle_continue`
   - `GenServer.call` with the default 5s timeout on work that can exceed it
   - State that belongs in ETS, Registry, or a database held in a single process
   - Unbounded mailbox growth; no back-pressure on producers
   - Restart strategy mismatched to actual dependencies between children
   - Global/named singletons that prevent horizontal scaling
   - Oban (if present): job idempotency, `unique`, `max_attempts`, long-running jobs blocking a queue, missing `Oban.Testing`

6. **Elixir Code Quality**
   - The official anti-patterns from `references/elixir_antipatterns.md`, with file:line evidence
   - Long parameter lists; primitive and boolean obsession
   - Non-assertive map access (`map[:key]` where `map.key` is meant) and non-assertive pattern matching
   - Complex `else` clauses in `with`; `with` chains that lose error context
   - Functions over ~30 lines or with deeply nested `case`/`cond`
   - Exceptions used for control flow; `!`-functions at boundaries that should return tagged tuples
   - Inconsistent return contracts (`{:ok, x} | x | nil` from the same function family)
   - Missing `@spec` on public API modules; Dialyzer findings if collected
   - Macros that could be plain functions; compile-time deps created by `use`

7. **Phoenix Web Layer** (if present)
   - Business logic in controllers; controllers calling `Repo`
   - Missing or misapplied pipelines (`:browser` vs `:api`); a scope without its auth plug
   - `action_fallback` and consistent error rendering
   - Params handled without pattern matching on the expected shape
   - Channels: authorization in `join/3`, unbounded broadcast payloads
   - Telemetry/logging: PII in logs, missing request correlation

8. **LiveView** (if present)
   - Socket assign bloat: large collections in assigns instead of `stream/3` or `temporary_assigns`
   - Authorization done only in `mount/3` and not re-checked in `handle_event/3`
   - Unvalidated params in `handle_event`; trusting hidden form fields or DOM ids
   - Expensive work in `render/1` or recomputation that belongs in an assign
   - Missing `on_mount` hooks for shared auth/session
   - `handle_info` growing into a catch-all
   - N+1 triggered per-event

9. **Ash** (if present)
   - Business logic in controllers/LiveViews instead of actions
   - Hand-written Ecto changesets bypassing Ash resources
   - Resources without policies, or `authorize?: false` / bypasses used as an escape hatch
   - `Ash.read!` and friends called without an `actor`
   - Manual loading where calculations/aggregates exist
   - Code interfaces missing, so callers build queries inline
   - Side effects in `change` hooks that belong in `after_action` (or vice versa)

10. **External Services & Failure Handling**
    - HTTP clients without timeouts (connect *and* receive) or retry policy
    - Synchronous third-party calls on the request path that should be backgrounded
    - Bare `rescue`/`catch` swallowing errors; `_ = Repo.insert(...)` ignoring the result
    - Missing circuit breaking or rate limiting on shared upstreams
    - Secrets read at compile time (`Application.compile_env`) that should be runtime (`Application.get_env` / `runtime.exs`)

11. **Build, Deps & Config**
    - `mix compile --warnings-as-errors` clean?
    - `mix format --check-formatted` clean? `.formatter.exs` present?
    - Retired/vulnerable deps (`mix hex.audit`, `mix deps.audit`); how far behind (`mix hex.outdated`)
    - `config/runtime.exs` used for anything environment-specific
    - `mix.lock` committed; CI running the same checks

### Step 5: Generate the Report

Use `references/report_template.md`.

- **Review mode**: write `ELIXIR_AUDIT_REPORT.md` in the project root and present it.
- **Orientation mode**: write to the path the user names (or ask). Never write into the audited repo. Lead with the architecture map section and label the file as private notes.

Every finding needs: file and line, what is wrong, why it matters in *this* codebase, and a concrete fix. A finding without a `path/to/file.ex:42` reference is a guess — drop it or verify it.

## Severity Definitions

- **Critical**: exploitable security issue, data loss or corruption risk, guaranteed production outage path
- **High**: performance cliff under real load, missing tests on a money/auth path, process design that will not survive scaling
- **Medium**: anti-patterns and boundary violations that raise the cost of every future change
- **Low**: style, naming, missing specs, small cleanups

## Key Detection Patterns

### N+1 queries
Grep for `Repo.` inside `Enum.map`, `Enum.each`, `for ... do`, `|> Enum.`, and inside `render/2` or LiveView `render/1`. Also look for `preload` called per-item rather than on the base query.

### Unsupervised processes
Grep for `spawn(`, `spawn_link(`, `Task.start(`, `Task.async(` outside a `Task.Supervisor`/`Task.async_stream` context. `Task.async` is fine when awaited in the same function; flag it when the result is never awaited.

### Atom exhaustion
Grep for `String.to_atom`, `List.to_atom`, `:erlang.binary_to_atom` and trace the argument. Safe only when the input is a compile-time-known set. `String.to_existing_atom` is the fix.

### Unsafe deserialization
Grep for `:erlang.binary_to_term` / `Plug.Crypto.non_executable_binary_to_term` — the former without `[:safe]` on untrusted input is remote code execution.

### GenServer bottleneck
For each GenServer, ask: is there exactly one of these, and does every request path go through it? Check `handle_call` bodies for work over ~1ms (DB queries, HTTP, heavy computation). That work belongs in the caller or a pooled worker.

### Boundary violation
Grep `lib/*_web/` for `Repo.`, `Ecto.Query`, or direct aliases of schema modules from another context.

### Missing index
For every `unique_constraint(:field)` in a changeset, confirm a `create unique_index(...)` exists in `priv/repo/migrations/`. For every `belongs_to`, confirm an index on the FK column.

## Analysis Commands

Prefer Claude Code's built-in tools over shell where they fit:

- **Find modules by layer**: Glob with `lib/**/*.ex`, `lib/*_web/**/*.ex`, `lib/*/schema*/**/*.ex`, `test/**/*_test.exs`, `priv/repo/migrations/*.exs`
- **Search patterns**: Grep for `Repo\.`, `String\.to_atom`, `binary_to_term`, `raw\(`, `spawn`, `Process\.sleep`, `rescue\s*$`, `authorize\?:\s*false`
- **Dependency graph and cycles**: Bash — `mix xref graph --format cycles`, `mix xref graph --label compile-connected --format stats`
- **Module sizes**: Bash — `find lib -name '*.ex' | xargs wc -l | sort -rn | head -30` (not `wc -l lib/**/*.ex`; bash does not expand `**` recursively without `globstar`, so the glob form silently misses anything nested more than one level deep)
- **Read** individual modules to judge responsibility and complexity

## Report Output

Review mode: `ELIXIR_AUDIT_REPORT.md` in the project root. Orientation mode: a path outside the audited repo. Present the report either way.
