---
name: elixir-audit
description: Perform comprehensive code audits of Elixir, Phoenix, LiveView and Ash applications. Use this skill when the user requests a code audit, architecture review, quality assessment, onboarding review, or "what are the pitfalls" analysis of an Elixir codebase. Examines architecture and context boundaries, testing posture, security, OTP and process design, Ecto data access and migrations, the Phoenix web layer, LiveView, Ash resources and policies, and the official Elixir anti-patterns, checking claims against primary sources and the installed versions' docs. Reads source only: it never runs Mix, the test suite, or any database. Outputs a markdown report grouped by category with severity levels (Critical, High, Medium, Low).
disable-model-invocation: true
---

# Elixir Audit Skill

A repeatable audit procedure for an Elixir/Phoenix application: what to examine, in what order, how to rate it, and how to report it. This skill deliberately carries no fact tables. Facts about APIs, defaults and version behaviour come from primary sources (below), checked against the versions the project actually locks.

Execution structure mirrors `rg-rails-audit` in the sister repo `claude-code-raul-skills` (itself ported from thoughtbot, MIT); all Elixir content here is original. Invoke explicitly via `/elixir-audit`.

## Source only

This audit reads files; the only file it writes is the report (Step 5). It never runs Mix, never fetches or installs deps, never creates a worktree or copy of the repo, never touches a database, and never runs the test suite. The only commands it runs are read-only: `git rev-parse`, `git --no-optional-locks status --porcelain -- .`, `git log`, and `find`/`grep`/`wc` over the source tree. For the whole audit it also never calls Tidewave or any other MCP or runtime tool (`project_eval`, `execute_sql_query`, `get_logs` and the like), nor anything else that executes project code or touches a database; this overrides `elixir-runtime`'s "prefer Tidewave" guidance until the audit ends.

Measured metrics (coverage, Credo/Dialyzer, Sobelow, dependency CVEs) are not collected by this version. When the project already has their output on disk, read it (Step 2); otherwise the report lists the commands the user can run themselves: `mix compile --warnings-as-errors`, `mix format --check-formatted`, `mix xref graph --format cycles`, `mix credo --strict`, `mix dialyzer`, `mix sobelow`, `mix deps.audit`, `mix hex.audit`, `mix hex.outdated`, `mix coveralls`.

## Primary sources

Do not rely on memory for what an API does, what a default is, or which version changed it. Use these, at the version in `mix.lock`:

- **Official Elixir anti-patterns guide** — the code, design, process and meta-programming pages: `hexdocs.pm/elixir/code-anti-patterns.html`, `design-anti-patterns.html`, `process-anti-patterns.html`, `macro-anti-patterns.html`. Use its pattern names in findings.
- **Sobelow's check list** — `hexdocs.pm/sobelow` — for the catalogue of Phoenix security classes.
- **Installed-version docs** for Phoenix, Plug, Ecto/`ecto_sql`, Phoenix LiveView, Ash (and its extensions) and Oban: `hexdocs.pm/<package>/<locked version>`.

When a finding depends on a default or on version-specific behaviour, verify it against the installed version: the package source under `deps/` when it is already present (read it; never fetch it), otherwise that version's hexdocs. If you cannot verify it, say so in the finding and lower its confidence rather than asserting it.

## When this is an onboarding audit, not a critique

A common use is reading an unfamiliar codebase you have just been given access to — a new client, a new team. In that mode the audience is *you*, not the team that wrote it.

Ask the user which mode applies before generating the report:

- **Orientation mode** — the report is private notes. Lead with an architecture map, the contexts and their boundaries, where the hot paths are, and what would trip up a newcomer's first PR. Findings are framed as "things to know", not "things you did wrong". Do not write the report into the audited repo.
- **Review mode** — the report is a deliverable for the team that owns the code. Standard severity-ranked findings, written to `ELIXIR_AUDIT_REPORT.md` in the project root.

Default to orientation mode when the user says they just got access, are new to the team, or are onboarding.

## Execution Flow

### Step 1: Determine Audit Scope and Mode

