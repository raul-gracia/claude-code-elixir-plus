# Phoenix Review

## Contexts and boundaries

The single most useful architectural question: **does `lib/my_app_web/` know anything about Ecto?**

- Grep `lib/*_web/` for `Repo.`, `import Ecto.Query`, `Ecto.Changeset` (outside form handling), and direct aliases of schema modules from a foreign context. Each hit is a boundary violation.
- Context modules should expose intention-revealing functions (`Accounts.register_user/1`), not CRUD passthroughs (`Accounts.create_user/1` that only calls `Repo.insert`) — though a thin CRUD layer is acceptable for genuinely CRUD resources.
- Cross-context calls should go through the other context's public API, never its schemas.
- **God context**: a context module over ~400 lines, or one covering unrelated concerns (`Accounts` handling users, billing, and notifications). Split along the concepts, not along the schemas.
- Contexts that are one-to-one with schemas are not contexts, they are repositories with extra steps. Note it, but only as a Low finding unless it is causing real coupling.
- Umbrella apps: check dependency direction in each `mix.exs`. Web → domain, never the reverse. Run `mix xref graph --format cycles`.

## Router

Walk `router.ex` top to bottom and build a table of scope → pipeline → auth plug. This catches more real bugs than any other single pass.

- Scopes missing their auth pipeline
- Pipelines defined but never used
- `live_dashboard` and `Plug.Swoosh.MailboxPreview` dev routes reachable in prod (check the `if Application.compile_env(:my_app, :dev_routes)` guard exists)
- Catch-all routes shadowing later ones
- Non-RESTful actions accumulating on a controller — often a missing resource
- `forward` to plugs without their own auth

## Controllers

- **Fat controller**: an action over ~15 lines, or containing business logic (conditionals on domain state, multi-step orchestration). Move it into the context.
- `action_fallback` configured, with a fallback controller handling `{:error, :not_found}`, `{:error, %Ecto.Changeset{}}`, `{:error, :unauthorized}` consistently. Without it, every action repeats error handling.
- Params matched in the function head (`def show(conn, %{"id" => id})`) rather than accessed with `params["id"]`.
- `with` used for the happy path with a meaningful `else`.
- Assigns set in a plug rather than repeated in every action.
- `render` receiving whole schemas rather than an explicit map.

## Views / JSON serialization

- JSON views rendering `Map.from_struct(schema)` or `@derive Jason.Encoder` on the schema — new fields leak automatically.
- Explicit field lists per view, with separate views for different audiences (owner vs public).
- HEEx: logic in templates that belongs in a function component or the controller.
- Function components with `attr`/`slot` declarations (compile-time checked) vs untyped assigns.
- `Phoenix.Component` reuse vs copy-pasted markup.

## Plugs

- Custom plugs with `init/1` doing runtime work — `init/1` runs at compile time in production.
- Plug order in the endpoint: `Plug.Static` before the router, `Plug.Parsers` limits, `Plug.RequestId`, `Plug.Telemetry`.
- Authentication plugs that `halt` correctly — a plug that assigns but does not halt on failure lets the action run.

## Channels / PubSub (if present)

- `join/3` authorizing the topic, including any id embedded in the topic name
- `handle_in` validating payloads
- Broadcast payloads containing full structs (sends everything to every subscriber, including fields the client should not see)
- `Presence` used correctly; unbounded presence lists
- No backpressure on a channel receiving from a fast client

## Telemetry, logging, observability

- `Logger` calls interpolating params, changesets, or structs — PII leak
- Log level in prod
- Request correlation: `Plug.RequestId` and the id propagated into background jobs
- Telemetry events attached for Repo query time, endpoint duration, and custom domain events
- An error tracker (Sentry/AppSignal/Honeybadger) configured, with `Logger` backend integration, and *with* the scrubber configured for params

## Endpoint config

- `force_ssl`, HSTS, secure browser headers, session cookie flags — see `security_checklist.md`
- `check_origin` for websockets set to an allowlist in prod, not `false`
- Static asset cache headers and `cache_static_manifest`
- `server: true` in releases (`config/runtime.exs`)
