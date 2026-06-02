---
name: elixir-thinking
description: Use when the user asks about Elixir language patterns, code structure, module design, error handling, testing strategies, performance tuning (BEAM VM, memory, GC, binaries, iodata), or mentions protocols, behaviours, pattern matching, with statements, comprehensions, structs, "coming from OOP", or deciding whether to use GenServer/processes vs plain modules/functions. Do NOT use for Phoenix/LiveView (use phoenix-thinking), Ecto/database (use ecto-thinking), OTP process implementation details (use otp-thinking), Oban (use oban-thinking), or Ash Framework (use ash-thinking).
---

# Elixir Thinking

Mental shifts required before writing Elixir. These contradict conventional OOP patterns.

## Tidewave MCP: Use It First

If Tidewave MCP tools are available, **use them before grep/file reads**:

| Instead of... | Use Tidewave |
|---------------|-------------|
| Grepping for a module/function | `get_source_location` — returns file + line for any module, function, or dependency |
| Web searching for library docs | `get_docs` — returns docs for your exact dependency versions |
| Searching hexdocs manually | `search_package_docs` — searches hexdocs filtered to your mix.lock |
| Writing a test script to try code | `project_eval` — evaluates code in your running app with full access to deps and IEx helpers |

`project_eval` is especially powerful for Elixir exploration — test pattern matching, pipe chains, protocol implementations, and module introspection (`exports/1`, `i/1`, `h/1`) without leaving the editor.

**Not installed?** → `mix igniter.install tidewave` then `claude mcp add --transport http tidewave http://localhost:4000/tidewave/mcp`

## The Iron Law

```
NO PROCESS WITHOUT A RUNTIME REASON
```

Before creating a GenServer, Agent, or any process, answer YES to at least one:
1. Do I need mutable state persisting across calls?
2. Do I need concurrent execution?
3. Do I need fault isolation?

**All three are NO?** Use plain functions. Modules organize code; processes manage runtime.

## The Three Decoupled Dimensions

OOP couples behavior, state, and mutability together. Elixir decouples them:

| OOP Dimension | Elixir Equivalent |
|---------------|-------------------|
| Behavior | Modules (functions) |
| State | Data (structs, maps) |
| Mutability | Processes (GenServer) |

Pick only what you need. "I only need data and functions" = no process needed.

## "Let It Crash" = "Let It Heal"

The misconception: Write careless code.
The truth: Supervisors START processes.

- Handle expected errors explicitly (`{:ok, _}` / `{:error, _}`)
- Let unexpected errors crash → supervisor restarts

## Control Flow

**Pattern matching first:**
- Match on function heads instead of `if/else` or `case` in bodies
- `%{}` matches ANY map—use `map_size(map) == 0` guard for empty maps
- Avoid nested `case`—refactor to single `case`, `with`, or separate functions

**Error handling:**
- Use `{:ok, result}` / `{:error, reason}` for operations that can fail
- Avoid raising exceptions for control flow
- Use `with` for chaining `{:ok, _}` / `{:error, _}` operations

**Be explicit about expected cases:**
- Avoid `_ -> nil` catch-alls—they silently swallow unexpected cases
- Avoid `value && value.field` nil-punning—obscures actual return types
- When a case has `{:ok, nil} -> nil` alongside `{:ok, value} -> value.field`, use `with` instead:

```elixir
# Verbose
case get_run(id) do
  {:ok, nil} -> nil
  {:ok, run} -> run.recommendations
end

# Prefer
with {:ok, %{recommendations: recs}} <- get_run(id), do: recs
```

## Polymorphism

| For Polymorphism Over... | Use | Contract |
|--------------------------|-----|----------|
| Modules | Behaviors | Upfront callbacks |
| Data | Protocols | Upfront implementations |
| Processes | Message passing | Implicit (send/receive) |

**Behaviors** = default for module polymorphism (very cheap at runtime)
**Protocols** = only when composing data types, especially built-ins
**Message passing** = only when stateful by design (IO, file handles)

Use the simplest abstraction: pattern matching → anonymous functions → behaviors → protocols → message passing. Each step adds complexity.

**When justified:** Library extensibility, multiple implementations, test swapping.
**When to stay coupled:** Internal module, single implementation, pattern matching handles all cases.

## Data Modeling Replaces Class Hierarchies

OOP: Complex class hierarchy + visitor pattern.
Elixir: Model as data + pattern matching + recursion.

```elixir
{:sequence, {:literal, "rain"}, {:repeat, {:alternation, "dogs", "cats"}}}

def interpret({:literal, text}, input), do: ...
def interpret({:sequence, left, right}, input), do: ...
def interpret({:repeat, pattern}, input), do: ...
```

