# Elixir Anti-Patterns

The four families documented in the official Elixir guides (`Anti-patterns` section of the Elixir docs, added in 1.16), with detection notes and severity guidance for the audit.

---

## Code-related anti-patterns

### Comments overuse
Comments restating what the code says, instead of naming things well or writing `@doc`/`@spec`.
**Detect**: comment-to-code ratio in a module; comments immediately above self-evident lines.
**Fix**: rename functions/variables; move the "why" into `@doc`, delete the "what".
**Severity**: Low

### Complex `else` clauses in `with`
A `with` whose `else` block has many clauses, each handling an error from a different step, so you cannot tell which step produced which error.
**Detect**: `with` blocks with an `else` of 3+ clauses, or `else` clauses matching bare `{:error, _}`.
**Fix**: normalize each step's error inline (wrap it so the source is identifiable), or split the `with` into private functions.
**Severity**: Medium — directly causes misattributed errors in production.

### Complex extractions in clauses
Function heads that both pattern-match many fields and bind them, where only some are used in the head's guard.
**Detect**: heads destructuring 4+ fields.
**Fix**: match only what the clause selection needs; extract the rest in the body.
**Severity**: Low

### Dynamic atom creation
`String.to_atom/1` (or `binary_to_atom`) on values derived from user input, HTTP params, external APIs, or file contents. Atoms are never garbage-collected; the table has a hard limit (default ~1M) and exhausting it crashes the VM.
**Detect**: grep `String.to_atom`, `List.to_atom`, `:erlang.binary_to_atom`, and `keys: :atoms` passed to `Jason.decode`/`decode!` (atomizes every key; `keys: :atoms!` does not create atoms), and trace every argument to its source.
**Fix**: `String.to_existing_atom/1` inside a `rescue ArgumentError`, or keep the value as a string, or match against an explicit allowlist.
**Severity**: **Critical** when reachable from user input — it is a remote denial of service.

### Long parameter list
Functions taking many positional arguments, especially several of the same type.
**Detect**: arity 5+, or 3+ consecutive params of the same primitive type.
**Fix**: group related params into a map or struct; if the group recurs, it is a missing domain type.
**Severity**: Medium

### Namespace trespassing
Defining modules under a namespace owned by another library or the standard library (`defmodule Ecto.MyThing`).
**Detect**: module names whose first segment is not the app's own namespace.
**Fix**: nest under the application namespace.
**Severity**: Medium

### Non-assertive map access
Using `map[:key]` (Access) where the key is expected to always exist. Access returns `nil` on a missing key, so the failure surfaces far from the bug.
**Detect**: `[:atom_key]` access on structs/maps that the code then assumes is non-nil.
**Fix**: `map.key` for guaranteed keys — it raises at the point of the bug. Reserve `map[:key]` for genuinely optional keys.
**Severity**: Medium — this is the single most common source of "nil crept in three layers down".

### Non-assertive pattern matching
Writing code that silently tolerates unexpected shapes: `case` with a catch-all `_ ->` that guesses, or `{:ok, x} = ...` avoided in favour of defensive branches.
**Detect**: `_ ->` clauses that return a default rather than raising, on internal (non-boundary) functions.
**Fix**: match the shapes you actually expect and let anything else crash. Be permissive at the system boundary, assertive inside it.
**Severity**: Medium

### Non-assertive truthiness
`&&`, `||`, `!` on values that are known booleans, hiding the difference between `false` and `nil`.
**Detect**: boolean operators applied to results of functions returning `boolean()`.
**Fix**: `and`, `or`, `not`.
**Severity**: Low

### Structs with 32 fields or more
At 32 fields or more the VM stops storing a struct as a flat map and switches to a hash map, which costs memory and sharing across instances.
**Detect**: `defstruct` (or `embedded_schema`/`schema`) with 32+ fields.
**Fix**: nest optional or related fields into a sub-struct or metadata map; weigh against API ergonomics.
**Severity**: Low, Medium for structs held in large numbers in memory.

---

## Design-related anti-patterns

### Alternative return types
A function whose return type changes based on an option (`format: :map` returning a map, otherwise a list).
**Detect**: functions branching on an opt to decide the *shape* of the return.
**Fix**: separate functions with distinct names.
**Severity**: Medium

### Boolean obsession
Multiple booleans encoding a state machine (`is_admin`, `is_active`, `is_suspended`) where the combinations are not all legal.
**Detect**: 2+ related boolean fields on a struct or schema.
**Fix**: one atom field with the legal states.
**Severity**: Medium — illegal states become representable and eventually get written.

