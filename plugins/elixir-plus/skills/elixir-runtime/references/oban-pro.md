# Part 2: Oban Pro

## Cascade Context: Erlang Term Serialization

Unlike regular job args, **cascade context preserves atoms**:

```elixir
# Creating - atom keys
Workflow.put_context(%{score_run_id: id})

# Processing - atom keys still work!
def my_cascade(%{score_run_id: id}) do
  # ...
end

# Dot notation works too
def later_step(context) do
  context.score_run_id
  context.previous_result
end
```

### Serialization Summary

| | Creating | Processing |
|-----------------|----------|--------------|
| Regular jobs | atoms ok | strings only |
| Cascade context | atoms ok | atoms ok |

## When to Use Workflows

Reserve Workflows for:
- Complex dependency graphs (not just linear chains)
- Fan-out/fan-in patterns
- When you need recorded values across steps
- Conditional branching based on runtime state

**Don't use Workflows for simple A -> B -> C chains.**

## Workflow Composition with Graft

When you need a parent workflow to wait for a sub-workflow to complete before continuing, use `add_graft` instead of `add_workflow`.

### Key Differences

| Method | Sub-workflow completes before deps run? | Output accessible? |
|--------|----------------------------------------|-------------------|
| `add_workflow` | No - just inserts jobs | No |
| `add_graft` | Yes - waits for all jobs | Yes, via recorded values |

### Pattern: Composing Independent Concerns

Don't couple unrelated concerns (e.g., notifications) to domain-specific workflows (e.g., scoring). Instead, create a higher-level orchestrator:

```elixir
# Bad: Notification logic buried in AggregateScores
defmodule AggregateScores do
  def workflow(score_run_id) do
    Workflow.new()
    |> Workflow.add(:aggregate, AggregateJob.new(...))
    |> Workflow.add(:send_notification, SendEmail.new(...), deps: :aggregate)  # Wrong place!
  end
end

# Good: Higher-level workflow composes scoring + notification
defmodule FullRunWithNotifications do
  def workflow(site_url, opts) do
    notification_opts = build_notification_opts(opts)

    Workflow.new()
    |> Workflow.put_context(%{notification_opts: notification_opts})
    |> Workflow.add_graft(:scoring, &graft_full_run/1)
    |> Workflow.add_cascade(:send_notification, &send_notification/1, deps: :scoring)
  end

  defp graft_full_run(context) do
    # Sub-workflow doesn't know about notifications
    FullRun.workflow(context.site_url, context.opts)
    |> Workflow.apply_graft()
    |> Oban.insert_all()
  end
end
```

### Recording Values for Dependent Steps

For a grafted workflow's output to be available to dependent steps, the final job must use `recorded: true`:

```elixir
defmodule FinalJob do
  use Oban.Pro.Worker, queue: :default, recorded: true

  def perform(%Oban.Job{} = job) do
    # Return value becomes available in context
    {:ok, %{score_run_id: score_run_id, composite_score: score}}
  end
end
```

## Dynamic Workflow Appending

Add jobs to a running workflow with `Workflow.append/2`:

```elixir
def perform(%Oban.Job{} = job) do
  if needs_extra_step?(job.args) do
    job
    |> Workflow.append()
    |> Workflow.add(:extra, ExtraWorker.new(%{}), deps: [:current_step])
    |> Oban.insert_all()
  end
  {:ok, :done}
end
```

**Caveat:** Cannot override context or add dependencies to already-running jobs. For complex dynamic scenarios, check external state in the job itself.

## Fan-Out/Fan-In with Batches

To run a final job after multiple paginated workflows complete, use Batch callbacks:

```elixir
# Wrap workflows in a shared batch
batch_id = "import-#{import_id}"

pages
|> Enum.each(fn page ->
  PageWorkflow.workflow(page)
  |> Batch.from_workflow(batch_id: batch_id)
  |> Oban.insert_all()
end)

# Add completion callback
Batch.new(batch_id: batch_id)
|> Batch.add_callback(:completed, CompletionWorker)
|> Oban.insert()
```

**Tip:** Include pagination workers in the batch to prevent premature completion.

## Testing Workflows

**Don't use inline testing mode** - workflows need database interaction.

```elixir
# Use run_workflow/1 for integration tests
assert %{completed: 3} =
  Workflow.new()
  |> Workflow.add(:a, WorkerA.new(%{}))
  |> Workflow.add(:b, WorkerB.new(%{}), deps: [:a])
  |> Workflow.add(:c, WorkerC.new(%{}), deps: [:b])
  |> run_workflow()
```

For testing recorded values between workers, insert predecessor jobs with pre-filled metadata.

---

# Red Flags - STOP and Reconsider

**Pro:**
- Using `add_workflow` when you need to wait for completion
- Coupling notifications/emails to domain workflows
- Not using `recorded: true` when you need output from grafted workflows
- Using Workflows for simple linear job chains
- Testing workflows with inline mode

**Any of these? Re-read the serialization rules.**
