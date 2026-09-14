# Elixir & Phoenix Security Checklist

Organized by Sobelow's check families plus the Elixir-specific classes Sobelow does not cover. Each item lists what to grep for and the severity to assign when found reachable from user input.

## Remote code execution

| Check | Grep | Notes | Severity |
|---|---|---|---|
| Unsafe `binary_to_term` | `binary_to_term` | Without `[:safe]`, deserializing attacker-controlled binary is RCE. `Plug.Crypto.non_executable_binary_to_term/2` is the safe wrapper. Also check cookies/sessions stored as ETF. | Critical |
| Code evaluation | `Code.eval_string`, `Code.eval_quoted`, `Code.compile_string`, `EEx.eval_string` | Any user input reaching these is RCE. | Critical |
| `:os.cmd` / `System.cmd` with interpolation | `System.cmd`, `:os.cmd` | `System.cmd/3` with a list of args is safe; string interpolation into `:os.cmd` is command injection. | Critical |

## Denial of service

| Check | Grep | Notes | Severity |
|---|---|---|---|
| Atom exhaustion | `String.to_atom`, `List.to_atom`, `binary_to_atom` | Atoms are never GC'd; the table limit is finite. Fix: `String.to_existing_atom` + rescue, or keep strings. | Critical if user-reachable |
| Unbounded body/upload | `Plug.Parsers` opts | Check `length:` on `Plug.Parsers`; default 8MB. Upload endpoints need their own limit. | High |
| Unbounded query | `Repo.all` without `limit` | A list endpoint that returns every row degrades with data growth and can OOM. | High |
| Regex on user input | `Regex.` with user-supplied pattern | User-supplied patterns allow catastrophic backtracking. | High |
| Unbounded mailbox | see `otp_design.md` | Fast producer + `cast` to slow consumer = OOM. | High |

## Injection

| Check | Grep | Notes | Severity |
|---|---|---|---|
| SQL injection | `Ecto.Adapters.SQL.query`, `unsafe_fragment` | Ecto's `^` interpolation is parameterized and safe, and `fragment/1` **rejects** string interpolation at compile time ("fragment(...) with dynamic interpolation is not allowed") — so ordinary `fragment/1` use is not a finding and reporting it is a false positive. The live vectors are `Ecto.Adapters.SQL.query/3` built with `#{}`, and any `unsafe_fragment`-style helper the codebase defines itself. | Critical |
| Query-building from params | `where: ^dynamic`, `order_by: ^` | Column/direction names taken from params must be allowlisted, not interpolated. Sorting by an attacker-chosen column is also an information leak. | High |
| XSS via `raw/1` | `raw(`, `{:safe,`, `Phoenix.HTML.raw` | HEEx escapes by default; `raw/1` opts out. Every call needs a justification and a sanitized source. | Critical |
| XSS via attributes | `href={@...}`, `src={@...}` | A user-controlled `href` accepts `javascript:`. Validate the scheme. | High |
| Content-Type / send_download from params | `send_download`, `put_resp_content_type` | User-controlled content type enables XSS via uploaded files. | High |

## Path traversal

| Check | Grep | Notes | Severity |
|---|---|---|---|
| `send_file` with params | `send_file` | User-controlled path reads arbitrary files. Use an allowlist or a database-backed id → path mapping. | Critical |
| `File.read` / `File.stream!` with params | `File.read`, `File.stream!`, `Path.join` | `Path.join(base, user_input)` does not prevent `../`. Use `Path.safe_relative/2` or verify `Path.expand` stays under the base. | Critical |
| `Plug.Static` `from:` | `Plug.Static` | Serving a directory that contains secrets or uploads. | High |

## Configuration

| Check | Where | Notes | Severity |
|---|---|---|---|
| Secrets in committed config | `config/*.exs` | `secret_key_base`, DB passwords, API keys must come from env at runtime (`config/runtime.exs`), never be committed. Check git history too, not just HEAD. | Critical |
| `force_ssl` / HSTS | endpoint config | Production endpoint missing `force_ssl:` and HSTS. | High |
| CSRF protection | `router.ex` `:browser` pipeline | `protect_from_forgery` present in the browser pipeline; API pipelines correctly exempt. | Critical if missing |
| Secure browser headers | `:browser` pipeline | `put_secure_browser_headers` present; consider a CSP. | Medium |
| Cookie flags | endpoint session opts | `secure: true`, `http_only: true`, `same_site: "Lax"` on the session cookie. | High |
| `debug_errors` / `code_reloader` in prod | `config/prod.exs` | Leak stack traces and source. | Critical |
| Directory listing / dev routes exposed | `router.ex` | `live_dashboard`, `mailbox` routes reachable in prod without auth. | Critical |

## Authentication & authorization

- Every `scope` in `router.ex` that needs auth has the auth plug in its pipeline. Walk the router and list scopes without one — this is the highest-yield single check in a Phoenix audit.
- Authorization is checked on the *object*, not just the session. Grep for `Repo.get(Thing, id)` immediately after reading `params["id"]` with no ownership check — that is IDOR.
- LiveView: `mount/3` auth does not cover `handle_event/3`. Each event handler that acts on an id must re-authorize. See `liveview_patterns.md`.
- Channels: `join/3` authorizes the topic, and topic names containing an id are checked against the socket's user.
- Token handling: `Phoenix.Token` / `Plug.Crypto` with a `max_age`; JWTs with verified signature *and* expiry.
- Password storage: `bcrypt_elixir` / `argon2_elixir`, never a bare hash. Timing-safe comparison (`Plug.Crypto.secure_compare/2`) for tokens.
- Enumeration: login and password-reset returning different responses for known vs unknown accounts.

## Data exposure

- PII in logs: grep `Logger.` for interpolated structs; a logged changeset or params map often contains passwords and tokens.
- `inspect/1` on a struct with sensitive fields — use `@derive {Inspect, except: [:password, :token]}`.
- JSON views rendering whole schemas (`Map.from_struct`) rather than an explicit field list.
- Error responses leaking internals in prod.
- Telemetry/APM handlers attaching full params.

## Dependencies

- `mix hex.audit` — retired packages.
- `mix deps.audit` (`mix_audit`) — known CVEs in deps.
- `mix hex.outdated` — how far behind; a major version behind on Phoenix/Ecto/Plug is a standing risk.
- `mix.lock` committed and CI installing from it.