- **Mode**: orientation or review (see above).
- **Scope**: full audit covers `lib/`, `test/`, `config/`, `priv/repo/migrations/`, `mix.exs`. For an umbrella: `apps/*/lib`, `apps/*/test`, `apps/*/priv/repo/migrations`, `config/`, the root `mix.exs` and every `apps/*/mix.exs`. Targeted audit covers only the paths given.
- **Project location** — record the Mix project's path relative to the git toplevel (`git rev-parse --show-prefix` run in the directory holding `mix.exs`; empty when they coincide). A monorepo `backend/` is common; report paths relative to the Mix project.
- **Commit audited** — record `git rev-parse HEAD`, and whether `git --no-optional-locks status --porcelain -- .` (run in the Mix project directory) is empty, ignoring this skill's own `ELIXIR_AUDIT_REPORT.md`. With uncommitted changes, the audit describes what is on disk, not `HEAD`; say so in the report. Skip both when the project is not a git checkout.
- **Stack detection** — record which of these are present, because whole sections of this audit only apply if they are. Read `mix.lock` (authoritative for what is actually in the dependency tree, and the source of every version you cite) plus the `deps/0` of every app: the root `mix.exs` of an umbrella declares no app deps, so for an umbrella read each `apps/*/mix.exs` and note which apps carry `:phoenix`.
  - `:phoenix`, `:phoenix_live_view`, `:ecto_sql`, `:ash` / `:ash_postgres` / `:ash_phoenix` / `:ash_oban`, `:oban` / `:oban_pro`, `:broadway`, `:nx` / `:bumblebee`, `:absinthe`
  - umbrella (`apps_path` in `mix.exs`) vs single app
  - Elixir and OTP versions: `mix.exs` `elixir:` is a requirement, not the version in use. Read the actual versions from `.tool-versions`, `mise.toml` / `.mise.toml`, the Dockerfile (`ARG ELIXIR_VERSION` / `OTP_VERSION` or the base image tag) or CI config; if none pins them, record the requirement and say "requirement only"

### Step 2: Read Existing Tool Output

Do not run any tool. Check whether the project already carries tool configuration or output, and read what exists:

- `.credo.exs` — which checks are disabled or tuned; a config that disables large numbers of checks is itself worth reporting.
- `.dialyzer_ignore.exs` (or the `ignore_warnings:` file named in `mix.exs` `dialyzer:`) — what the team has accepted; its size says how seriously Dialyzer is run.
- `.sobelow-skips` and `.sobelow-conf` — previously accepted Sobelow findings and the scan configuration.
- Coverage output already on disk (`cover/excoveralls.json`, `cover/lcov.info`, `cover/*.html`) or a CI coverage artifact the user points you to. It describes whatever commit produced it: compare its timestamp with `git log -1 --format=%ci` and say how stale it is. Never present it as a measurement of `HEAD`.
- CI configuration (`.github/workflows/*.yml`, `.gitlab-ci.yml`, `.circleci/config.yml`, etc.) — which of compile-with-warnings-as-errors, format check, Credo, Dialyzer, Sobelow, `deps.audit`, and the test suite actually run on every change.
- Whether `:credo`, `:dialyxir`, `:sobelow`, `:mix_audit`, `:excoveralls` appear in `mix.exs` deps and `mix.lock`.

Record what was found and what was absent; the report's "Scope and method" section uses it. Existing scanner output is a lead, not a finding: read the code before reporting anything it lists.

### Step 3: Load Stack-Specific References

This skill's only bundled reference is `references/report_template.md` (Step 5). Two sibling references from the `elixir-runtime` skill load by stack:

- If AshOban is present: `../elixir-runtime/references/ash-oban.md` — the AshOban workflow reference; use it for trigger-backed jobs in the Process & OTP and Ash sections.
- If Oban Pro is present: `../elixir-runtime/references/oban-pro.md`.

### Step 4: Analyze Code by Category

Analyze in this order. Skip categories whose stack is absent. For each, answer the questions with file:line evidence; consult the primary sources above for what the correct or current behaviour is.

Items a tool would normally measure (xref cycles and hotspots, compile warnings, formatting, dependency audits, coverage) are judged from the source and any existing output found in Step 2. Say in the report which ones were judged from source only, and list the command that would measure each under "Commands to run yourself".

1. **Architecture & Boundaries**
   - Is domain code separated from the web layer? Does the web layer reach into persistence or into another context's internals?
   - Umbrella: read each `apps/*/mix.exs` `deps/0` for `in_umbrella: true` edges. Does the dependency direction run web → domain, and are there cycles?
   - Do contexts reference each other's internal modules? Which pairs reference each other?
   - Which modules are compile dependencies of many files (`use`, macro calls, function calls in a module body, plus anything those reach transitively), so a change to them recompiles most of the app? Struct usage, `require` and imports used only for functions are export dependencies, which recompile callers only when the module's API changes.
   - Are there god contexts: one module very large, or covering unrelated concerns?
   - Is each behaviour or protocol earning its indirection, or is it speculative?

