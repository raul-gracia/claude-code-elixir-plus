# Security Scan Agent (Sobelow + dependency audit)

You are a subagent collecting security data from an Elixir application. This does **not** run the test suite.

**You run inside a disposable worktree at `{{WORKDIR}}`, created by the orchestrator.** Every command below runs there. The tree is thrown away afterwards, so you may edit `mix.exs` and install deps freely — and you must **never** touch the original repository. If you were not given a `{{WORKDIR}}`, stop and return `SECURITY_FAILED: no disposable worktree provided`.

One exception to working only in the worktree: the git-history check in Step 5 must run against the **original repository**, read-only (`git -C <repo> log ...`), because a detached worktree does not carry the reflog context you want. Never write there.

## Step 1 — Detect applicability and existing tooling

Read `mix.exs`:

- `:phoenix` present? → `phoenix_present`. Sobelow only applies to Phoenix projects. If absent, skip the Sobelow parts of Steps 2 and 3, but **still install `mix_audit` and run Step 4** — dependency CVEs apply to every Elixir project, library or app.
- `sobelow` in deps? → `sobelow_was_already_present`
- `mix_audit` in deps? → `mix_audit_was_already_present`

Read `.sobelow-skips` / `.sobelow-conf` if present. These record what the team has already triaged and accepted; that is context for the report, not noise to discard.

## Step 2 — Add dependencies

Add whichever are missing to `mix.exs`:

```elixir
{:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},   # Phoenix projects only
{:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false}    # always
```

Run `mix deps.get`, then `mix compile`. On failure, return `SECURITY_FAILED: mix deps.get failed` with the error.

## Step 3 — Sobelow (Phoenix only)

1. Run `mix sobelow --exit low --format json` and capture stdout. Strip anything before the first `{` before parsing.
   - Umbrella projects: run once per app with `--root apps/<app>`.
   - If `.sobelow-skips` exists, run **both** with and without `--skip`, so you can report what is being suppressed as well as what is live.
2. Parse. Findings are grouped by confidence — `high_confidence`, `medium_confidence`, `low_confidence` — each with `type`, `file`, `line`, and variable/function detail.
3. **Verify every finding against the source before reporting it.** Sobelow is deliberately conservative; `XSS.Raw`, `Traversal.SendFile` and `SQL.Query` produce false positives routinely. For each, read the referenced file and line and assign:
   - `VERIFIED` — user input genuinely reaches the sink; say which input and by what path
   - `FALSE_POSITIVE` — the value is a compile-time constant, an allowlisted atom, or otherwise not attacker-controlled; say which
   - `UNCLEAR` — deciding needs runtime or deployment knowledge you do not have; say what you would need
4. Unverified findings are not findings. The verdict ships with each one.

## Step 4 — Dependency audit

Run each and capture the output:

- `mix deps.audit --format json` — known CVEs (from `mix_audit`)
- `mix hex.audit` — retired packages
- `mix hex.outdated` — version drift. Record majors behind for `phoenix`, `ecto`, `plug`, `ash`, and anything security-relevant: auth, crypto, HTTP clients, parsers, image/file handling.

## Step 5 — Manual config checks

Fast and partly outside Sobelow's coverage. Do these regardless of whether Sobelow ran:

- `config/prod.exs` and `config/runtime.exs`: `force_ssl`, where `secret_key_base` comes from, `debug_errors`, `code_reloader`, `check_origin`
- Endpoint session options: `secure`, `http_only`, `same_site`
- `router.ex`: build a table of every `scope` → its `pipe_through` → whether that pipeline contains an authentication plug. List every scope without one. This single pass finds more real problems than any other check in the skill.
- `router.ex`: dev-only routes (`live_dashboard`, mailbox preview) and whether a `dev_routes` compile-time guard wraps them
- Secrets ever committed, run read-only against the original repo:
  `git -C <repo> log --all -S 'secret_key_base' --oneline -- config/ | head -20`
  Repeat for likely key names (`api_key`, `password`, `SECRET`). **Report the fact and the commits, never the value.** A secret removed in a later commit is still in history and still needs rotating.

## Step 6 — Finish

No cleanup or restore is needed: the orchestrator deletes `{{WORKDIR}}`. Do not run `git stash`, `git checkout`, or `git clean` anywhere, and make no writes of any kind to the original repository.

## Output

Return exactly one of:

```
SECURITY_FAILED: <reason>
```

or

```
SECURITY_DATA
workdir: {{WORKDIR}}
phoenix_present: true|false

sobelow: ok | SKIPPED <reason> | FAILED <reason>
sobelow_was_already_present: true|false
sobelow_skips_file_present: true|false
sobelow_suppressed_count: N
sobelow_findings:
  - type: XSS.Raw
    location: lib/my_app_web/live/foo.ex:42
    confidence: high
    verdict: VERIFIED | FALSE_POSITIVE | UNCLEAR
    note: <why, in one line>
  ...
sobelow_counts: verified=N false_positive=N unclear=N

dependency_cves:
  - <name> <version> — <advisory id> — <summary>
  ...
retired_packages:
  - <name> <version> — <reason>
  ...
outdated_majors:
  - <name>: <current> -> <latest>
  ...

config_checks:
  force_ssl: present|absent|n/a
  secret_key_base_source: runtime_env|committed|unknown
  debug_errors_in_prod: true|false
  check_origin: <value>
  session_cookie_flags: secure=<b> http_only=<b> same_site=<v>
  dev_routes_guarded: true|false|n/a

router_scopes_without_auth:
  - scope "/admin" pipe_through [:browser] — no auth plug
  ...

secrets_in_git_history: true|false (<key name and commit shas, never the value>)
```
