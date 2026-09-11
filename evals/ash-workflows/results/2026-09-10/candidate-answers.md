# Candidate skill forward evaluation answers

Model identity exposed by the session: Codex, based on GPT-6. The exact deployed model snapshot is not exposed to me.

These are reasoning evaluations, not application execution tests. I read only the supplied candidate [skill](candidate/elixir-runtime/SKILL.md), its [AshOban reference](candidate/elixir-runtime/references/ash-oban.md), its [Oban Pro reference](candidate/elixir-runtime/references/oban-pro.md), and the supplied prompts, plus primary public documentation. No application source, worktree, evaluation rubric, or other evaluation was inspected. No Tidewave tools were available. I did not install dependencies, use a database, change an application, or perform remote mutations. All validation below is proposed, not executed. Public AshOban guide pages identified themselves as 0.8.14 when inspected on 2026-09-10; some version-qualified URLs were unavailable. Unverified implementation details are described as pseudocode.

**A1. Welcome email changes over time**

Make welcome delivery a durable resource: user, kind, due time, status, operation key, provider receipt, and timestamps. Enforce one ordinary request per user with a database uniqueness constraint. Set its due time to signup plus one day. Support resends create separate, authorized requests with initiator, reason, and a link to the original; retain delivery attempts and outcomes.

