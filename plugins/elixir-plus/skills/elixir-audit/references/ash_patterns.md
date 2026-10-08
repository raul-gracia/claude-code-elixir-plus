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

- **Resources without `Ash.Policy.Authorizer`.** Only a resource listing `Ash.Policy.Authorizer` in `authorizers:` is policy-checked. A resource without it is not authorized at all, whatever the domain's `authorize` setting (`:always` / `:by_default` / `:when_requested`) — and policies defined on the domain are not applied to it either (Ash warns about exactly this at compile time). A resource *with* the authorizer but no policy that applies to a request is forbidden. List every resource lacking the authorizer and decide whether each is meant to be open — it changes the severity of every other finding here.
- **`authorize?: false`** passed at call sites. Each one is an intentional bypass; each needs a reason. Grep it and list every occurrence with its justification (or absence).
- **Missing `actor`.** Read each domain's `authorization do authorize ... end` first (default `:by_default`); it decides what a call without `actor:` means. Under `:when_requested`, a call passing neither `actor:` nor `authorize?:` runs with `authorize?: false` — no policy runs, so on a policy-protected resource it is an authorization bypass. Under `:by_default` it is authorized with a nil actor, so actor-referencing checks fail and the call is forbidden (fail-closed: a bug, not a bypass). `:always` forces authorization. Grep `Ash.read`, `Ash.get`, `Ash.create`, `Ash.update`, `Ash.destroy` and code-interface calls. A call has an actor if it gets one from any of: `actor:` or `scope:` on the call itself; `actor:` or `scope:` on the changeset, query or form it runs (`Ash.Changeset.for_create/for_update/for_destroy/for_action`, `Ash.Query.for_read`, `AshPhoenix.Form.for_create/for_update`), which Ash stores in the private context and reuses; or a domain with `require_actor? true`, which raises instead of running actor-less. Flag only calls with none of these, and rate each by its domain's setting.
- **`bypass` blocks** — they short-circuit all subsequent policies. An over-broad bypass (e.g. any admin bypasses everything) is a standing risk. List them.
- **Field policies** for attribute-level access; check sensitive attributes (`sensitive? true`) are both marked and policy-protected.
- **Policy tests** — policies are logic and need tests with different actors. A resource with policies and no authorization tests is a High finding.
- `forbid_if` / `authorize_if` ordering: within one policy, checks apply top to bottom and the first decisive check wins; across policies, every policy that applies to the request must pass. Read them carefully; ordering bugs are silent.

## Queries, calculations, aggregates

- Manual loading in application code where a `calculation` or `aggregate` exists (or should). Aggregates push the work to SQL; manual loading is N+1 in disguise.
- `Ash.Query.load/2` for related data rather than separate reads.
- Expensive calculations that run per record in Elixir — a module calculation's `calculate/3` does — where an `expr(...)` calculation (or a module implementing `expression/2`) could be pushed into SQL.
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
- `AshOban` (if present): audit triggers against the elixir-runtime skill's `references/ash-oban.md` (loaded in Step 3), not `otp_design.md`'s generic Oban section — uniqueness and row locks do not make a trigger safe there.

## Testing

- Tests going through actions (`Ash.create!(...)`) rather than inserting with `Repo` — a test that seeds with `Repo.insert` does not exercise validations or policies and gives false confidence.
- `Ash.can?/3` assertions for policy coverage.
- Generators/factories built on actions.
