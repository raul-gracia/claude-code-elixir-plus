# OTP & Process Design Review

What to check when reviewing the concurrency design of an Elixir application. Most production incidents in Elixir systems trace back to this file's contents rather than to business logic.

## Supervision tree

Read `lib/my_app/application.ex` first. It is the architecture diagram.

- **Child order matters** — children start in order and shut down in reverse. A child that depends on another must start after it. Flag a Repo listed after something that queries on boot.
- **Restart strategy vs. dependency shape**:
  - `:one_for_one` — children are independent. Wrong if child B holds a reference (pid, ETS table) owned by child A.
  - `:rest_for_one` — later children depend on earlier ones. Usually the right answer for a pipeline.
  - `:one_for_all` — all-or-nothing. Correct for tightly coupled groups; a sign of trouble if the group is large.
- **`max_restarts` / `max_seconds`** — defaults (3 in 5s) let a crash loop take down the whole node. Deliberate or accidental?
- **Depth** — a flat tree with 20 children under `Application` means the failure domains have not been thought about. Group related processes under their own supervisor.
- **`restart: :temporary` / `:transient`** — correct for one-shot work, wrong for anything that must be running.

## GenServer review

For each GenServer, answer these:

1. **Is there exactly one of it, and does every request touch it?** That is a global serialization point. Throughput is capped at one message at a time regardless of how many cores or nodes you have.
2. **What is in `handle_call`?** Any DB query, HTTP call, file IO, or heavy computation blocks every other caller. Move it to the calling process (a plain function), or use a pool (`:poolboy`, `NimblePool`, or `Task.Supervisor.async_stream`).
3. **Does `init/1` block?** Work in `init/1` blocks the supervisor's start, and a slow `init` stalls boot. Use `{:ok, state, {:continue, :setup}}` and `handle_continue/2`.
4. **Call timeouts.** `GenServer.call/2` defaults to 5000ms and *exits* the caller on timeout. Any handler that can exceed 5s needs an explicit timeout and a caller that handles the exit — or should be a `cast` plus a reply message.
5. **`cast` used where delivery matters?** `cast` is fire-and-forget with no backpressure. A fast producer casting to a slow consumer grows the mailbox until the node runs out of memory.
6. **Mailbox growth.** Any process receiving from an unbounded source needs backpressure: `call` instead of `cast`, GenStage/Broadway, or an explicit queue with a drop policy.
7. **State size.** Large state means large copies on some operations and long GC pauses. Big shared read-heavy data belongs in ETS or `:persistent_term`, not a GenServer.
8. **`handle_info` catch-all.** A bare `handle_info(_, state)` clause hides bugs (unexpected messages, late replies from timed-out calls). Log them at minimum.
9. **`terminate/2` assumed to run.** It does not run on `:brutal_kill`, on some crashes, or when the VM dies. Never put required cleanup there alone.

## Alternatives that are usually better than a GenServer

- **ETS** — shared read-heavy state, concurrent reads (`read_concurrency: true`). Watch for: `:public` tables written by many processes (race conditions), tables owned by an unsupervised process (data vanishes on crash), unbounded growth with no eviction.
- **`:persistent_term`** — near-zero-cost reads for data that changes almost never. Writing triggers a global GC; never write per-request.
- **Registry** — process lookup by key, replacing a GenServer-as-directory.
- **`Task.async_stream`** — bounded parallel work with `max_concurrency`, instead of spawning per item.
- **DynamicSupervisor** — per-entity processes started on demand.

## Task and spawn

- `Task.async/1` + `Task.await/2` is fine when awaited in the same function — the link makes failures propagate.
- `Task.start/1` and `spawn/1` are unsupervised: the process is invisible, failures are silent, and shutdown does not wait for it. Flag every occurrence.
- `Task.Supervisor.async_nolink/2` is the right tool for work whose failure should not take the caller down.
- `Task.async_stream/3` without `max_concurrency` defaults to `System.schedulers_online()` — usually fine, but check `timeout` (default 5s) and `on_timeout: :kill_task` vs the default `:exit`.
- Tasks spawned per web request that outlive the request are a leak.

## Distribution & scaling

- **Named processes** (`name: __MODULE__`) are per-node. On multiple nodes you get one per node, which is either what you want or a silent correctness bug.
- **Global singletons** (`:global`, `Horde`, `swarm`) need a story for netsplits. Ask what happens during one.
- **Node-local ETS/state** breaks the moment a second instance is deployed. Check whether the app is deployed as one node today and whether anything assumes it.

## Oban (if present)

- **Idempotency** — jobs retry. Any job performing a non-idempotent side effect (charging a card, sending an email) needs a guard.
- **`unique`** — prevents duplicate enqueues; check it is set where duplicates are harmful, and that the `period` matches reality.
- **`max_attempts`** — default 20. For a job that will never succeed on retry (bad input), that is 20 wasted runs; return `{:cancel, reason}`.
- **Long jobs** — a job running for minutes occupies a queue slot. Check queue concurrency against job duration.
- **Queue isolation** — slow jobs and latency-sensitive jobs in the same queue means the latter waits.
- **Testing** — `Oban.Testing` in `:manual` mode; flag jobs with no test.
- **Shutdown** — `:shutdown_grace_period` vs job duration; jobs killed mid-flight must be safe to retry.

## Broadway / GenStage (if present)

- Demand and `max_demand` tuned, or left at defaults against a very different workload
- Batching configured where the sink benefits from it
- Failure handling: `handle_failed/2` present, or failures silently dropped
