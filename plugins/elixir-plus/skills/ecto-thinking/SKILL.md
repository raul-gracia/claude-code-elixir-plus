---
name: ecto-thinking
description: Use when the user works with Ecto, database schemas, changesets, migrations, Repo operations, preloading, query composition, contexts/bounded-contexts, Ecto.Multi, or multi-tenancy. Covers context design and cross-context patterns. Do NOT use for Ash.Resource definitions (use ash-thinking) or Phoenix LiveView (use phoenix-thinking).
---

# Ecto Thinking

Mental shifts for Ecto and data layer design. These insights challenge typical ORM patterns.

## Iron Law: NEVER Use `:float` for Money

Floats can't represent decimal cents exactly (`0.1 + 0.2 != 0.3`). Balances drift, reconciliation fails, audits find pennies that don't exist.

```elixir
# BAD — silent corruption
add :price, :float

# GOOD — exact decimal (Postgres numeric)
add :price, :decimal, precision: 19, scale: 4
# OR — integer cents, format at the edge
add :price_cents, :integer
```

Arithmetic on `:decimal` MUST use the `Decimal` module, never `+`/`*`:

```elixir
# BAD
total = price + tax            # works on floats, breaks on Decimal
# GOOD
total = Decimal.add(price, tax)
```

Never `cast` user-supplied money through a float on the way in — keep it `:decimal` (or integer cents) end to end.

## Tidewave MCP: Database at Your Fingertips

If Tidewave MCP tools are available, **use them for all database and schema work**:

| Task | Tidewave Tool |
|------|--------------|
| List all schemas in the project | `get_ecto_schemas` — discovers all modules with `__changeset__/0`, shows file paths |
| Run a query against the database | `execute_sql_query` — executes SQL through your Ecto repo (supports multiple repos, parameterized queries, 50-row limit) |
| Test a changeset or Repo operation | `project_eval` — run `Repo.all(Post)`, test changesets, verify migrations in the running app |
| Check Ecto docs for your version | `get_docs` — e.g., `get_docs("Ecto.Changeset.cast/4")` for your exact Ecto version |

**Prefer `execute_sql_query` over manual psql** — it uses your app's Ecto connection, respects your repo config, and works with any database adapter.

**Prefer `project_eval` over writing test scripts** — test `Repo.aggregate`, changeset pipelines, or `Ecto.Multi` operations directly in the running app.

**Not installed?** → `mix igniter.install tidewave` then `claude mcp add --transport http tidewave http://localhost:4000/tidewave/mcp`

## Context = Setting That Changes Meaning

Context isn't just a namespace—it changes what words mean. "Product" means different things in Checkout (SKU, name), Billing (SKU, cost), and Fulfillment (SKU, warehouse). Each bounded context may have its OWN Product schema/table.

**Think top-down:** Subdomain → Context → Entity. Not "What context does Product belong to?" but "What is a Product in this business domain?"

## Cross-Context References: IDs, Not Associations

```elixir
schema "cart_items" do
  field :product_id, :integer  # Reference by ID
  # NOT: belongs_to :product, Catalog.Product
end
```

Query through the context, not across associations. Keeps contexts independent and testable.

## DDD Patterns as Pipelines

```elixir
def create_product(params) do
  params
  |> Products.build()       # Factory: unstructured → domain
  |> Products.validate()    # Aggregate: enforce invariants
  |> Products.insert()      # Repository: persist
end
```

Use events (as data structs) to compose bounded contexts with minimal coupling.

## Schema ≠ Database Table

| Use Case | Approach |
|----------|----------|
| Database table | Standard `schema/2` |
| Form validation only | `embedded_schema/1` |
| API request/response | Embedded schema or schemaless |

## Multiple Changesets per Schema

```elixir
def registration_changeset(user, attrs)  # Full validation + password
def profile_changeset(user, attrs)       # Name, bio only
def admin_changeset(user, attrs)         # Role, verified_at
```