2. **Testing Coverage & Quality**
   - Which `lib/**/*.ex` modules have no matching `test/**/*_test.exs`? Before calling one untested, check whether context- or integration-level tests exercise it (phx.gen.auth, for example, tests its user token schema through `accounts_test.exs` and the auth controller/LiveView tests). What remains is the first list. Cite an existing coverage report from Step 2 only with its age.
   - How much of the suite runs async, and why can the rest not?
   - Is database isolation set up so tests cannot leak state into each other?
   - Are external boundaries mocked against explicit contracts, or with ad-hoc stubs?
   - Do tests wait on time rather than on messages or observable state (a flake source)?
   - Are documented examples executed as doctests? Does parsing/serialization code have property tests?
   - Is interactive UI (LiveView) tested through its own test tooling? Do factories hide expensive setup?

3. **Security** — work through Sobelow's check classes, then the Elixir-specific questions:
   - Can user input reach atom creation, code evaluation, or deserialization of untrusted terms?
   - Can user input reach raw SQL or query fragments, unescaped HTML, file paths, or redirects?
   - Does every route scope, channel join and LiveView event that touches protected data enforce authentication and authorization?
   - Are login, password reset, magic-link, registration and similar endpoints rate-limited or otherwise protected against brute force and enumeration?
   - Can a user-controlled URL reach an HTTP client (webhook targets, import/fetch-from-URL, avatar or link previews) without an allowlist, so the server can be pointed at internal hosts (SSRF)?
   - Are secrets committed in `config/*.exs` or fixed at compile time rather than read at runtime?
   - Are session, cookie, CSRF, TLS and security-header settings correct for the installed Plug/Phoenix version? Verify each against that version's docs before reporting.

4. **Ecto & Data Layer**
   - Are there queries inside loops, comprehensions or render paths (N+1), or associations loaded per item rather than on the base query?
   - Are list queries bounded?
   - Does every uniqueness rule and every foreign key used in lookups have a backing index in `priv/repo/migrations/`?
   - Which fields can a changeset accept from user params, including nested associations, and should it?
   - Are multi-step writes atomic? Do side effects (email, HTTP, jobs) happen inside a transaction that can still roll back?
   - Are migrations safe to run against production data: locking, concurrent index builds, reversibility, backfills mixed with schema changes, delete behaviour on references? Check the installed `ecto_sql` docs and the repo config for how the project's migrations lock and run.
   - Is "not found" handled the same way at each boundary?

5. **Process & OTP Design**
   - Is every long-lived process started under a supervisor, and is every async result either awaited or deliberately fire-and-forget under supervision?
   - Does any single process serialize work that every request needs? Does it do slow work (DB, HTTP, heavy computation) inside its callbacks?
   - Can startup block the supervision tree?
   - Do synchronous calls have timeouts that match the work they wait on?
   - Is state held in one process that belongs in ETS, a Registry or the database? Can mailboxes grow without back-pressure?
   - Does each restart strategy match the real dependencies between children? Do named singletons block running more than one node?
   - Background jobs (if present): are they idempotent, deduplicated where they must be, bounded in retries and duration, and tested?

6. **Elixir Code Quality**
   - Which patterns from the official anti-patterns guide appear? Name them as the guide does, with file:line evidence.
   - Are there long parameter lists, primitive or boolean obsession, or non-assertive access and matching?
   - Do `with` chains keep error context, or collapse it in a complex `else`?
   - Are there very long functions or deeply nested branching?
   - Are exceptions used for control flow? Do boundaries return a consistent contract (tagged tuples vs raising vs `nil`)?
   - Do public API modules carry typespecs? What does the Dialyzer ignore file suppress, if present?
   - Could a macro be a plain function?

7. **Phoenix Web Layer** (if present)
   - Does business logic or persistence live in controllers?
   - Does every router scope use the right pipeline and auth plug, and every `live_session` the right `on_mount` hooks? Live navigation within a `live_session` does not go through the plug pipeline, so LiveView authorization must come from `on_mount`/`mount`. Fill the router audit table in the report.
   - Are errors rendered consistently (fallback controllers or equivalent)?
   - Are params matched against an expected shape before use?
   - Channels: is authorization checked on join? Are broadcast payloads bounded?
   - Logging and telemetry: is PII logged? Can a request be correlated across logs?

