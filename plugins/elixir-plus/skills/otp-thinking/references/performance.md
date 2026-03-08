# OTP Performance

## Table of Contents
- [Process Bottleneck Diagnosis](#process-bottleneck-diagnosis)
- [ETS Deep Dive](#ets-deep-dive)
- [Scheduler Tuning](#scheduler-tuning)
- [GenServer Performance Patterns](#genserver-performance-patterns)
- [persistent_term Caveats](#persistent_term-caveats)
- [Process Mailbox Management](#process-mailbox-management)

## Process Bottleneck Diagnosis

### Detecting Overloaded Processes

```elixir
# Message queue growing = process can't keep up
Process.info(pid, :message_queue_len)

# Top consumers in production (recon)
:recon.proc_count(:message_queue_len, 10)  # Top 10 by mailbox
:recon.proc_count(:memory, 10)             # Top 10 by memory
:recon.proc_count(:reductions, 10)         # Top 10 by CPU (snapshot)
:recon.proc_window(:reductions, 10, 1000)  # Top 10 by CPU over 1s
```

### The GenServer Bottleneck Pattern

A GenServer processes ONE message at a time. At high throughput:

```
Clients → [msg1, msg2, msg3, ...msgN] → GenServer (processes one at a time)
                  ↑ mailbox grows
```

**Solutions by increasing effectiveness:**

1. **ETS bypass for reads** — GenServer owns ETS table, writes serialize through it, reads bypass entirely
2. **Sharding** — Multiple GenServers behind Registry, hash key to determine which handles request
3. **PartitionSupervisor** — Built-in sharding for DynamicSupervisor children
4. **Demand-based processing** — Process messages in batches from the mailbox

### :sys for Live Debugging

```elixir
:sys.get_state(pid)         # Current state (GenServer, no message processing)
:sys.get_status(pid)        # Full status with metadata
:sys.trace(pid, true)       # Trace ALL messages (TURN OFF IMMEDIATELY after use)
:sys.statistics(pid, true)  # Start collecting stats
:sys.statistics(pid, :get)  # Read stats
```

## ETS Deep Dive

### Concurrency Flags

| Flag | Effect | Best For |
|------|--------|----------|
| `:read_concurrency` | Optimizes for concurrent reads (adds read locks) | Read-heavy caches, lookup tables |
| `:write_concurrency` | Shards lock granularity for writes | Write-heavy counters, metrics |
| `{:write_concurrency, :auto}` | Auto-tune write sharding (OTP 25+) | Mixed workloads |
| `:decentralized_counters` | Per-scheduler counters for `update_counter` (OTP 23+) | High-throughput atomic counters |
| `:compressed` | Compress stored terms | Memory-sensitive, CPU trade-off |

**Trade-offs:**
- `:read_concurrency` adds overhead to writes — don't use on write-heavy tables
- `:write_concurrency` adds overhead to reads — don't use on read-heavy tables
- Both together: use `{:write_concurrency, :auto}` instead

### Table Types

| Type | Lookup | Ordering | Best For |
|------|--------|----------|----------|
| `:set` | O(1) hash | None | Key-value cache, fast lookups |
| `:ordered_set` | O(log n) tree | Sorted by key | Range queries, iteration in order |
| `:bag` | O(1) hash | None | Multiple values per key |
| `:duplicate_bag` | O(1) hash | None | Duplicate key-value pairs |

### Atomic Operations (No GenServer Needed)

```elixir
# Atomic increment — no serialization bottleneck
:ets.update_counter(:my_table, :page_views, {2, 1})

# Conditional update (compare-and-swap pattern)
:ets.update_counter(:my_table, :stock, {2, -1, 0, 0})  # Decrement, min 0

# Atomic insert-if-absent
:ets.insert_new(:my_table, {key, value})
```

### Write-Behind Cache Pattern

```elixir
# Fast writes to ETS, periodic flush to database
def handle_info(:flush, state) do
  entries = :ets.tab2list(@table)
  Repo.insert_all(MySchema, entries)
  :ets.delete_all_objects(@table)
  schedule_flush()
  {:noreply, state}
end
```

### Monitoring

```elixir
:ets.info(:my_table, :size)      # Row count
:ets.info(:my_table, :memory)    # Memory in words (multiply by :erlang.system_info(:wordsize))
```

## Scheduler Tuning

### Key Flags

| Flag | Purpose | Default |
|------|---------|---------|
| `+S N:N` | Online:available schedulers | Auto-detected from CPUs |
| `+sbt db` | Bind schedulers to CPUs | No binding |
| `+stbt ts` | Bind type: thread spread | Reduces NUMA bouncing |
| `+sbwt very_long` | Busy-wait threshold | `short` |
| `+swt very_low` | Wakeup threshold | `medium` |
| `+SDcpu N` | Dirty CPU scheduler count | Number of CPUs |
| `+SDio N` | Dirty I/O scheduler count | 10 |

### Detecting Scheduler Imbalance

```elixir
# Per-scheduler utilization over 1 second
:scheduler.utilization(1)

# Returns list like:
# [{:normal, 1, 0.85, _}, {:normal, 2, 0.12, _}, ...]
# Imbalanced = some schedulers at 90%+ while others idle
```

Fix imbalance with `+stbt ts` (thread spread binding) or `+sbt db` (default binding).

### Reductions

Each process gets ~4000 reductions per scheduler timeslice. A reduction ≈ one function call. Processes that consume reductions quickly get preempted, ensuring fairness.

Long-running NIFs that don't yield break this fairness — use dirty schedulers.

## GenServer Performance Patterns

### handle_continue for Non-Blocking Init

```elixir
def init(args) do
  {:ok, %{}, {:continue, :load_data}}
end

def handle_continue(:load_data, state) do
  # Heavy work here — doesn't block supervisor startup
  {:noreply, %{state | data: load_expensive_data()}}
end
```

### Batching Messages

Process multiple messages in one pass:

```elixir
def handle_cast({:event, data}, state) do
  # Drain additional messages from mailbox
  events = drain_events([data])
  # Process batch
  {:noreply, process_batch(events, state)}
end

defp drain_events(acc) do
  receive do
    {:"$gen_cast", {:event, data}} -> drain_events([data | acc])
  after
    0 -> Enum.reverse(acc)
  end
end
```

### Process Pooling

For CPU-bound work, pool workers instead of creating a single GenServer:

```elixir
# Using NimblePool
NimblePool.checkout!(MyPool, :checkout, fn _from, worker ->
  {result, worker} = do_work(worker)
  {:ok, result, worker}
end)
```

Or shard with Registry:

```elixir
# N GenServers behind Registry, hash key to pick one
shard = :erlang.phash2(key, @shard_count)
GenServer.call({:via, Registry, {MyRegistry, shard}}, {:get, key})
```

## persistent_term Caveats

`persistent_term` is faster than ETS for reads (no copying, direct reference) but:

**Updates trigger a global GC scan across ALL processes.** Every process must be scanned to check for references to the old value.

| Operation | Cost |
|-----------|------|
| Read | ~0 (direct pointer, no copy) |
| Write/Update | O(N) where N = total process count |
| Delete | O(N) same as update |

**Rules:**
- Use for truly static config (loaded once at boot, never changes)
- Never use for frequently changing data
- Never use in hot loops that update values
- Measure with `:persistent_term.info()` to check memory

```elixir
# Good: app config loaded once
:persistent_term.put(:app_config, %{feature_flags: flags})

# Bad: updating a counter
:persistent_term.put(:request_count, count + 1)  # Triggers global GC!
```

## Process Mailbox Management

### Selective Receive Performance

BEAM scans the mailbox linearly for pattern matches. Large mailboxes with selective receives = O(N) per receive.

```elixir
# Bad: selective receive on large mailbox
receive do
  {:response, ^ref, data} -> data  # Scans entire mailbox for matching ref
end

# Good: use Process.monitor + receive ref (optimized by compiler)
ref = Process.monitor(pid)
receive do
  {:DOWN, ^ref, _, _, _} -> :ok  # Compiler optimizes ref-based receives
end
```

### Off-Heap Messages

```elixir
Process.flag(:message_queue_data, :off_heap)
```

Messages stored outside process heap. GC doesn't scan them. Use for:
- Processes that receive bursts of messages
- Processes with large heaps where GC is expensive
- Processes where message processing is slower than arrival rate

### Detecting Flooded Mailboxes

```elixir
# In production monitoring
for {pid, len} <- :recon.proc_count(:message_queue_len, 5) do
  info = Process.info(pid, [:registered_name, :current_function])
  Logger.warning("Flooded: #{inspect(info)} queue=#{len}")
end
```