Define SQL-compatible eligibility, in pseudocode: `pending AND due_at <= now AND user.active`. Recheck it during execution. Deactivation postpones an unsent request; reactivation restores eligibility without creating another ordinary request. Completed requests stay completed. Periodic reconciliation recreates lost jobs from eligible requests; pruning jobs after seven days cannot erase completion evidence. Oban uniqueness only lasts while relevant jobs remain retained. [Oban uniqueness](https://oban.hexdocs.pm/unique_jobs.html)

Use provider idempotency for retries. Without sufficient provider guarantees, stop ambiguous deliveries for reconciliation rather than promise both eventual delivery and at-most-once receipt. Test due-time boundaries, deactivate/reactivate, missing jobs, concurrent workers, post-pruning recovery, and resend history.

**A2. Vendor events arrive during outages**

Authenticate signatures and constrain request size before acceptance. Commit a `VendorEvent` containing tenant, vendor event ID, payload, receipt time, and pending status; enforce uniqueness on tenant/vendor/event ID. Return success only after durable commit, including for already accepted duplicates.

For normal latency, immediately attempt a separate dispatch action using `run_oban_trigger(:process)`, which AshOban documents for prompt action-driven enqueueing. Keep that attempt outside the acceptance transaction, with a bounded timeout: enqueue failure must leave the committed event pending. [AshOban action-triggered enqueueing](https://ash-oban.hexdocs.pm/getting-started-with-ash-oban.html#triggering-on-action)

Explicitly configure a one-minute recovery scan over indexed pending/due events. Most events take the immediate path and should finish within seconds; after enqueueing recovers, missed events wait up to the next healthy scan, plus backlog and execution time. A seconds-level recovery objective requires a separately verified faster dispatcher, not minute cron alone.

Workers recheck eligibility, preserve default locking, and process idempotently. Test concurrent duplicate acceptance, crash after commit, enqueue outage, lost jobs, tenant isolation, and measured ingestion-to-completion latency under load.

**A3. Delivery succeeds before persistence fails**

Persist an outbound operation and stable provider idempotency key before making the request. Bind the key to the logical operation and immutable payload, never an Oban job ID or attempt. Retries and reconstructed jobs reuse that key. Record a conservative first-dispatch timestamp durably before sending, so uncertainty about persistence cannot reset the 24-hour safety window.

If the provider accepts but completion fails to commit, retry with the same key while its guarantee remains valid. Persist the resulting provider receipt and completion when the database recovers. Row locks, job uniqueness, and an outbox cannot make the provider request and database commit atomic. This follows the supplied [external-effect failure-window guidance](candidate/elixir-runtime/references/ash-oban.md).

After key expiry, stop automatic resubmission of ambiguous operations. Query provider status using a durable business reference; otherwise require explicit reconciliation. Without a stronger provider contract, exactly-once completion after a longer outage is unprovable. Test acceptance followed by commit failure, retries before/after expiry, lost jobs, provider lookup failure, and unchanged keys/payloads across reconstruction.

**A4. Only an administrator starts this operation**

Expose an administrator-authorized `request_cancellation` action. It records the request and initiator, then applies `change run_oban_trigger(:cancel)`. Its worker calls a separate cancellation action and requires the appointment still to have that explicit request. Use this verified trigger configuration:

```elixir
trigger :cancel do
  action :perform_cancellation
  scheduler_cron false
  where expr(cancellation_requested == true)
  worker_module_name MyApp.Appointment.CancelWorker
end
```

Omitting `scheduler_cron` would enable minute scheduling in 0.8.14. [AshOban trigger DSL](https://ash-oban.hexdocs.pm/dsl-ashoban.html#oban-triggers-trigger)

Define execution authorization deliberately: persist the initiating administrator for current-permission checks, or grant a narrowly scoped worker permission to fulfill an already authorized request. Do not allow arbitrary callers to invoke the worker action directly.

Use manual Oban testing: call the actual administrator action, inspect its enqueued worker/record, then drain that queue and assert cancellation. Also assert an ordinary user creates neither request nor job, an unrequested appointment remains unchanged, and no cancellation scheduler is configured. Testing only the worker would miss the administrator boundary. [Testing guide](https://ash-oban.hexdocs.pm/testing.html)

**A5. Exhausted jobs keep coming back**

`max_attempts 3` limits one job. The scheduler sees the resource still pending and schedules another job with a fresh attempt allowance. The documentation explicitly identifies this behavior. [AshOban attempts and error options](https://ash-oban.hexdocs.pm/dsl-ashoban.html#oban-triggers-trigger)

Add an excluded domain state such as `failed_permanently`, plus failure time and a concise error code. Configure `on_error :mark_failed`; that small update action changes pending to failed after exhaustion. Its only essential responsibility is persisting ineligibility, so ancillary reporting cannot prevent the transition. The error argument is named `:error` if needed. [Error handling](https://ash-oban.hexdocs.pm/getting-started-with-ash-oban.html#handling-errors)

The worker must recheck current eligibility so already queued duplicates cannot continue processing failed records. Operators use an authorized correction/retry action that validates the corrected payload, preserves failure history, restores pending state, and requests processing. Do not clear historical evidence merely to retry.

Test three failures, persisted terminal state, several subsequent scans without replacement work, stale queued jobs, and one explicit corrected retry. Monitor failures of `mark_failed` itself, since an uncommitted terminal state still permits rescheduling.

**A6. User permissions change during a delay**

Store an export request with tenant, execution-user identifier, immutable requester audit identifier/snapshot, parameters, request time, status, and failure reason. Preserve audit data independently of a deletable user relationship. Initiator evidence and execution authorization serve different purposes.

Configure an actor persister that stores identity and reloads current permissions. A missing user must return an error, never a privileged fallback. AshOban's guide explicitly warns that users can disappear or permissions can change between scheduling and execution. [Actor persistence](https://ash-oban.hexdocs.pm/getting-started-with-ash-oban.html#persisting-the-actor-along-with-a-job)

Use a recovery scan that reads pending requests and explicitly dispatches each with the request's saved execution identity and tenant. Cron does not automatically know the original caller. At execution, reload and authorize that user again; a recovery scanner's system identity grants only discovery/dispatch, not export access. Persist a terminal authorization-denied/missing-user outcome through a narrowly scoped failure action.

Test revocation, deletion, tenant mismatch, reauthorization on retries, and job reconstruction after all arguments are lost. Assert no export artifact is produced and requester evidence remains available.

**A7. Fulfillment messages contradict their arrival order**

Keep vendor observations separate from internal order decisions. Each observation records tenant/vendor identity, deduplication key, payload, reported event time, receipt time, and vendor sequence/version when supplied. Duplicate transmissions can increment receipt metadata or append receipt records while applying the logical observation once.

Maintain a fulfillment projection using authoritative vendor ordering or an explicit reconciliation rule. If ordering metadata is unavailable, record Thursday's shipment as late evidence and retain Monday's delivered projection; investigate genuinely contradictory facts instead of treating arrival time as truth. Preserve the observation even when it cannot be applied.

Staff approval and cancellation remain authorized actions with permitted transitions, distinct from vendor fact ingestion. AshStateMachine can enforce action-specific transitions if the installed extension is verified; it does not supply the vendor conflict policy. [AshStateMachine transition guide](https://hex.pm/packages/ash_state_machine/0.2.13/files/documentation/tutorials/getting-started-with-ash-state-machine.md?fallback=default)

Corrections append actor, reason, superseded evidence, and before/after state. Test every message ordering, repeated shipment, replay, conflicting cancellation/delivery, concurrent staff actions, and deterministic rebuilding of the projection from retained evidence.

**A8. Bulk updates and worker renames**

Use an update trigger with Pro `chunks`, choosing size, timeout, and queue capacity from database/provider limits. Scheduling 100,000 matches still inserts 100,000 jobs. ChunkWorker groups them into bulk updates, partitioned by actor and tenant. One concurrency slot represents a chunk. Atomic-compatible actions can reduce SQL round trips; non-atomic actions use streaming. [AshOban chunk execution](https://ash-oban.hexdocs.pm/triggers-and-scheduled-actions.html#chunk-processing-oban-pro)

For remote cancellation, retain per-order durable intent, idempotency, retry outcomes, and provider rate limiting; a bulk API call does not imply one atomic external effect. Verify installed Pro compatibility.

Before renaming, explicitly preserve the existing deployed worker/scheduler module names and queue. If module identity must change, retain compatible old workers until old jobs finish. [Module identities](https://ash-oban.hexdocs.pm/dsl-ashoban.html#module-names)

To retire cron under Pro, deploy `state :deleted`, verify persistent schedule removal, then remove schedule source; use `:paused` for a temporary pause. Keep worker code for queued jobs. [Schedule lifecycle](https://ash-oban.hexdocs.pm/getting-started-with-ash-oban.html#changing-triggers-when-using-oban-pro)

Without Pro, use per-record triggers or ordinary bounded batching. Validate actor/tenant partitions, SQL behavior, partial failures, throttling, and queued-job compatibility across deployment.

**A9. A temporary import finishes next week**

Use one ordinary recursive Oban worker carrying an import-run ID and page cursor. Fetch a bounded page, validate it, then transactionally persist the page's idempotent upserts, durable checkpoint, and next-page job. If enqueueing fails, roll back that transaction; a retry reprocesses the same page safely. Do not hold a database transaction open while waiting for the legacy service.

A small temporary checkpoint record or existing migration ledger is sufficient. This is a bounded operational import, so it need not introduce a permanent Ash workflow resource, trigger graph, or Pro workflow. The official recursive-job pattern explicitly covers long-running external-service backfills. [Oban recursive jobs](https://oban.hexdocs.pm/recursive-jobs.html)

Reuse existing Ash write actions where domain validation or policies matter. Preserve the legacy cursor/snapshot semantics, cap concurrency, and honor rate limits. Test duplicate pages, failure after fetch, commit/enqueue failure, expired cursors, and restart from the checkpoint. Reconcile counts and sampled records before removing code; first verify no runnable or retryable import jobs still reference its worker module.

**A10. Available packages are older than the talk**

Treat Ash 3.5.42 and AshOban 0.4.12 as compatibility boundaries. Inspect their published package files or tagged source, including dependency usage rules when accessible, rather than copying current documentation. In this evaluation, the published 0.4.12 `AshOban.Test` source contains `schedule_and_run_triggers/2` only: it does not define `assert_would_schedule`, `assert_triggered`, or the newer `use AshOban.Test` wrapper. [Exact 0.4.12 source](https://hex.pm/packages/ash_oban/0.4.12/files/lib/test.ex)

Prepare three separate future tests: query the trigger's eligibility filter through a supported read action; call the create action and inspect enqueued jobs with version-matched Oban testing helpers; then drain only the relevant queue and assert the mocked side effect plus final resource state. Check scheduling-function options before selecting a specific trigger. Preserve actor/tenant context in all three.

Here I can verify published API availability and reason about test design. With no dependencies or running app, I cannot compile resources, evaluate eligibility, inspect jobs, or prove effects. Unconfirmed Ash 3.5.42 query signatures remain pseudocode; no runtime result is claimed.