## Defaults and Options

Use `/3` variants (`Keyword.get/3`, `Map.get/3`) instead of case statements branching on `nil`:

```elixir
# WRONG
case Keyword.get(opts, :chunker) do
  nil -> chunker()
  config -> parse_chunker_config(config)
end

# RIGHT
Keyword.get(opts, :chunker, :default) |> parse_chunker_config()
```

Don't create helper functions to merge config defaults. Inline the fallback:

```elixir
# WRONG
defp merge_defaults(opts), do: Keyword.merge([repo: Application.get_env(:app, :repo)], opts)

# RIGHT
def some_function(opts) do
  repo = opts[:repo] || Application.get_env(:app, :repo)
end
```

## Idioms

- Process dictionary is typically unidiomatic—pass state explicitly
- Reserve `is_thing` names for guards only
- Use structs over maps when shape is known: `defstruct [:name, :age]`
- Prepend to lists `[new | list]` not `list ++ [new]`
- Use `dbg/1` for debugging—prints formatted value with context
- Use built-in `JSON` module (Elixir 1.18+) instead of Jason
- `:erlang.binary_to_term/1` on untrusted input MUST pass `[:safe]` (atom-exhaustion / decode-bomb)

## Streams: Lazy vs Eager

`Enum` is **eager**—every step traverses the whole collection and builds an intermediate list. `Stream` is **lazy**—it fuses steps into one pass per element and runs only when a terminal (`Enum.*`, `Stream.run/1`) consumes it. Reach for `Stream` on large datasets or long pipelines to cut intermediate-list memory.

```elixir
1..1_000_000
|> Stream.map(&(&1 * 2))
|> Stream.filter(&(rem(&1, 3) == 0))
|> Enum.sum()   # nothing runs until this terminal
```

FOOTGUN: "Stream is always faster" is wrong. Per-element closure overhead makes it **slower on small collections**—book benchmark: ~50 elements `Enum` wins, ~500k elements `Stream` wins. Measure, don't assume.

**Infinite / unknown-length work.** For work of unknown size (paginate an API with no total, search until found), generate lazily with `Stream.iterate/2` and stop with `Enum.reduce_while/3`:

```elixir
Stream.iterate(1, &(&1 + 1))
|> Enum.reduce_while(0, fn page, acc ->
  case fetch(page) do
    [] -> {:halt, acc}
    rows -> {:cont, acc + length(rows)}
  end
end)
```

FOOTGUN: only an explicitly-halting terminal makes this safe. A plain `Enum.map` over an infinite stream never returns.

## Standard Library Data Structures

Don't reach for a list when the access pattern fights it, and don't hand-roll structures the OTP stdlib already ships.

**`:queue` for FIFO.** A list is a stack—O(1) prepend/head-pop, but FIFO (pop oldest) via `List.last`/`++` is O(n). Use Erlang `:queue` (amortized O(1) in/out):

```elixir
q = :queue.in(:a, :queue.new())
q = :queue.in(:b, q)
{{:value, :a}, q} = :queue.out(q)   # MUST rebind q
```

FOOTGUN: `:queue` is immutable—rebind the returned queue or you re-pop the same element forever. `:queue.len/1` is O(n) (walks the queue); track length yourself if you need it often.

**Sets.** Default `MapSet` (idiomatic). Need ordered output on `to_list`? Reach for an Erlang set.

| Want | Use | Dedup compares with | Notes |
|------|-----|--------------------|-------|
| Idiomatic default | `MapSet` | `===` | First choice |
| Small, ordered output | `:ordsets` | `==` | List-backed |
| Larger, ordered, log-time | `:gb_sets` | `==` | Tree-backed |
| Erlang interop | `:sets.new(version: 2)` | `===` | OTP24+; map-backed, far faster than legacy |

FOOTGUN: `:sets`/`MapSet` dedup with `===` (`42 ≠ 42.0`); `:ordsets`/`:gb_sets` use `==` (`42 == 42.0`)—type-sensitive dedup silently differs. Sets from different modules are NOT interchangeable.

**`:digraph` for DAGs / dependency resolution.** Don't hand-roll graph traversal. `:digraph` + `:digraph_utils.topsort/1` gives dependency ordering; create `[:acyclic]` (or `:digraph_utils.is_acyclic/1`) for cycle detection. Good for workflow/build/migration ordering.

```elixir
g = :digraph.new([:acyclic])
:digraph.add_vertex(g, :a)
:digraph.add_vertex(g, :b)
:digraph.add_edge(g, :a, :b)        # a before b
[:a, :b] = :digraph_utils.topsort(g)
:digraph.delete(g)                  # free the ETS table
```

