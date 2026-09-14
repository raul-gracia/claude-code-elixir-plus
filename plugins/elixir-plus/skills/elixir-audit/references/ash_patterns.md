# Ash Framework Review

Applies when `:ash` is in `mix.exs`. Ash inverts the usual Phoenix structure: resources declare actions, and the framework derives queries, changesets, authorization, and APIs from them. Most Ash findings are about code that works *around* the framework rather than with it.

## Resources and actions

- **Business logic outside actions.** Logic in a controller or LiveView that builds a changeset step by step belongs in a custom action with `change` modules. Grep `lib/*_web/` for `Ash.Changeset.` — construction outside the resource is the smell.
- **Hand-written Ecto changesets / direct `Repo` calls** on a resource-backed schema. This bypasses actions, validations, policies, and notifications entirely. Critical if it bypasses a policy.
- **Default actions used for everything** (`defaults [:create, :read, :update, :destroy]`) with authorization and validation bolted on elsewhere. Named actions (`:register`, `:publish`, `:archive`) express intent and scope their own accept lists.
- **`accept` lists** — the Ash equivalent of `cast`. An action accepting every attribute is mass assignment. Check especially `:create` and `:update` defaults.
- **`argument` + `change` vs accepting raw attributes** for values needing transformation.
- Validations declared on the resource vs scattered in calling code.

## Authorization / policies

This is where Ash pays for itself, and where audits find the most.

- **Resources with no `policies` block at all.** If `authorize?` is configured as `:by_default` or `:always`, a resource with no policies denies everything (noisy but safe). If authorization is not enforced by default, a resource with no policies is wide open. Determine which mode the app is in first — it changes the severity of every other finding here.
- **`authorize?: false`** passed at call sites. Each one is an intentional bypass; each needs a reason. Grep it and list every occurrence with its justification (or absence).
- **Missing `actor`.** `Ash.read!(Query, actor: nil)` or code interface calls without `actor:` — policies that reference the actor cannot evaluate. Grep for `Ash.read`, `Ash.create`, `Ash.update`, `Ash.destroy` and check every call passes an actor where policies expect one.
- **`bypass` blocks** — they short-circuit all subsequent policies. An over-broad bypass (e.g. any admin bypasses everything) is a standing risk. List them.
- **Field policies** for attribute-level access; check sensitive attributes (`sensitive? true`) are both marked and policy-protected.
- **Policy tests** — policies are logic and need tests with different actors. A resource with policies and no authorization tests is a High finding.
- `forbid_if` / `authorize_if` ordering: policies are checked in order and the first decisive check wins. Read them carefully; ordering bugs are silent.

## Queries, calculations, aggregates

- Manual loading in application code where a `calculation` or `aggregate` exists (or should). Aggregates push the work to SQL; manual loading is N+1 in disguise.
- `Ash.Query.load/2` for related data rather than separate reads.
- Calculations that are expensive and not `calculate` -expressed in SQL — check whether they run per-record in Elixir.
- `Ash.Query.filter` built from user params without an allowlist.
- Pagination declared on read actions (`pagination offset?: true, required?: true`) — unpaginated reads on growing tables.

## Code interfaces

- `define :register, action: :register` on the domain gives callers a plain function instead of query-building. Missing code interfaces mean every caller constructs `Ash.Query`/`Ash.Changeset` inline, spreading framework detail through the app.
- Check the domain module (`Ash.Domain`) lists its resources and defines interfaces for the common paths.

## Changes, preparations, hooks

- Side effects in a `change` module's main body rather than in `after_action` — the change runs during changeset construction, so effects fire even if the transaction later fails.
- `before_action` doing work that belongs in a validation.
- `Ash.Notifier` (including `Ash.Notifier.PubSub`) used for post-commit fan-out rather than manual broadcasting in the caller.
- Atomic updates (`change atomic_update/2`) vs read-modify-write races.

## Extensions

- `AshPostgres`: `references` with `on_delete`, custom indexes declared in the `postgres` block, migrations generated (`mix ash_postgres.generate_migrations`) and reviewed rather than hand-edited.
- `AshPhoenix`: `AshPhoenix.Form` used for forms rather than raw changesets.
- `AshJsonApi` / `AshGraphql`: which actions are exposed, and whether exposure matches the policy surface. An action exposed over GraphQL with weak policies is reachable by anyone with the endpoint.
- `AshAuthentication`: strategies configured, tokens with expiry, `sign_in` action policies.
- `AshOban` (if present): triggers idempotent, same concerns as `otp_design.md`'s Oban section.

## Testing

- Tests going through actions (`Ash.create!(...)`) rather than inserting with `Repo` — a test that seeds with `Repo.insert` does not exercise validations or policies and gives false confidence.
- `Ash.can?/3` assertions for policy coverage.
- Generators/factories built on actions.
