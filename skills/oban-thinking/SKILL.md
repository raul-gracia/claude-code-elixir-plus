---
name: oban-thinking
description: This skill should be used when the user asks to "add a background job", "process async", "schedule a task", "retry failed jobs", "add email sending", "run this later", "add a cron job", "unique jobs", "batch process", or mentions Oban, Oban Pro, workflows, job queues, cascades, grafting, recorded values, job args, or troubleshooting job failures.
---

# Oban Thinking

Paradigm shifts for Oban job processing. These insights prevent common bugs and guide proper patterns.

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
- Catching all errors and returning `{:ok, _}`
- Wrapping job logic in try/rescue
- Creating one job per item when processing millions of records

**Any of these? Re-read the serialization rules.**
