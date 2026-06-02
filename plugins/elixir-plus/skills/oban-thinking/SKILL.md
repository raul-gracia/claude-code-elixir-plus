---
name: oban-thinking
description: Use when the user works with Oban job processing, background jobs, async tasks with database persistence, job queues, retries, unique jobs, or scheduling. Covers non-Pro Oban patterns. For Oban Pro (workflows, grafts, cascades, batches), see references/oban-pro.md.
---

# Oban Thinking

Paradigm shifts for Oban job processing. These insights prevent common bugs and guide proper patterns.

## Tidewave MCP: Job Queue Inspection

If Tidewave MCP tools are available, **use them to inspect and debug Oban jobs**:

| Task | Tidewave Tool |
|------|--------------|
| Query job state in the database | `execute_sql_query` — e.g., `SELECT state, worker, count(*) FROM oban_jobs GROUP BY state, worker` |
| Check Oban config at runtime | `project_eval` — run `Oban.config(Oban)` to see queues, plugins, and repo |
| Inspect a stuck/failed job | `execute_sql_query` — `SELECT * FROM oban_jobs WHERE state = 'retryable' ORDER BY attempted_at DESC LIMIT 5` |
| Test a worker's perform/1 | `project_eval` — build a job struct and call perform directly |
| Check queue health | `project_eval` — run `Oban.check_queue(queue: :default)` |
| View Oban logs | `get_logs` — grep for `Oban` to see job execution logs |
| Read Oban docs for your version | `get_docs` — e.g., `get_docs("Oban.Worker")` for your exact Oban version |

**Not installed?** → `mix igniter.install tidewave` then `claude mcp add --transport http tidewave http://localhost:4000/tidewave/mcp`

---

# Part 1: Oban (Non-Pro)

## The Iron Law: JSON Serialization

```
JOB ARGS ARE JSON. ATOMS BECOME STRINGS.
```

This single fact causes most Oban debugging headaches.

```elixir
# Creating - atom keys are fine
MyWorker.new(%{user_id: 123})

# Processing - must use string keys (JSON converted atoms to strings)
def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
  # ...
end
```

## The Iron Law: Idempotency

```
JOBS MUST BE IDEMPOTENT. OBAN RUNS A JOB AT LEAST ONCE — OFTEN MORE.
```

Retries, crashes after partial work, and at-least-once delivery all mean `perform/1` can run again. A job that charges a card, sends an email, or increments a counter with no guard will double-execute. Make the side effect safe to repeat: check-then-act inside a transaction, use unique constraints / `on_conflict`, dedupe keys, or make the operation naturally idempotent (upsert, not insert).

**This is NOT the same as `unique:`.** Uniqueness is checked at INSERT, not EXECUTION (see [Unique Jobs](#unique-jobs)) — it stops duplicate jobs being enqueued, it does NOT stop one running job from re-executing on retry.

```elixir
# Bad: re-running this job double-charges the customer
def perform(%Oban.Job{args: %{"order_id" => order_id}}) do
  order = Orders.get!(order_id)
  Payments.charge!(order.amount, order.card_token)  # runs again on every retry
  {:ok, :charged}
end

# Good: an idempotency key makes the charge safe to repeat
def perform(%Oban.Job{args: %{"order_id" => order_id}}) do
  order = Orders.get!(order_id)
  # Stripe (and most processors) dedupe on the idempotency key:
  # a repeat call with the same key returns the original charge, never a second one.
  Payments.charge!(order.amount, order.card_token, idempotency_key: "order-#{order_id}")
  {:ok, :charged}
end
```

For internal side effects, guard with a unique constraint instead: `insert ... on_conflict: :nothing` or check-then-act inside `Repo.transaction/1`.

## Error Handling: Let It Crash

**Don't catch errors in Oban jobs.** Let them bubble up to Oban for proper handling.

### Why?

1. **Automatic logging**: Oban logs the full error with stacktrace
2. **Automatic retries**: Jobs retry with exponential backoff
3. **Visibility**: Failed jobs appear in Oban Web dashboard
4. **Consistency**: Error states are tracked in the database

### Anti-Pattern

```elixir
# Bad: Swallowing errors
def perform(%Oban.Job{} = job) do
  case do_work(job.args) do
    {:ok, result} -> {:ok, result}
    {:error, reason} ->
      Logger.error("Failed: #{reason}")
      {:ok, :failed}  # Silently marks as complete!
  end
end
```

### Correct Pattern

```elixir
# Good: Let errors propagate
def perform(%Oban.Job{} = job) do
  result = do_work!(job.args)  # Raises on failure
  {:ok, result}
end

# Or return error tuple - Oban treats as failure
def perform(%Oban.Job{} = job) do
  case do_work(job.args) do
    {:ok, result} -> {:ok, result}
    {:error, reason} -> {:error, reason}  # Oban will retry
  end
end
```

### When to Catch Errors

Only catch errors when you need custom retry logic or want to mark a job as permanently failed:

```elixir
def perform(%Oban.Job{} = job) do
  case external_api_call(job.args) do
    {:ok, result} -> {:ok, result}
    {:error, :not_found} -> {:cancel, :resource_not_found}  # Don't retry
    {:error, :rate_limited} -> {:snooze, 60}  # Retry in 60 seconds
    {:error, _} -> {:error, :will_retry}  # Normal retry
  end
end
```

## Snoozing for Polling

Use `{:snooze, seconds}` for polling external state instead of manual retry logic:

```elixir
def perform(%Oban.Job{} = job) do
  if external_thing_finished?(job.args) do
    {:ok, :done}
  else
    {:snooze, 5}  # Check again in 5 seconds
  end
end
```

## Simple Job Chaining

For simple sequential chains (JobA → JobB → JobC), have each job enqueue the next:

```elixir
def perform(%Oban.Job{} = job) do
  result = do_work(job.args)
  # Enqueue next job on success
  NextWorker.new(%{data: result}) |> Oban.insert()
  {:ok, result}
end
```

**Don't reach for Oban Pro Workflows for linear chains.**

## Unique Jobs

Prevent duplicate jobs with the `unique` option:

```elixir
use Oban.Worker,
  queue: :default,
  unique: [period: 60]  # Only one job with same args per 60 seconds

# Or scope uniqueness to specific fields
unique: [period: 300, keys: [:user_id]]
```

**Gotcha:** Uniqueness is checked on insert, not execution. Two identical jobs inserted 61 seconds apart will both run.

## High Throughput: Chunking

For millions of records, **chunk work into batches** rather than one job per item:

```elixir
# Bad: One job per contact (millions of jobs = database strain)
Enum.each(contacts, &ContactWorker.new(%{id: &1.id}) |> Oban.insert())

# Good: Chunk into batches
contacts
|> Enum.chunk_every(100)
|> Enum.each(&BatchWorker.new(%{contact_ids: Enum.map(&1, fn c -> c.id end)}) |> Oban.insert())
```

Use bulk inserts without uniqueness constraints for maximum throughput.

---

> **Oban Pro patterns** (workflows, grafts, cascades, batches) are in [references/oban-pro.md](references/oban-pro.md).

---

# Red Flags - STOP and Reconsider

**Non-Pro:**
- Pattern matching on atom keys in `perform/1`
- A non-idempotent side effect (charge/email/increment) with no guard, relying on `unique:` to prevent re-execution
- Catching all errors and returning `{:ok, _}`
- Wrapping job logic in try/rescue
- Creating one job per item when processing millions of records

**Any of these? Re-read the serialization rules.**
