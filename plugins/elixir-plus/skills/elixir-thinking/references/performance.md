# Elixir Performance

## Table of Contents
- [BEAM VM Tuning](#beam-vm-tuning)
- [Memory and GC](#memory-and-gc)
- [Binary Handling and Iodata](#binary-handling-and-iodata)
- [Compile-Time Optimizations](#compile-time-optimizations)
- [Enum vs Stream vs Flow](#enum-vs-stream-vs-flow)
- [NIFs and Dirty Schedulers](#nifs-and-dirty-schedulers)
- [Diagnosis Tools](#diagnosis-tools)

## BEAM VM Tuning

Critical `vm.args` flags for production:

| Flag | Effect | When to Use |
|------|--------|-------------|
| `+S N:N` | Set scheduler count | Match to CPU cores, or pin for benchmarking |
| `+sbwt very_long` | Keep schedulers spinning (busy-wait) | Sustained high-throughput (trades CPU idle for latency) |
| `+sbwtdcpu very_long` | Same for dirty CPU schedulers | Heavy NIF or dirty workloads |
| `+swt very_low` | Faster scheduler wakeup threshold | Low-latency response to new work |
| `+stbt ts` | Bind schedulers to CPU topology | Multi-socket/NUMA machines (reduces cache-line bouncing) |
| `+K true` | Enable kernel polling (epoll/kqueue) | Always in production |
| `+A 64` | Async thread pool for file I/O | Heavy file I/O workloads |
| `+SDio 64` | Dirty I/O scheduler count | Heavy external I/O (network, files) |
| `+hms 32768` | Min heap size per process (32KB) | Short-lived handler processes (reduces GC churn) |
| `+Muacnl 0` | Disable carrier migration | Reduces allocator lock contention across cores |

**Example production launch:**

```bash
elixir --erl "+sbwt very_long +sbwtdcpu very_long +swt very_low +S 10:10 +K true +A 64" \
  -S mix phx.server
```

Or in `rel/vm.args.eex`:

```
+sbwt very_long
+sbwtdcpu very_long
+swt very_low
+K true
+A 64
+SDio 64
+hms 32768
```

**`+sbwt very_long` alone** enables microsecond-scale wakeup latency — critical for 1M+ RPS. Trade-off: higher CPU usage at idle.

## Memory and GC

### Per-Process Heaps

Each BEAM process has its own heap and GC. **No stop-the-world pauses.** This is the single biggest performance advantage over most runtimes.

### Tuning GC Per Process

```elixir
# Increase min heap for processes that accumulate data
Process.spawn(fn -> ... end, [min_heap_size: 32_768])

# Or in GenServer
def init(state) do
  Process.flag(:min_heap_size, 32_768)
  {:ok, state}
end
```

`fullsweep_after` controls how many minor GCs before a full sweep. Lower = more aggressive memory reclaim, higher = less GC overhead:

```elixir
# Default is 65535. For memory-sensitive processes:
Process.flag(:fullsweep_after, 10)
```

### Off-Heap Messages

For processes with large mailboxes:

```elixir
Process.flag(:message_queue_data, :off_heap)
```

Stores messages outside the process heap — GC doesn't scan them. Use for processes that receive many messages but process them slowly.

## Binary Handling and Iodata

### Reference-Counted vs Heap Binaries

| Size | Type | Location | Implication |
|------|------|----------|-------------|
| <= 64 bytes | Heap binary | Process heap | Copied on send, GC'd with process |
| > 64 bytes | Refc binary | Shared heap | Reference counted, can leak |

**Sub-binary trap:** A small sub-binary holds a reference to its large parent. The parent won't be GC'd until all sub-binaries are gone.

```elixir
# Forces a copy, releasing the parent reference
small_piece = :binary.copy(small_piece)
```

### Iodata Over Concatenation

**Never concatenate strings in hot paths.** Use iodata (nested lists of binaries):

```elixir
# Bad: forces allocation and copying at each <>
response = "{\"id\":" <> id <> ",\"name\":\"" <> name <> "\"}"

# Good: zero-copy, Bandit/Cowboy writes via writev() syscall
response = [~S({"id":), id, ~S(,"name":"), name, ~S("})]
```

Iodata avoids intermediate binary allocations entirely. The HTTP server writes the nested list directly to the socket.

### JSON Encoding

**Tier 1 — Iodata construction (fastest):**
Build JSON as iodata manually. No encoder runs. 112% faster than map→JSON.

**Tier 2 — Rust NIF encoder:**
`jsonrs` (Rust/serde_json) is 5-10x faster than Jason with 3-30x less memory.

**Tier 3 — Built-in JSON module:**
Elixir 1.18+ `JSON` module is ~1.5-2x faster than Jason.

**Tier 4 — Jason:**
Fine for most apps. Use compile-time encoding for constants:

```elixir
@metadata_json Jason.encode!(%{version: "1.0"})  # Encoded ONCE at compile time
```

### Custom JSON Escape (Hot Path)

Default `String.replace/3` chains traverse the string multiple times. Single-pass escape:

```elixir
defp json_escape(str) when is_binary(str), do: json_escape_bin(str, <<>>)

for {char, escaped} <- [{?\\, ~S(\\)}, {?", ~S(\")}, {?\n, ~S(\n)}, {?\r, ~S(\r)}, {?\t, ~S(\t)}] do
  defp json_escape_bin(<<unquote(char), rest::binary>>, acc),
    do: json_escape_bin(rest, <<acc::binary, unquote(escaped)>>)
end

defp json_escape_bin(<<c, rest::binary>>, acc),
  do: json_escape_bin(rest, <<acc::binary, c>>)
defp json_escape_bin(<<>>, acc), do: acc
```

## Compile-Time Optimizations

### Pre-compute Constants

```elixir
# Pre-build lists at compile time
@foo_keys Enum.map(1..10, &"foo#{&1}")

# Pre-encode JSON fragments
@status_success ~S(,"status":"success"})
@status_pending ~S(,"status":"pending"})

# Pre-encode metadata
@metadata_json Jason.encode!(%{version: "1.0", features: ["a", "b"]})
```

### Inline Hot Functions

```elixir
@compile {:inline, my_hot_function: 1}
```

Eliminates function call overhead. Use sparingly on measured hot paths only.

### Avoid Runtime Config in Hot Paths

`Application.get_env/2` does an ETS lookup on every call. Cache at compile time or in process state:

```elixir
# Bad: ETS lookup per request
def handle(conn), do: json(conn, %{key: Application.get_env(:app, :key)})

# Good: compile-time
@key Application.compile_env!(:app, :key)
def handle(conn), do: send_resp(conn, 200, @key)
```

## Enum vs Stream vs Flow

| Tool | Best For | Overhead |
|------|----------|----------|
| `Enum` | Small-medium collections, all fit in memory | Intermediate lists |
| `Stream` | Large/infinite collections, memory-sensitive | Function call overhead per element |
| `Flow` | CPU-bound parallel work on large collections | Process spawn + message passing |

**Rule:** Use `Enum` by default. Switch to `Stream` when you're chaining operations on 10K+ element collections and memory matters. Use `Flow` only for CPU-bound parallel work.

## NIFs and Dirty Schedulers

NIFs block the scheduler they run on. Long-running NIFs starve other processes.

| Scheduler Type | Flag | Use For |
|----------------|------|---------|
| Normal | (default) | Must complete in <1ms |
| Dirty CPU | `ERL_NIF_DIRTY_JOB_CPU_BOUND` | CPU-bound >1ms |
| Dirty I/O | `ERL_NIF_DIRTY_JOB_IO_BOUND` | I/O-bound (network, disk) |

Tune dirty scheduler counts with `+SDcpu N` and `+SDio N`.

**Rustler** is the safe NIF alternative — memory-safe, panic-safe, no risk of crashing the VM.

## Diagnosis Tools

### Built-in

```elixir
Process.info(pid, :message_queue_len)   # Detect overloaded processes
Process.info(pid, :memory)              # Per-process memory
Process.info(pid, :reductions)          # CPU proxy (work done)
:erlang.system_info(:process_count)     # Total process count
:scheduler.utilization(1)               # Scheduler load over 1 second
:erlang.memory()                        # System-wide memory breakdown
```

### Recon (production-safe)

```elixir
:recon.proc_count(:memory, 10)          # Top 10 processes by memory
:recon.proc_count(:message_queue_len, 10) # Top 10 by mailbox size
:recon.proc_window(:reductions, 10, 1000) # Top 10 by CPU over 1s window
:recon.bin_leak(10)                     # Processes leaking binaries
:recon.scheduler_usage(1000)            # Per-scheduler utilization
```

### Observer

```elixir
:observer.start()       # GUI (dev only)
# observer_cli for production terminals
```

### Benchee

```elixir
Benchee.run(%{
  "option_a" => fn -> ... end,
  "option_b" => fn -> ... end
}, memory_time: 2)
```

Always benchmark with `memory_time` to catch allocation differences.
