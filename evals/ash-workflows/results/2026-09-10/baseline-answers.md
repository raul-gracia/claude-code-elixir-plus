# Independent baseline answers

Model identity: this session identifies the assistant as Codex, based on GPT-6; no more specific serving-model identifier is exposed.

I used only the supplied baseline `elixir-runtime/SKILL.md`, its `references/oban-pro.md`, the task prompts, and public primary-source package documentation/source. No Tidewave tools were exposed. No application, dependencies, database, or remote state was changed. These are implementation proposals and validation plans, not executed application tests. Several versioned HexDocs URLs could not be fetched; the AshOban v0.8.14 tagged source and the getting-started page identifying itself as v0.8.14 were accessible. The old 0.4.12 test module was also accessible. Unverified implementation details are described as pseudocode.

## A1. Welcome email changes over time

Persist a `WelcomeDelivery` resource with user, kind, due time, state, stable delivery key, completion timestamp and provider receipt. Enforce one ordinary delivery per user with a database identity; create separate, explicitly authorized resend deliveries recording the support actor and reason. Keep delivery attempts/history independently of Oban pruning.

Signup creates the ordinary delivery due at signup plus one day. Eligibility is pending, due and currently active. Deactivation leaves an unsent delivery dormant; reactivation makes the same delivery eligible without clearing successful history. A periodic trigger reconstructs lost jobs from eligible resources. Workers reload eligibility immediately before sending, and concurrent workers serialize state changes.

