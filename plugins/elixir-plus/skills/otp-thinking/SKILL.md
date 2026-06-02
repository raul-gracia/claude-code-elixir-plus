---
name: otp-thinking
description: Use when the user works with GenServer, Supervisor, Task, Agent, Registry, DynamicSupervisor, ETS, persistent_term, Broadway, or asks about process design, supervision trees, fault tolerance, concurrency, process bottleneck diagnosis, scheduler tuning, choosing between Broadway vs Oban, or "let it crash". Do NOT use for deciding whether to use a process in the first place (use elixir-thinking) or for Oban job queues (use oban-thinking).
---

# OTP Thinking

Paradigm shifts for OTP design. These insights challenge typical concurrency and state management patterns.

## Tidewave MCP: Runtime Process Inspection

If Tidewave MCP tools are available, **use `project_eval` for live process debugging**:

```
# Inspect GenServer state
project_eval(":sys.get_state(MyApp.SomeServer)")

# Find top processes by memory/reductions/message_queue
project_eval(":recon.proc_count(:memory, 10)")

# Check supervision tree
project_eval("Supervisor.which_children(MyApp.Supervisor)")

# Inspect ETS tables
project_eval(":ets.info(:my_table)")
project_eval(":ets.tab2list(:my_table) |> Enum.take(5)")

# Check process info
project_eval("Process.info(Process.whereis(MyApp.Worker), [:message_queue_len, :memory, :status])")
```

**Use `get_logs`** to correlate process crashes with log output — filter by level (`:error`) or grep for specific modules.

**Not installed?** → `mix igniter.install tidewave` then `claude mcp add --transport http tidewave http://localhost:4000/tidewave/mcp`

## The Iron Law

```
GENSERVER IS A BOTTLENECK BY DESIGN
```

A GenServer processes ONE message at a time. Before creating one, ask:
1. Do I actually need serialized access?
2. Will this become a throughput bottleneck?
3. Can reads bypass the GenServer via ETS?

**The ETS pattern:** GenServer owns ETS table, writes serialize through GenServer, reads bypass it entirely with `:read_concurrency`.

**No exceptions:** Don't wrap stateless functions in GenServer. Don't create GenServer "for organization".

## GenServer Patterns

| Function | Use For |
|----------|---------|
| `call/3` | Synchronous requests expecting replies |
| `cast/2` | Fire-and-forget messages |

**When in doubt, use `call`** to ensure back-pressure. Set appropriate timeouts for `call/3`.

Use `handle_continue/2` for post-init work—keeps `init/1` fast and non-blocking.

**Deferred reply:** stash `from` and reply later via `GenServer.reply(from, result)` from `handle_info`/`handle_continue` (caller uses an `:infinity` timeout) — useful for rate limiters / async-backed calls.

```elixir
def handle_call(:work, from, state), do: {:noreply, %{state | waiting: from}}
def handle_info({:done, result}, state), do: (GenServer.reply(state.waiting, result); {:noreply, %{state | waiting: nil}})
```

## Task.Supervisor, Not Task.async

`Task.async` spawns a **linked** process—if task crashes, caller crashes too.

| Pattern | On task crash |
|---------|---------------|
| `Task.async/1` | Caller crashes (linked, unsupervised) |
| `Task.Supervisor.async/2` | Caller crashes (linked, supervised) |
| `Task.Supervisor.async_nolink/2` | Caller survives, can handle error |

**Use Task.Supervisor for:** Production code, graceful shutdown, observability, `async_nolink`.
**Use Task.async for:** Quick experiments, scripts, when crash-together is acceptable.

## Task.async_stream for Bounded Concurrency

The async_nolink table above is about crash isolation. This is a different axis: running the SAME operation across N items with a CAPPED number in flight (HTTP fan-out, per-record API calls). Use `Task.async_stream/3` with `max_concurrency:` — never spawn N raw `Task.async`, which has no backpressure and can exhaust connection pools / FDs.

```elixir
urls
|> Task.async_stream(&fetch/1, max_concurrency: 10, ordered: false, on_timeout: :kill_task)
|> Enum.reduce(%{}, fn {:ok, res}, acc -> merge(acc, res) end)
```

**Footgun:** it's lazy (a Stream) — nothing runs until an `Enum`/`Stream.run` terminal consumes it. Add `ordered: false` when order doesn't matter (avoids head-of-line blocking); set `on_timeout:` deliberately (default crashes the caller).

## DynamicSupervisor + Registry = Named Dynamic Processes

DynamicSupervisor only supports `:one_for_one` (dynamic children have no ordering). Use Registry for names—never create atoms dynamically:

```elixir
defp via_tuple(id), do: {:via, Registry, {MyApp.Registry, id}}
```

### PartitionSupervisor: When the Parent Is the Bottleneck

PartitionSupervisor runs N copies of a child (one per scheduler) and routes by key. It's about **throughput/serialization, not child count** — reach for it when a SINGLE DynamicSupervisor or named GenServer is itself the serialization point (the parent/owner, not the children).

```elixir
{PartitionSupervisor, child_spec: DynamicSupervisor, name: MyApp.Sup, partitions: System.schedulers_online()}

# Address a partition by key, not a plain name:
DynamicSupervisor.start_child({:via, PartitionSupervisor, {MyApp.Sup, key}}, spec)
```

**Footguns:** measure a real bottleneck first — premature partitioning otherwise. Routing is by key, so hot keys still serialize onto one partition.

## :pg for Distributed, Registry for Local

| Tool | Scope | Use Case |
|------|-------|----------|
| Registry | Single node | Named dynamic processes |
| :pg | Cluster-wide | Process groups, pub/sub |

