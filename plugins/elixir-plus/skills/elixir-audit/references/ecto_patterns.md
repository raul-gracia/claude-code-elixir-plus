# Ecto Review

## N+1 and query shape

The dominant performance finding in Phoenix apps. Detection:

- `Repo.` inside `Enum.map/each/reduce`, inside a `for` comprehension, inside `render/2`, or inside a LiveView `render/1`
- `preload` called per-item instead of on the base query
- Association access (`post.comments`) on a struct loaded without that preload returns `%Ecto.Association.NotLoaded{}` — it does not raise. The failure surfaces later, when something tries to enumerate or JSON-encode it, or it quietly renders as nothing. Grep for association field access and check the loading query, and look for `Repo.preload(post, :comments)` inside a loop
- A function returning a list of schemas that callers then enrich one by one

Fixes: `preload` on the query, `Repo.preload(list, :assoc)` on the whole list at once, a `join` + `select` when only a few fields are needed, or `Ecto.Query.subquery` for aggregates.

Also check:
- `Repo.all` with no `limit` on anything reachable from a request
- `select:` narrowing — loading whole rows when two columns are used
- `Repo.aggregate(:count)` vs loading and `length/1`
- Queries built in the web layer rather than the context

## Indexes

Walk `priv/repo/migrations/` and the schema modules together:

- Every `belongs_to` needs an index on its FK column. Postgres does *not* create one automatically. Missing FK indexes make deletes and joins slow and cause lock escalation.
- Every `unique_constraint(:field)` in a changeset needs a matching `create unique_index(...)`. Without it the constraint silently never fires and duplicates get in.
- `unsafe_validate_unique` is a UX nicety, not a guarantee — it must be backed by the DB constraint.
- Columns used in `where` or `order_by` on hot paths.
- Polymorphic-ish columns (`*_type` + `*_id` pairs) need a composite index.
- Partial indexes for soft-delete patterns (`where: is_nil(deleted_at)`).
- Over-indexing is also a finding: indexes that duplicate a prefix of another index, or on low-cardinality columns.

## Changesets

- **Over-broad `cast`**: `cast(params, __MODULE__.__schema__(:fields))` or a list including `:role`, `:admin`, `:balance`. This is mass assignment. The cast list is the allowlist; it must be explicit and minimal per action.
- **`cast_assoc` on user params**: lets a client create or modify associated records. Usually not intended.
- **Separate changesets per action** — `registration_changeset`, `profile_changeset`, `admin_changeset`. One changeset for every path means the most permissive path wins.
- **Validation vs constraint**: `validate_required` is app-level; uniqueness and FK integrity must also exist as DB constraints with `unique_constraint`/`foreign_key_constraint` to turn the DB error into a changeset error.
- **`prepare_changes`** used for side effects — runs inside the transaction, so slow work there holds locks.

## Transactions

- Multi-step writes without `Ecto.Multi` or `Repo.transaction` — partial failure leaves inconsistent data.
- **Side effects inside a transaction**: sending email, HTTP calls, enqueueing jobs that read the not-yet-committed row. Move them after commit (or use `Oban` in the same transaction, which is the one case where enqueueing inside is correct).
- Long transactions holding locks; `Repo.transaction` wrapping a whole request.
- `Repo.transaction` return value ignored, or `{:error, failed_op, changeset, changes}` destructured without handling each failure op.
- Nested transactions — an inner `Repo.transaction`/`Repo.transact` simply runs inside the outer one (no savepoint), and an inner error or rollback aborts the whole outer transaction. Flag code that expects to recover from an inner failure and carry on.
- `Repo.insert_all`/`update_all` for bulk work instead of a loop of single writes.

## Migrations

- `references(..., on_delete: :nothing)` (the default) leaves orphans or blocks deletes. Every FK should state its intent.
- `create index(..., concurrently: true)` needs `@disable_ddl_transaction true` — without it the statement cannot run inside the migration transaction. The default migration lock is `:table_lock`, which also defeats a concurrent build; the ecto_sql-recommended fix is `migration_lock: :pg_advisory_lock` in the repo config. `@disable_migration_lock true` in the migration is the alternative, but lets several nodes run the same migration at once. Finding: `concurrently` without `@disable_ddl_transaction`, or under `:table_lock` with neither the advisory lock nor `@disable_migration_lock`.
- Adding a `NOT NULL` column with a default on a large table locks it (mitigated in PG11+, but check the PG version).
- Data backfills in the same migration as the schema change — they run in one transaction and cannot be retried independently. Separate them.
- Missing `down`/`change` reversibility on anything that might need rollback.
- Migrations referencing schema modules (`MyApp.User`) — the module will drift from the migration's point in history. Use raw queries or `execute`.
- Migration history from source, not from a database: read `priv/repo/migrations/` (and `apps/*/priv/repo/migrations/` in an umbrella) for out-of-order or duplicate timestamps, migrations edited after they clearly shipped, and renamed or deleted files a deployed database may still record.

## Schemas

- Business logic on the schema module rather than in the context. A schema should define fields, associations, and changesets.
- `@derive {Jason.Encoder, ...}` exposing fields to JSON by default — an easy accidental leak when a field is added later.
- `Ecto.Enum` used for fixed value sets rather than raw strings.
- `:utc_datetime` vs `:naive_datetime` chosen consistently; `:utc_datetime_usec` where precision matters.
- Decimal for money, never float. Grep `:float` in migrations for anything money-shaped — this is a Critical finding if found.
- Soft deletes implemented ad hoc (a `deleted_at` that half the queries forget to filter). Check every query on that schema.

## Repo configuration

- `pool_size` vs the actual concurrency of the app and the DB's `max_connections`.
- `queue_target` / `queue_interval` — defaults cause cascading timeouts under load.
- `timeout` (default 15s) on queries that legitimately take longer.
- Read replicas configured but queries not routed.
- `telemetry` handlers for slow-query logging present.