Job uniqueness is an optimization: `trigger_once?` depends on retained completed jobs. [AshOban v0.8.14 source](https://raw.githubusercontent.com/ash-project/ash_oban/v0.8.14/lib/ash_oban.ex).

Use provider deduplication with the stable delivery key. Without durable provider deduplication or reconciliation, ambiguous sends must stop for review to preserve strict at-most-once delivery. Test deactivation/reactivation, concurrent workers, pruning, lost jobs, and independent resends.

## A2. Vendor events arrive during outages

Create a durable inbox resource containing vendor/tenant, vendor event identifier, authenticated payload, received time, processing state, attempts and error detail. A database identity on vendor/tenant/event identifier deduplicates concurrent deliveries; retain conflicting payloads for investigation instead of silently replacing accepted evidence.

The endpoint acknowledges only after the inbox commit. Immediately after commit, attempt `AshOban.run_trigger(record, :process)` for low latency, catching enqueue failure without deleting or rolling back the accepted event. A crash between commit and enqueue is recoverable. The processing action reloads the inbox row, skips completed events, applies idempotent changes and records completion.

Add a recovery trigger matching unfinished, retryable records with `scheduler_cron "* * * * *"`; 0.8.14 supports this periodic schedule. [Tagged source](https://raw.githubusercontent.com/ash-project/ash_oban/v0.8.14/lib/ash_oban.ex).

Normal processing can take seconds; recovery after enqueue failure waits until the next minute tick plus scheduling/backlog delay. An ongoing database outage prevents a bounded recovery promise. Verify durable acceptance during enqueue failure, restart recovery, duplicates and measured queue latency under load.

## A3. Delivery succeeds before persistence fails

Create and commit a durable operation identifier and immutable request payload before contacting the provider. Derive the provider idempotency key from that operation, never from the Oban job ID, attempt number, or a reconstructed job. Every retry sends the same key and payload, then records the provider receipt and completion if successful. Serialize competing execution and skip already completed operations.

A database rollback cannot undo the provider's acceptance. Within the provider's stated 24-hour deduplication window, a repeated request should recover the original outcome without another effect, according to that provider's precise contract. Store the first attempt time conservatively; timeout does not prove failure.

After a longer outage, the key may have expired. Reconcile using a provider lookup or retained receipt before attempting another send. If outcome cannot be established, mark the operation uncertain and require reconciliation; automatic retry risks duplication. Exactly-once delivery is not guaranteed across this boundary. Test acceptance followed by commit failure, retry within retention, and retry after expiration.

## A4. Only an administrator starts this operation

Use an administrator-authorized `request_cancellation` action to record cancellation intent and enqueue a dedicated trigger with `change run_oban_trigger(:cancel_requested)`. Its configuration is:

```elixir
trigger :cancel_requested do
  action :perform_cancellation
  scheduler_cron false
  where expr(cancellation_requested == true and status != :cancelled)
end
```

Explicitly disabling cron matters: omission otherwise schedules every minute in 0.8.14. Configure the worker queue, execution policy and actor persistence deliberately. [AshOban getting started](https://ash-oban.hexdocs.pm/getting-started-with-ash-oban.html).

The worker reloads the appointment, validates the persisted request, and makes cancellation idempotent. Do not give ordinary callers an alternate direct route to the background operation.

In manual Oban testing mode, invoke the actual administrator action with an administrator actor, inspect the queued worker and appointment primary key using Oban's testing helpers, then drain only its queue and assert cancellation. Verify a non-administrator request is forbidden and queues nothing. Assert scheduler configuration is disabled. Running a scheduler helper alone would not establish that the administrator action enqueues work.

## A5. Exhausted jobs keep coming back

`max_attempts 3` limits attempts on one job. The scheduler still finds the resource's unchanged `status: :pending` and can create another job after exhaustion. It does not remember a permanent resource-level failure. [AshOban trigger source](https://raw.githubusercontent.com/ash-project/ash_oban/v0.8.14/lib/ash_oban.ex).

Configure `on_error :mark_failed`. Make that a minimal update action setting a durable failed status, failure timestamp and sanitized error summary. If it accepts details, declare its `:error` argument. It must succeed independently of validation of the malformed business payload; do not repeat the remote operation or depend on another notification succeeding. The guide explicitly warns that a failing error action defeats this state change. [Error handling guide](https://ash-oban.hexdocs.pm/getting-started-with-ash-oban.html).

Expose an operator-authorized repair/retry action that validates corrected input, records who requested retry, and returns the resource to pending. Preserve previous failure history. Test three failures, subsequent scheduler ticks producing no work, and successful retry after repair; also test persistence failure in `mark_failed` and alert operators if it occurs.

## A6. User permissions change during a delay

Persist an `ExportRequest` with tenant, requested parameters, request time, immutable requester identifier, an audit snapshot sufficient to identify the requester after account deletion, and execution status. A nullable relationship to the current account can coexist with that audit identity. Do not store old permissions as execution authority.

Use a narrowly authorized service identity only to discover and dispatch outstanding requests. The execution action loads the current account and tenant membership from the request, then calls the actual export action as that requester with authorization enabled. Both the initial enqueue and cron reconstruction must enter this same execution path. A scheduler actor must never replace the requester for permission checks.

AshOban actor persistence can reload current actors, but missing actors must fail closed; actor information living only in a lost job cannot support reconstruction. [Actor guidance](https://ash-oban.hexdocs.pm/getting-started-with-ash-oban.html).

Deleted or revoked accounts produce a durable denied/cancelled outcome and audit entry. Test revocation, deletion, cross-tenant requests, lost-job recovery and retries, asserting no export data is produced after denial.

## A7. Fulfillment messages contradict their arrival order

Represent vendor observations as immutable records: vendor event ID, order identity, reported event type, occurrence time, arrival time, payload and authoritative vendor sequence/version when available. Deduplicate business processing by event ID; optionally retain each webhook receipt to show repeated transport deliveries.

Keep internal approval/cancellation transitions separate from vendor fulfillment observations. Expose explicit authorized Ash actions with allowed transitions and concurrency checks, recording actor, reason, previous state and resulting state. Delivery evidence does not automatically authorize an internal cancellation or approval.

Build a projection with defined precedence: a later-arriving shipment observation does not regress confirmed delivery. Prefer authoritative sequencing when supplied; arrival time alone is not business ordering, and conflicting timestamps should be flagged. Repeated shipment events add no repeated effect.

Corrections append a correction record referencing the original observation or transition, with explanation and approver, then recompute the projection. Do not overwrite evidence. Test every permutation of delivery/shipment arrival, duplicates, concurrent internal actions, and corrections that preserve the complete audit trail.

## A8. Bulk updates and worker renames

With compatible Pro installed and enabled, configure trigger `chunks` with a bounded size and timeout. The scheduler still creates per-record jobs; Pro collects them for `Ash.bulk_update/4`, partitioned by actor and tenant. This is distinct from an Oban Pro Batch completion callback. [AshOban v0.8.14 source](https://raw.githubusercontent.com/ash-project/ash_oban/v0.8.14/lib/ash_oban.ex).

Atomic cancellation changes permit bulk database execution. Remote-call changes need per-record execution or verified bulk callbacks and stable idempotency keys; do not claim one SQL operation covers network effects. Confirm the installed worker's bulk strategy before enabling this variant; ordinary workers are a safe fallback.

Pin worker/scheduler module names and queue names before renaming the trigger so retained jobs remain executable. Keep compatibility until scheduled and retryable old jobs drain. With Pro, deploy the old schedule as `state :deleted`, confirm deletion, then remove its configuration in a subsequent deployment. [Deployment guidance](https://ash-oban.hexdocs.pm/getting-started-with-ash-oban.html).

Without Pro, stream eligible records into ordinary jobs with bounded concurrency. Verify 100,000-record coverage, partial failures, tenant isolation, memory usage, and execution of jobs created before deployment.

## A9. A temporary import finishes next week

Use an ordinary Oban worker carrying an import identifier and page cursor. Fetch one bounded page with explicit timeout and retry handling. Validate it, upsert rows using stable legacy identifiers, and enqueue the next cursor in the same database transaction as the page's writes when both use the same database. If they cannot share a transaction, persist a checkpoint/outbox so continuation can be reconstructed.

A retry must tolerate partially observed remote responses and already imported rows. Keep page/checkpoint counts and error logs sufficient to verify completeness; reject cursor loops and stop only on the legacy service's explicit end condition. Rate-limit calls and bound memory per page.

This is a temporary linear chain; the supplied Oban Pro reference advises against introducing a Workflow for simple chains. A permanent domain resource/state machine is unnecessary unless users need durable import management. Test duplicate page execution and crashes before/after continuation insertion. Remove the worker only after verification and after all outstanding scheduled/retryable import jobs are resolved.

## A10. Available packages are older than the talk

Treat the stated lockfile versions as authoritative. Without Tidewave or `deps/`, inspect public sources tagged Ash 3.5.42 and AshOban 0.4.12, including their tests and changelogs. Do not install packages or use current documentation as proof of old APIs.

The accessible 0.4.12 `AshOban.Test` contains only `schedule_and_run_triggers/2`; it has neither the modern assertion macros nor a `use` helper. [Versioned test module](https://hex.pm/packages/ash_oban/0.4.12/files/lib/test.ex).

Prepare three independent tests: eligibility via a database read combining the record key and the trigger's verified filter; enqueueing by invoking the actual create action and inspecting the generated worker's queued arguments with supported Oban testing helpers; execution by draining the intended queue and asserting the provider adapter call and persisted outcome. Verify the exact older Ash query syntax and Oban version before writing runnable calls.

Here I can establish source-level API availability and draft tests. I cannot compile resources, validate database predicates, run policies, prove enqueueing, or execute the worker without dependencies and a configured test runtime.