FOOTGUN: `:digraph` is mutable and ETS-backed—(a) do NOT rebind, calls mutate via the reference; (b) only the owning process can mutate; (c) it is NOT garbage-collected, so `:digraph.delete/1` or you leak an ETS table.

**`:array`** is almost never worth it over maps/tuples—skip it.

## `:crypto` Is the Stdlib Security Toolbox

No dependency needed for hashing/HMAC/random: `:crypto.hash/2`, `:crypto.mac(:hmac, :sha256, key, body)` (webhook signature verification), `:crypto.strong_rand_bytes/1` (tokens).

CRITICAL FOOTGUN: never compare a MAC or secret with `==`—that's a timing attack. Use a constant-time compare.

```elixir
expected = :crypto.mac(:hmac, :sha256, secret, body)
Plug.Crypto.secure_compare(expected, sig_from_header)   # NOT ==
```

## Testing

**Prefer pattern matching over imperative assertions.** Never use `assert length` + `Enum.at`/`List.last`/`hd`. Pattern match checks length and content in one shot:

```elixir
# Bad
assert length(students) == 2
assert Enum.at(students, 0).name == "Alice"
assert Enum.at(students, 1).name == "Bob"

# Good
assert [%{name: "Alice"}, %{name: "Bob"}] = students
```

**Test behavior, not implementation.** Test use cases / public API. Refactoring shouldn't break tests.

**Test your code, not the framework.** If deleting your code doesn't fail the test, it's tautological.

**Keep tests async.** `async: false` means you've coupled to global state. Fix the coupling:

| Problem | Solution |
|---------|----------|
| `Application.put_env` | Pass config as function argument |
| Feature flags | Inject via process dictionary or context |
| ETS tables | Create per-test tables with unique names |
| External APIs | Use Mox with explicit allowances |
| File system operations | Use `@tag :tmp_dir` (see below) |

**Use `tmp_dir` for file tests.** ExUnit creates unique temp directories per test, async-safe:

```elixir
@tag :tmp_dir
test "writes file", %{tmp_dir: tmp_dir} do
  path = Path.join(tmp_dir, "test.txt")
  File.write!(path, "content")
  assert File.read!(path) == "content"
end
```

Directory is auto-cleaned before each run. Works with `@moduletag :tmp_dir` for all tests in module.

### Testing GenServers

**Don't drop to `async: false` for a named singleton.** That smell means you coupled to a global name. Make the name injectable, derive a unique one per test from the context, and start with `start_supervised!/1` (auto-terminated after the test, keeps the suite `async: true`):

```elixir
setup %{test: test} do
  name = Module.concat([Queue, test])
  pid = start_supervised!({Queue, name: name})
  %{queue: name, pid: pid}
end
```

**Unit-test callbacks directly.** `handle_call/3`, `handle_cast/2` are plain functions returning `{:reply, ...}`/`{:noreply, ...}`—call them with hand-built state, no process needed. FOOTGUN: you bypass `init/1`, so build only states actually reachable in production.

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "I need a process to organize this code" | Modules organize code. Processes are for runtime. |
| "GenServer is the Elixir way" | Plain functions are also the Elixir way. |
| "I'll need state eventually" | YAGNI. Add process when you need it. |
| "It's just a simple wrapper process" | Simple wrappers become bottlenecks. |
| "This is how I'd structure it in OOP" | Rethink from data flow. |

## Performance

For BEAM VM tuning, memory/GC, binary handling, iodata patterns, compile-time optimizations, and diagnosis tools, see [references/performance.md](references/performance.md).

Key rules for hot paths:
- Use iodata over string concatenation (`[a, b]` not `a <> b`)
- Pre-encode constants at compile time (`@json Jason.encode!(data)`)
- Avoid `Application.get_env/2` in hot paths (ETS lookup per call)
- Use `JSON` module (Elixir 1.18+) or `jsonrs` (Rust NIF) over Jason for throughput

## Red Flags - STOP and Reconsider

- Creating process without answering the three questions
- Using GenServer for stateless operations
- Wrapping a library in a process "for safety"
- One process per entity without runtime justification
- Reaching for protocols when pattern matching works
- Defaulting to `Stream` "for speed" on a small collection
- FIFO via `List.last`/`list ++ [x]` instead of `:queue`
- Using `:digraph` without a matching `:digraph.delete/1` (ETS leak), or rebinding its return value
- Comparing a MAC/secret/token with `==` instead of `secure_compare/2`
- `binary_to_term` on untrusted input without `[:safe]`
- `async: false` on a GenServer test because the name is global

**Any of these? Re-read The Iron Law.**
