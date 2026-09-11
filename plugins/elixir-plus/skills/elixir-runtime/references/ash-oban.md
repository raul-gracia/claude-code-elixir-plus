# Working with Ash background operations

Use this procedure when designing or changing background work on Ash resources. It captures the approved workload-review concerns; use installed-version documentation for DSL syntax rather than treating the examples from a talk as an API specification.

## Inspect the resource and intended outcome

Find the action that owns the operation, its inputs and side effects, and the resource state that says whether work remains. Reuse existing actions and policies across interfaces. For recurring business workflows, determine eligibility from durable domain state; use a SQL-compatible calculation when the same rule needs a name or multiple callers. Job retention and uniqueness are insufficient evidence of permanent business completion.

Trace deactivation, reactivation and explicit retries through the resource's state changes. If resending must preserve delivery history, use delivery/request records or a suitable audit trail; clearing a timestamp alone erases that distinction. Check whether eligible work can be reconstructed from domain records when pending jobs are absent. Test reconstruction in an isolated environment.

A temporary paginated import can use a normal Oban worker with durable progress and safe retries. It need not introduce a permanent Ash workflow resource. See the upstream [trigger model](https://ash-oban.hexdocs.pm/triggers-and-scheduled-actions.html) for the resource-backed case.

## Choose execution and recovery timing deliberately

Use `run_oban_trigger` from the relevant resource action when the operation should be enqueued promptly. Add a periodic eligibility scan when accepted work must recover from missed enqueueing, selecting its cadence from the recovery objective and database load. A trigger intentionally used only on demand needs `scheduler_cron false`; it has no periodic reconstruction guarantee.

For inbound events, authenticate the request and enforce transport/size limits before durable acceptance. Persist the accepted event with its source, tenant and deduplication identity, then process it asynchronously. Outbound requests can likewise have durable intent records. Preserve the trigger's execution-time eligibility check; a scheduler's earlier match is not proof that the operation is still appropriate.

Check the failure window between an external effect and the database commit. Reuse an operation-scoped provider idempotency key where supported, including across reconstructed jobs. Account for key expiry and ambiguous outcomes with reconciliation or explicit intervention. A row lock, uniqueness setting or outbox alone cannot guarantee exactly-once remote delivery. Keep row locks enabled unless the actual write/transaction model justifies changing them; append-only input by itself does not prove that processing is race-free.

## Preserve identity across retries and reconstruction

Distinguish the initiating actor in the audit record from the actor whose permissions govern execution. Store and restore the latter with the configured actor persister when required, and authorize against current permissions. Handle missing or revoked actors explicitly; silently switching to a privileged system actor changes the business rule.

Persist tenant and initiating-actor information in domain records when a cron scan must reconstruct lost jobs. Job arguments alone cannot preserve this information after job loss, and a cron scheduler does not automatically recover the original caller. If system execution is intended, define its permitted operations and retain the initiator separately. Preserve audit identifiers or snapshots according to the application's retention policy when actor records can be deleted. Consult [actor persistence](https://ash-oban.hexdocs.pm/getting-started-with-ash-oban.html) for the installed behavior.

For external state changes, retain deduplicated vendor observations separately from controlled internal transitions. Use vendor sequence/version information or a documented reconciliation rule when arrival order is unreliable. Keep corrections auditable; neither an unrestricted transition graph nor a strict graph alone resolves contradictory events.

## Verify operational facts against installed versions

The following facts were checked against AshOban 0.8.14 documentation on 2026-09-10. They are compatibility notes, not a requirement to upgrade; recheck the cited version's source when a project uses another release.

| Behavior | Required implementation decision | Revisit condition |
| --- | --- | --- |
| `scheduler_cron` defaults to every minute. | Set a deliberate cron expression or `false`. | Recheck when AshOban changes this default or makes the option required. |
| `max_attempts` limits a job; the scheduler can create another while the record still matches. | Put permanent failures into an excluded domain state with a small, reliable `on_error` action; make correction/retry restore eligibility explicitly. | Recheck when scheduling or final-error semantics change. |
| `lock_for_update?` defaults to true; `worker_read_action` can be customized. | Check execution-time eligibility and transaction semantics before changing either. | Recheck when the read action, data layer or transaction hooks change. |
| Generated worker and scheduler module identities are used by queued jobs. | Set stable module names; preserve old worker availability when a module identity must change. | Review every resource/trigger/module rename. |
| Pro persists cron schedules beyond resource source changes. | Deploy `state :deleted` before removing a schedule; use `:paused` for a temporary pause. Verify retirement before source deletion. | Recheck when the cron plugin or its reconciliation configuration changes. |

Sources are the [DSL as inspected](https://ash-oban.hexdocs.pm/dsl-ashoban.html) and [setup, error handling and schedule lifecycle](https://ash-oban.hexdocs.pm/getting-started-with-ash-oban.html). For Pro chunk execution, load [oban-pro.md](oban-pro.md); check atomic eligibility before promising a single SQL statement.

## Test eligibility, enqueueing and actual effects

Consult the installed `AshOban.Test` documentation before choosing helpers for each kind of test. `assert_would_schedule` and `refute_would_schedule` check eligibility; `assert_triggered` checks enqueueing; `schedule_and_run_triggers` schedules and drains work so the test can assert effects. Verify the installed helper's drain scope in its documentation or source before execution. Older releases may require `Oban.Testing`, explicit scheduling and controlled queue draining instead.

Select the specific resource/trigger to limit newly scheduled work, and establish queue/database isolation separately. [`Oban.drain_queue/2`](https://oban.hexdocs.pm/Oban.html#drain_queue/2), documented in Oban 2.24.1, executes all available jobs in the selected queue, including unrelated workers' jobs. Before any drain, use an isolated test queue or an Oban instance with isolated job storage, or ensure only intended jobs are visible to the drain.

In a target application's test environment, cover eligibility changes after enqueueing, recovery without pending jobs, retries after external success, terminal failures and explicit retries. Include tenant and actor changes, plus resend history and out-of-order events where relevant. Assert the business effect and resulting state after execution, not just a job count. The upstream [testing guide](https://ash-oban.hexdocs.pm/testing.html) describes manual mode; this procedure does not authorize running jobs against production.