`:pg` replaced deprecated `:pg2`. **Horde** provides distributed supervisor/registry with CRDTs.

## Broadway vs Oban: Different Problems

| Tool | Use For |
|------|---------|
| Broadway | External queues (SQS, Kafka, RabbitMQ) — data ingestion with batching |
| Oban | Background jobs with database persistence |

Broadway is NOT a job queue.

### Broadway Gotchas

**Processors are for runtime, not code organization.** Dispatch to modules in `handle_message`, don't add processors for different message types.

**one_for_all is for Broadway bugs, not your code.** Your `handle_message` errors are caught and result in failed messages, not supervisor restarts.

**Handle expected failures in the producer** (connection loss, rate limits). Reserve max_restarts for unexpected bugs.

## Supervision Strategies Encode Dependencies

| Strategy | Children Relationship |
|----------|----------------------|
| :one_for_one | Independent |
| :one_for_all | Interdependent (all restart) |
| :rest_for_one | Sequential dependency |

Use `:max_restarts` and `:max_seconds` to prevent restart loops.

Think about failure cascades BEFORE coding.

### Toggle Children via :ignore, Not if-Lists

To enable a process per environment, list ALL children unconditionally and let each `start_link/1` check its own config, returning `:ignore` when off:

```elixir
def start_link(opts) do
  if Application.get_env(:my_app, __MODULE__)[:enabled],
    do: GenServer.start_link(__MODULE__, opts, name: __MODULE__),
    else: :ignore
end
```

**Footgun:** the `if [child] else [] end` approach scrambles child ORDERING (which encodes restart dependencies) and is error-prone. `:ignore` keeps the tree healthy with no running process.

### Startup Side-Effects Are Tree-Level Ordering

`handle_continue` defers slow init WITHIN a process. At the TREE level: if a startup side-effect (telemetry, cache warm) is independent of siblings, run it as a `Task` child placed LAST; if siblings depend on its result, do it synchronously in an init GenServer placed FIRST. **Footgun:** child position is load-bearing — a Task placed early can signal "startup complete" before later children that actually fail.

## Abstraction Decision Tree

```
Need state?
├── No → Plain function
└── Yes → Complex behavior?
    ├── No → Agent
    └── Yes → Supervision?
        ├── No → spawn_link
        └── Yes → Request/response?
            ├── No → Task.Supervisor
            └── Yes → Explicit states?
                ├── No → GenServer
                └── Yes → GenStateMachine
```

## Storage Options

| Need | Use |
|------|-----|
| Memory cache | ETS (`:read_concurrency` for reads) |
| Static config | :persistent_term (faster than ETS) |
| Disk persistence | DETS (2GB limit) |
| Transactions/Distribution | Mnesia |

**ETS crash survival via `:heir`:** when losing a cache on owner crash is expensive to rebuild, designate a dormant heir — on owner death the table transfers (`{:"ETS-TRANSFER", tab, from, data}`) instead of being destroyed.

```elixir
:ets.new(:cache, [:protected, :named_table, {:heir, heir_pid, nil}])
```

**Footgun:** real added complexity — not every table needs an heir. Only when rebuild cost > complexity.

## :sys Debugs ANY OTP Process

```elixir
:sys.get_state(pid)        # Current state
:sys.trace(pid, true)      # Trace events (TURN OFF when done!)
```

## Telemetry Is Built Into Everything

Phoenix, Ecto, and most libraries emit telemetry events. Attach handlers:

```elixir
:telemetry.attach("my-handler", [:phoenix, :endpoint, :stop], &handle/4, nil)
```

Use `Telemetry.Metrics` + reporters (StatsD, Prometheus, LiveDashboard).

## Performance

For process bottleneck diagnosis, ETS concurrency flags, scheduler tuning, GenServer batching, persistent_term caveats, and mailbox management, see [references/performance.md](references/performance.md).

Key rules:
- Use `:recon.proc_count/2` to find top memory/CPU/mailbox consumers
- Use `+sbwt very_long` for sustained high-throughput workloads
- Use `:ets.update_counter/3` for atomic increments — but for pure integer counters, `:counters`/`:atomics` beat both ETS and a serializing GenServer (lock-free, hardware-accelerated)
- Never update `persistent_term` frequently (triggers global GC)

### Lock-Free Counters: :counters and :atomics

```elixir
ref = :counters.new(1, [:write_concurrency])
:counters.add(ref, 1, 1)
:counters.get(ref, 1)
```

Use `:atomics` (or `:counters` without `:write_concurrency`) when every read must be EXACT; use `:counters` with `:write_concurrency` for max write throughput at the cost of EVENTUALLY-CONSISTENT reads. **Footgun:** never use write_concurrency counters for balances/quotas where a read must be exact. They're fixed-size integer arrays (not KV) — pass the ref around or stash it in `persistent_term`.

## Red Flags - STOP and Reconsider

- GenServer wrapping stateless computation
- Task.async in production when you need error handling
- Creating atoms dynamically for process names
- Single GenServer becoming throughput bottleneck
- Using Broadway for background jobs (use Oban)
- Using Oban for external queue consumption (use Broadway)
- Spawning N raw `Task.async` over a collection (no backpressure → use `async_stream` with `max_concurrency:`)
- Conditional `if [child] else [] end` in a child list (scrambles ordering → return `:ignore` from `start_link/1`)
- Reaching for PartitionSupervisor without measuring the parent as a real bottleneck
- `write_concurrency` counters for balances/quotas requiring exact reads
- No supervision strategy reasoning

**Any of these? Re-read The Iron Law and use the Abstraction Decision Tree.**