### Exceptions for control flow
Using `raise`/`rescue`, or `!`-functions, for outcomes that are expected (record not found, validation failure).
**Detect**: `rescue` blocks around `Repo.get!`, `String.to_integer`, JSON decode.
**Fix**: tagged tuples (`{:ok, _} | {:error, _}`) for expected outcomes; reserve raising for programmer error.
**Severity**: Medium

### Primitive obsession
Domain concepts carried as bare strings/maps (`%{"card_number" => ...}`) rather than structs with validation.
**Detect**: the same map key set threaded through many functions.
**Fix**: define a struct; validate at construction.
**Severity**: Medium

### Unrelated multi-clause function
Multiple clauses of one function doing unrelated work, grouped only because they share a name.
**Detect**: clauses whose bodies share no logic and whose heads match different domains.
**Fix**: split into separately named functions.
**Severity**: Low

### Using application configuration for library parameters
A library reading `Application.get_env` for values that belong to the caller, making the value global and untestable per-caller.
**Detect**: `Application.get_env` in a module intended for reuse.
**Fix**: pass the value as an argument or option.
**Severity**: Medium — also flag `Application.compile_env` used for anything that must vary at runtime; that belongs in `config/runtime.exs`.

---

## Process-related anti-patterns

### Code organization by process
Using processes (GenServer/Agent) purely to organize code, when a plain module with functions would do. Processes are for concurrency, state that must outlive a call, isolation, or interfacing with the outside world — not for namespacing.
**Detect**: a GenServer whose state is derivable, or whose every call is a pure transformation.
**Fix**: plain module; pass state as an argument.
**Severity**: High — it converts a trivially concurrent operation into a serialization point.

### Scattered process interfaces
Callers reaching a process via raw `GenServer.call(pid, {:some, :tuple})` from several modules, with no public API on the owning module.
**Detect**: `GenServer.call`/`cast`/`send` to a module from outside that module.
**Fix**: public functions on the owning module wrapping every message.
**Severity**: Medium

### Sending unnecessary data
Passing large structures into a spawned process or message when only a field is needed — the data is copied per message.
**Detect**: closures capturing a big struct in `Task.async`; messages carrying full records.
**Fix**: extract the needed fields before sending.
**Severity**: Medium, High on hot paths.

### Unsupervised processes
`spawn`, `spawn_link`, `Task.start`, or a GenServer started outside a supervision tree. These die silently, leak, and do not restart.
**Detect**: grep `spawn(`, `spawn_link(`, `Task.start(`, `GenServer.start_link` not called from a supervisor child spec.
**Fix**: `Task.Supervisor.start_child/2`, `DynamicSupervisor`, or a proper child spec.
**Severity**: High

---

## Meta-programming anti-patterns

### Compile-time dependencies
`use`, module attributes referencing other modules, or macros that create compile-time edges, so touching one module recompiles a large fraction of the app.
**Detect**: `mix xref graph --label compile-connected --format stats`; any module with a large compile-connected count.
**Fix**: move to runtime dispatch (behaviours, function calls) where possible; avoid `alias`/struct expansion at compile time in widely-used modules.
**Severity**: Medium — shows up as developer pain, not production pain, but compounds.

### Large code generation
Macros generating many functions or large bodies, inflating compile time and making stack traces unreadable.
**Detect**: `quote` blocks over ~20 lines; `for` loops around `def` inside a macro.
**Fix**: generate a thin delegating function that calls a normal function with the parameters.
**Severity**: Medium

### Unnecessary macros
A macro where a function would work — i.e. the macro does not need to manipulate the AST or defer evaluation.
**Detect**: `defmacro` whose body only interpolates its arguments into a call.
**Fix**: make it a function.
**Severity**: Medium

### `use` instead of `import`
A library or internal module offering `use` (a `__using__/1` that injects code) where `import` or `alias` would do, so a reader cannot see what the call site gains without reading the macro.
**Detect**: `defmacro __using__` whose `quote` only contains `import`/`alias`/`require`.
**Fix**: have callers `import`/`alias` directly; if `use` is needed, document what it injects in the moduledoc.
**Severity**: Low

### Untracked compile-time dependencies
Module names built at compile time with `Module.concat/1,2` or literal atoms (`:"Elixir.MyApp.Foo"`), which the compiler cannot track, so dependents are not recompiled when the target changes.
**Detect**: `Module.concat` or `:"Elixir.` in module bodies, module attributes, or macros.
**Fix**: reference modules by their full alias; when names must be generated, generate them inside `quote`/`unquote` so the dependency is visible.
**Severity**: Medium — stale builds that only a clean compile fixes.