Different operations = different changesets.

## Multi-Tenancy: Composite Foreign Keys

```elixir
add :post_id, references(:posts, with: [org_id: :org_id], match: :full)
```

Use `prepare_query/3` for automatic scoping. Raise if `org_id` missing.

## Preload vs Join Trade-offs

| Approach | Best For |
|----------|----------|
| Separate preloads | Has-many with many records (less memory) |
| Join preloads | Belongs-to, has-one (single query) |

Join preloads can use 10x more memory for has-many.

## CRUD Contexts Are Fine

> "If you have a CRUD bounded context, go for it. No need to add complexity."

Use generators for simple cases. Add DDD patterns only when business logic demands it.

## Gotchas from Core Team

### CTE Queries Don't Inherit Schema Prefix

In multi-tenant apps, CTEs don't get the parent query's prefix.

**Fix:** Explicitly set prefix: `%{recursive_query | prefix: "tenant"}`

### Parameterized Queries ≠ Prepared Statements

- **Parameterized queries:** `WHERE id = $1` — always used by Ecto
- **Prepared statements:** Query plan cached by name — can be disabled

**pgbouncer:** Use `prepare: :unnamed` (disables prepared statements, keeps parameterized queries).

### pool_count vs pool_size

More pools with fewer connections = better for benchmarks. **But** with mixed fast/slow queries, a single larger pool gives better latency.

**Rule:** `pool_count` for uniform workloads, larger `pool_size` for real apps.

### Sandbox Mode Doesn't Work With External Processes

Cachex, separate GenServers, or anything outside the test process won't share the sandbox transaction.

**Fix:** Make the external service use the test process, or accept it's not in the same transaction.

### Null Bytes Crash Postgres

PostgreSQL rejects null bytes even though they're valid UTF-8.

**Fix:** Sanitize at boundaries: `String.replace(string, "\x00", "")`

### No Implicit Cross Joins

`from(a in A, b in B, ...)` with no `on:` or where-correlation is a Cartesian product — every row of A × every row of B.

```elixir
# BAD — accidental cross join (every a paired with every b)
from a in Author,
  b in Book,
  select: {a.name, b.title}

# GOOD — explicit, correlated join
from a in Author,
  join: b in Book, on: b.author_id == a.id,
  select: {a.name, b.title}
```

Always express joins with `join:` + `on:`. Never list a second source in the `from` and rely on a where clause to "fix" it later.

### Dedup Shared Children Before cast_assoc

When multiple parents reference the SAME child data (e.g. shared tags), passing duplicate child params inserts duplicates or trips a unique constraint.

**Fix:** dedup child params before the changeset, or persist children up front with `Repo.insert` + `on_conflict:` / `Ecto.Multi`, then associate by ID. `cast_assoc` assumes each param is a distinct row.

### preload_order for Association Sorting

```elixir
has_many :comments, Comment, preload_order: [desc: :inserted_at]
```

Note: Doesn't work for `through` associations.

### Runtime Migrations Use List API

```elixir
Ecto.Migrator.run(Repo, [{0, Migration1}, {1, Migration2}], :up, opts)
```

## Idioms

- Prefer `Repo.insert/1` over `Repo.insert!/1`—handle `{:ok, _}` / `{:error, _}` explicitly
- Use `Repo.transact/1` (Ecto 3.12+) for simple transactions instead of `Ecto.Multi`

## Red Flags - STOP and Reconsider

- belongs_to pointing to another context's schema
- Single changeset for all operations
- Preloading has-many with join
- CTEs in multi-tenant apps without explicit prefix
- Using pgbouncer without `prepare: :unnamed`
- Testing with Cachex/GenServers assuming sandbox shares transactions
- Accepting user input without null byte sanitization
- `:float` (or float arithmetic) anywhere near money
- A `from` listing two sources with no correlating `on:`/where (cross join)
- `cast_assoc` over child params that contain duplicate shared records

**Any of these? Re-read the Gotchas section.**