8. **LiveView** (if present)
   - Does socket state hold large or growing collections? Check the installed LiveView docs for the mechanisms that version offers for large collections.
   - Is authorization enforced on every event that changes data, not only when the view mounts?
   - Are event params, hidden fields or DOM ids trusted without validation?
   - Is expensive work repeated on every render instead of computed once?
   - Is shared auth/session logic centralised or repeated per view?
   - Have catch-all message handlers grown unbounded? Does any event trigger an N+1?

9. **Ash** (if present)
   - Does business logic live in actions, or in controllers and LiveViews around them?
   - Do hand-written Ecto changesets bypass the resources?
   - Does every resource reachable from user input have policies? Where are policies bypassed or authorization turned off, and is each bypass justified?
   - Does each action's `accept` list (including `accept :*` or `default_accept :*`) let a caller set attributes they must not control — role, tenant or organisation id, ownership, status flags? That is privilege escalation even when policies exist.
   - Which calls run without an actor, and does the domain's authorization configuration enforce policies for those calls? Read the domain and resource config and verify the behaviour against the installed Ash version's docs before rating it.
   - Is data loaded by hand where calculations or aggregates fit? Are code interfaces missing, so callers build queries inline?
   - Do change hooks run side effects at the right point relative to the transaction?

10. **External Services & Failure Handling**
    - Do HTTP clients set timeouts and a retry policy?
    - Are slow third-party calls on the request path that could be backgrounded?
    - Are errors or return values swallowed (bare rescues, ignored results)?
    - Is there circuit breaking or rate limiting on shared upstreams?

11. **Build, Deps & Config**
    - Compile warnings are not observable without compiling: report whether CI compiles with warnings as errors; if not, suggest the command.
    - Is there a formatter config, and does CI check it?
    - List the locked versions of the main framework deps. Call one outdated only when you can verify the current release; CVE and retirement status come from `mix deps.audit` / `mix hex.audit`, which the user runs.
    - Is environment-specific config read at runtime? Is `mix.lock` committed, and does CI run the checks the team relies on?

### Step 5: Generate the Report

Use `references/report_template.md`.

- **Review mode**: write `ELIXIR_AUDIT_REPORT.md` in the project root and present it.
- **Orientation mode**: write to the path the user names (or ask). Never write into the audited repo. Lead with the architecture map section and label the file as private notes.

Every finding needs: file and line, what is wrong, why it matters in *this* codebase, and a concrete fix. A finding without a `path/to/file.ex:42` reference is a guess — drop it or verify it. The exception is a project-level finding (e.g. no CI step runs the test suite, or `mix.lock` is not committed), which cites the evidence instead: the file whose content or absence shows it. A finding that rests on a default or version behaviour names the version and the source it was checked against.

## Severity Definitions

Rate by impact in this codebase, never by which API or pattern is involved. The same construct can be Critical in one place and Low in another.

- **Critical**: exploitable now by an outside party, or by any user who can sign up (e.g. cross-tenant access, IDOR), with a concrete path to it, or likely data loss or corruption, or a guaranteed production outage path.
- **High**: exploitable only with preconditions (an authenticated user, a specific config); incorrect results on a real path; a failure or performance cliff likely under realistic load; a money or auth behaviour with no test at any level (after checking context and integration tests).
- **Medium**: correctness risk that is unlikely or contained; boundary violations and anti-patterns that raise the cost of every future change.
- **Low**: maintainability and style — naming, missing specs, small cleanups — or any finding whose consequence here cannot be stated concretely.

When exploitability or reach cannot be confirmed from source, rate the confirmed part and say what would raise it.

## Analysis Commands

Prefer Claude Code's built-in tools over shell where they fit:

- **Find modules by layer**: Glob with `lib/**/*.ex`, `lib/*_web/**/*.ex`, `test/**/*_test.exs`, `priv/repo/migrations/*.exs`
- **Search**: Grep for the constructs each Step 4 question names, then read the surrounding code and trace inputs to their source before reporting
- **Dependency direction**: read `deps/0` in every `mix.exs` for `in_umbrella: true` edges; Grep each context directory for aliases of other contexts' modules. `mix xref graph` is a command for the user to run, not the auditor
- **Dependencies and versions**: read `mix.lock` and each `mix.exs` `deps/0`
- **Module sizes**: Bash — `find lib -name '*.ex' | xargs wc -l | sort -rn | head -30`, with `apps/*/lib` in place of `lib` for an umbrella (a `lib/**/*.ex` shell glob misses nested files without `globstar`)
- **Read** individual modules to judge responsibility and complexity

## Report Output

Review mode: `ELIXIR_AUDIT_REPORT.md` in the project root. Orientation mode: a path outside the audited repo. Present the report either way.
