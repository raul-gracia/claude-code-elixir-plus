# Independent grading of Ash workflow reasoning smoke evaluations

Graded: 2026-09-10 (session date).

Inputs inspected: the frozen `evals/ash-workflows/rubric.md` and `prompts.md`, plus `/tmp/dc-198-eval/baseline-answers.md` and `/tmp/dc-198-eval/candidate-answers.md`. No skill bodies, implementation plans, application code, linked sources, or other evaluation material were inspected. The raw answer files were not changed.

Each numbered criterion below follows the frozen rubric's order. A PASS requires the answer to state or demonstrate every component of that criterion. Each task is graded independently; material in A5, for example, cannot supply an omission in A2. Quoted fragments are exact excerpts from the relevant answer. Ellipses between separately quoted fragments indicate separate evidence, not omitted requirements. These are reasoning judgments, not executable test results or independent verification of the cited APIs.

## Totals

| Task | Baseline | Candidate |
| --- | ---: | ---: |
| A1 | 4/4 | 4/4 |
| A2 | 3/4 | 3/4 |
| A3 | 4/4 | 4/4 |
| A4 | 4/4 | 4/4 |
| A5 | 4/4 | 4/4 |
| A6 | 4/4 | 4/4 |
| A7 | 4/4 | 4/4 |
| A8 | 4/4 | 4/4 |
| A9 | 4/4 | 4/4 |
| A10 | 4/4 | 4/4 |
| **Total** | **39/40** | **39/40** |

The results are tied. Both answers omit A2's explicit treatment of terminal failures remaining ineligible until an explicit retry. No release blocker was found in either saved answer set. This single comparison is descriptive smoke evidence; it establishes neither statistical improvement, implicit skill selection, nor correctness of generated application code.

## A1. Welcome email changes over time

| Criterion | Baseline decision and evidence | Candidate decision and evidence |
| --- | --- | --- |
| 1. Domain state determines pending work and completion independently of job retention. | **PASS.** Stores delivery “state” and “completion timestamp”; states “Eligibility is pending, due and currently active” and “Keep delivery attempts/history independently of Oban pruning.” | **PASS.** Defines `pending AND due_at <= now AND user.active`; states “Completed requests stay completed” and “pruning jobs after seven days cannot erase completion evidence.” |
| 2. Reactivation and explicit resend preserve required history. | **PASS.** “reactivation makes the same delivery eligible without clearing successful history”; “create separate, explicitly authorized resend deliveries recording the support actor and reason.” | **PASS.** “reactivation restores eligibility without creating another ordinary request”; “Support resends create separate, authorized requests with initiator, reason, and a link to the original; retain delivery attempts and outcomes.” |
| 3. Reconciliation can reconstruct eligible work. | **PASS.** “A periodic trigger reconstructs lost jobs from eligible resources.” | **PASS.** “Periodic reconciliation recreates lost jobs from eligible requests”. |
| 4. Execution rechecks eligibility and addresses duplicate effects. | **PASS.** “Workers reload eligibility immediately before sending”; “Use provider deduplication with the stable delivery key”; ambiguous sends stop for review without sufficient deduplication or reconciliation. | **PASS.** “Recheck it during execution”; “Use provider idempotency for retries”; “stop ambiguous deliveries for reconciliation” without sufficient provider guarantees. |

## A2. Vendor events arrive during outages

| Criterion | Baseline decision and evidence | Candidate decision and evidence |
| --- | --- | --- |
| 1. Durable authenticated ingestion with a deduplication identity. | **PASS.** “Create a durable inbox resource” containing “authenticated payload”; “A database identity on vendor/tenant/event identifier deduplicates concurrent deliveries”; acknowledges “only after the inbox commit.” | **PASS.** “Authenticate signatures”; “Return success only after durable commit”; “enforce uniqueness on tenant/vendor/event ID.” |
| 2. Immediate trigger plus recovery scan. | **PASS.** “Immediately after commit, attempt `AshOban.run_trigger(record, :process)`”; “Add a recovery trigger” with `scheduler_cron "* * * * *"`. | **PASS.** “immediately attempt a separate dispatch action using `run_oban_trigger(:process)`”; “Explicitly configure a one-minute recovery scan”. |
| 3. Eligibility and recovery cadence reflect the workload. | **PASS.** Recovery matches “unfinished, retryable records”; “Normal processing can take seconds”; recovery waits for “the next minute tick plus scheduling/backlog delay”; proposes measured queue latency under load. | **PASS.** Scans “indexed pending/due events”; immediate processing “should finish within seconds”; identifies the next healthy scan plus backlog/execution delay and says a seconds-level recovery objective needs a faster dispatcher. |
| 4. Terminal failures leave the eligible set until an explicit retry. | **FAIL.** Although recovery matches “unfinished, retryable records,” A2 never states that terminal failure changes a record to an excluded state, nor that only explicit retry restores eligibility. A5's separate answer cannot fill this omission. | **FAIL.** A2 describes pending/due eligibility and idempotent processing, but gives no terminal-failure transition excluding records from recovery and no explicit retry action restoring eligibility. A5's separate answer cannot fill this omission. |

## A3. Delivery succeeds before persistence fails

| Criterion | Baseline decision and evidence | Candidate decision and evidence |
| --- | --- | --- |
| 1. Identifies remote success followed by local failure. | **PASS.** “A database rollback cannot undo the provider's acceptance”; explicitly proposes testing “acceptance followed by commit failure”. | **PASS.** “If the provider accepts but completion fails to commit, retry with the same key while its guarantee remains valid.” |
| 2. Reuses an operation-scoped provider key. | **PASS.** “Derive the provider idempotency key from that operation, never from the Oban job ID, attempt number, or a reconstructed job. Every retry sends the same key and payload”. | **PASS.** “Bind the key to the logical operation and immutable payload, never an Oban job ID or attempt. Retries and reconstructed jobs reuse that key.” |
| 3. Treats the 24-hour expiry and ambiguous outcomes explicitly. | **PASS.** Identifies the “24-hour deduplication window”; says “timeout does not prove failure”; after expiry, reconcile and “mark the operation uncertain” if the outcome cannot be established. | **PASS.** Persists first-dispatch time so uncertainty cannot reset the “24-hour safety window”; “After key expiry, stop automatic resubmission of ambiguous operations”; query provider status or require explicit reconciliation. |
| 4. Does not claim that locking or an outbox alone guarantees exactly-once delivery. | **PASS.** Serialization is proposed, but the answer expressly limits guarantees: “Exactly-once delivery is not guaranteed across this boundary.” No locking/outbox exactly-once claim appears. | **PASS.** “Row locks, job uniqueness, and an outbox cannot make the provider request and database commit atomic”; “Without a stronger provider contract, exactly-once completion after a longer outage is unprovable.” |

## A4. Only an administrator starts this operation

| Criterion | Baseline decision and evidence | Candidate decision and evidence |
| --- | --- | --- |
| 1. Sets `scheduler_cron false`. | **PASS.** Trigger code explicitly contains `scheduler_cron false`. | **PASS.** Trigger code explicitly contains `scheduler_cron false`. |
| 2. Enqueues from the administrator action with its authorization context. | **PASS.** “Use an administrator-authorized `request_cancellation` action” with `change run_oban_trigger(:cancel_requested)`; tests “the actual administrator action with an administrator actor” and verifies non-administrators are forbidden. See the wording limitation below. | **PASS.** “Expose an administrator-authorized `request_cancellation` action. It records the request and initiator, then applies `change run_oban_trigger(:cancel)`”; explicitly describes retaining the initiating administrator or narrowly granting execution permission for the authorized request. |
| 3. Distinguishes enqueue assertions from worker-effect tests. | **PASS.** “inspect the queued worker and appointment primary key” and then “drain only its queue and assert cancellation”; distinguishes scheduler-helper tests from action-enqueue evidence. | **PASS.** “call the actual administrator action, inspect its enqueued worker/record, then drain that queue and assert cancellation”; warns that testing only the worker misses the administrator boundary. |
| 4. States how eligibility is checked at execution. | **PASS.** “The worker reloads the appointment, validates the persisted request, and makes cancellation idempotent”; the trigger predicate requires requested cancellation and a non-cancelled status. | **PASS.** The worker “requires the appointment still to have that explicit request”; trigger predicate is `cancellation_requested == true`. |

## A5. Exhausted jobs keep coming back

| Criterion | Baseline decision and evidence | Candidate decision and evidence |
| --- | --- | --- |
| 1. Explains new jobs after per-job retry exhaustion. | **PASS.** “`max_attempts 3` limits attempts on one job”; the unchanged pending resource allows the scheduler to “create another job after exhaustion.” | **PASS.** “`max_attempts 3` limits one job”; the still-pending resource gets “another job with a fresh attempt allowance.” |
| 2. Transitions to a domain failure state excluded by the predicate. | **PASS.** Configures `on_error :mark_failed` to set “a durable failed status”; the stated scheduler matches `status: :pending`, and validation explicitly expects later ticks to produce no work. | **PASS.** “Add an excluded domain state such as `failed_permanently`”; `on_error :mark_failed` “changes pending to failed after exhaustion.” |
| 3. Keeps terminal error handling small and reliable. | **PASS.** “a minimal update action”; “must succeed independently of validation of the malformed business payload”; does not repeat the remote operation or depend on a notification; monitors persistence failure. | **PASS.** “that small update action”; “Its only essential responsibility is persisting ineligibility, so ancillary reporting cannot prevent the transition”; monitors failures of `mark_failed` itself. |
| 4. Restores eligibility through an explicit correction/retry action. | **PASS.** “an operator-authorized repair/retry action that validates corrected input, records who requested retry, and returns the resource to pending.” | **PASS.** “Operators use an authorized correction/retry action that validates the corrected payload, preserves failure history, restores pending state, and requests processing.” |

## A6. User permissions change during a delay

| Criterion | Baseline decision and evidence | Candidate decision and evidence |
| --- | --- | --- |
| 1. Distinguishes initiating actor from execution actor. | **PASS.** Stores requester identity; uses a service identity “only to discover and dispatch”; performs the actual export “as that requester with authorization enabled”; the scheduler actor must not replace the requester. | **PASS.** Stores execution-user and requester audit identities; “Initiator evidence and execution authorization serve different purposes”; discovery/dispatch authority is distinct from export authority. |
| 2. Checks current authorization and handles revoked/deleted actors without silently escalating. | **PASS.** Loads the “current account and tenant membership”; missing actors “must fail closed”; “Deleted or revoked accounts produce a durable denied/cancelled outcome and audit entry.” | **PASS.** “At execution, reload and authorize that user again”; “A missing user must return an error, never a privileged fallback”; persists authorization-denied/missing-user outcomes. |
| 3. Persists tenant and initiator information needed by reconstruction. | **PASS.** Persists an export request with “tenant” and “immutable requester identifier”; both enqueue and reconstruction use the same execution path; states job-only actor information cannot support reconstruction. | **PASS.** Stores tenant, execution-user identity and requester audit identity; recovery explicitly dispatches with “the request's saved execution identity and tenant.” |
| 4. Retains audit evidence after actor deletion. | **PASS.** “an audit snapshot sufficient to identify the requester after account deletion”; a nullable current-account relationship coexists with that audit identity. | **PASS.** “immutable requester audit identifier/snapshot”; “Preserve audit data independently of a deletable user relationship.” |

## A7. Fulfillment messages contradict their arrival order

| Criterion | Baseline decision and evidence | Candidate decision and evidence |
| --- | --- | --- |
| 1. Preserves vendor events and deduplicates them. | **PASS.** “vendor observations as immutable records” with event ID and payload; “Deduplicate business processing by event ID”; corrections do not overwrite evidence. | **PASS.** Each observation records identity, deduplication key and payload; applies “the logical observation once”; “Preserve the observation even when it cannot be applied.” |
| 2. Avoids regressing solely on arrival order. | **PASS.** “a later-arriving shipment observation does not regress confirmed delivery”; “arrival time alone is not business ordering”. | **PASS.** “record Thursday's shipment as late evidence and retain Monday's delivered projection”; does not treat arrival time as truth. |
| 3. Separates external observations from controlled internal transitions. | **PASS.** “Keep internal approval/cancellation transitions separate from vendor fulfillment observations”; “explicit authorized Ash actions with allowed transitions and concurrency checks”. | **PASS.** “Keep vendor observations separate from internal order decisions”; staff actions have “permitted transitions, distinct from vendor fact ingestion.” |
| 4. Supports auditable corrections or reconciliation. | **PASS.** Corrections append references to original evidence “with explanation and approver,” then recompute the projection without overwriting evidence. | **PASS.** “Corrections append actor, reason, superseded evidence, and before/after state”; tests deterministic rebuilding from retained evidence. |

## A8. Bulk updates and worker renames

| Criterion | Baseline decision and evidence | Candidate decision and evidence |
| --- | --- | --- |
| 1. Explains one scheduled job per record and Pro chunk batching. | **PASS.** “The scheduler still creates per-record jobs; Pro collects them for `Ash.bulk_update/4`, partitioned by actor and tenant.” | **PASS.** “Scheduling 100,000 matches still inserts 100,000 jobs. ChunkWorker groups them into bulk updates, partitioned by actor and tenant.” |
| 2. Distinguishes atomic SQL updates from per-record remote effects. | **PASS.** “Atomic cancellation changes permit bulk database execution”; remote-call changes require “per-record execution or verified bulk callbacks and stable idempotency keys”; “do not claim one SQL operation covers network effects.” | **PASS.** Atomic-compatible actions reduce SQL round trips; remote cancellation retains “per-order durable intent, idempotency, retry outcomes, and provider rate limiting”; “a bulk API call does not imply one atomic external effect.” |
| 3. Handles stable worker identities and persistent cron retirement. | **PASS.** “Pin worker/scheduler module names and queue names before renaming”; keep compatibility until old jobs drain; “deploy the old schedule as `state :deleted`, confirm deletion, then remove its configuration in a subsequent deployment.” | **PASS.** Preserves existing deployed module names and queue, retaining old workers if identities change; deploys `state :deleted`, verifies persistent removal, then removes source; keeps workers for queued jobs. |
| 4. Offers ordinary batching/per-record processing without assuming Pro. | **PASS.** “Without Pro, stream eligible records into ordinary jobs with bounded concurrency.” | **PASS.** “Without Pro, use per-record triggers or ordinary bounded batching.” |

## A9. A temporary import finishes next week

| Criterion | Baseline decision and evidence | Candidate decision and evidence |
| --- | --- | --- |
| 1. Accepts a normal Oban worker or justified lightweight chain. | **PASS.** “Use an ordinary Oban worker carrying an import identifier and page cursor”; describes a temporary linear chain. | **PASS.** “Use one ordinary recursive Oban worker carrying an import-run ID and page cursor.” |
| 2. Persists progress and makes reruns safe. | **PASS.** Uses stable-ID upserts and transactional page writes plus continuation; otherwise persists “a checkpoint/outbox so continuation can be reconstructed”; retries tolerate already imported rows and retains page/checkpoint counts. | **PASS.** Transactionally persists “the page's idempotent upserts, durable checkpoint, and next-page job”; “a retry reprocesses the same page safely.” |
| 3. Avoids forcing permanent Ash resources for a temporary operation. | **PASS.** “A permanent domain resource/state machine is unnecessary unless users need durable import management.” | **PASS.** A temporary checkpoint or migration ledger suffices; “it need not introduce a permanent Ash workflow resource, trigger graph, or Pro workflow.” |
| 4. Identifies validation/cleanup after completion. | **PASS.** Retains counts/logs “to verify completeness”; removes the worker “only after verification and after all outstanding scheduled/retryable import jobs are resolved.” | **PASS.** “Reconcile counts and sampled records before removing code”; first verify no runnable or retryable jobs still reference the worker. |

## A10. Available packages are older than the talk

| Criterion | Baseline decision and evidence | Candidate decision and evidence |
| --- | --- | --- |
| 1. Uses the lockfile's versions and upstream versioned docs. | **PASS.** “Treat the stated lockfile versions as authoritative”; inspect sources tagged “Ash 3.5.42 and AshOban 0.4.12”; links exact-version package documentation/source and rejects current docs as proof of older APIs. | **PASS.** “Treat Ash 3.5.42 and AshOban 0.4.12 as compatibility boundaries”; inspects published package files/tagged source; links exact 0.4.12 package source and rejects copying current documentation. |
| 2. Does not claim unavailable runtime introspection. | **PASS.** Begins “Without Tidewave or `deps/`” and claims only source-level API inspection and test drafting; no runtime introspection claim. | **PASS.** Header states “No Tidewave tools were available”; A10 says it cannot inspect jobs or evaluate eligibility without dependencies/running app. |
| 3. Distinguishes eligibility, enqueue and effect tests using supported helpers or lower-level alternatives. | **PASS.** Separates a record-key/filter database read, invoking the create action and inspecting queued arguments with supported Oban helpers, and draining the relevant queue to assert adapter call/state; verifies older query syntax and Oban version before runnable calls. | **PASS.** Separates supported eligibility-filter reads, create-action enqueue inspection with version-matched Oban helpers, and queue draining to assert mocked effect/final state; checks older scheduling options before selecting a trigger. |
| 4. Reports runtime behavior as unverified without dependencies and execution. | **PASS.** “I cannot compile resources, validate database predicates, run policies, prove enqueueing, or execute the worker without dependencies and a configured test runtime.” | **PASS.** “With no dependencies or running app, I cannot compile resources, evaluate eligibility, inspect jobs, or prove effects”; “no runtime result is claimed.” |

## Release-blocker scan

| Frozen blocker | Baseline | Candidate |
| --- | --- | --- |
| Exactly-once claim unsupported by provider contract. | **Not found.** A1 conditions duplicate protection on provider guarantees/reconciliation and stops ambiguous sends. A3 explicitly says exactly-once delivery is not guaranteed across the expiry boundary and qualifies the 24-hour guarantee by the provider's precise contract. | **Not found.** A1 stops ambiguous deliveries without sufficient guarantees. A3 rejects atomicity from locks, uniqueness or an outbox and says exactly-once completion after longer outages is unprovable without a stronger provider contract. |
| Silent authorization escalation. | **Not found.** A6 limits the service actor to discovery/dispatch, executes as the current requester, and fails closed after revocation/deletion. A4 requires administrator initiation and blocks ordinary callers from a direct worker-action route. | **Not found.** A6 forbids privileged fallback and limits scanner authority to discovery/dispatch. A4 explicitly offers a narrowly scoped worker permission for an already authorized request as an alternative policy; it does not silently substitute privilege after requester authorization fails. |
| Automatic periodic cancellation in A4. | **Not found.** Explicit `scheduler_cron false`, with a test asserting scheduler configuration is disabled. | **Not found.** Explicit `scheduler_cron false`, with a test asserting no cancellation scheduler is configured. |

No release-blocker retest is triggered by these saved answers. The shared A2 omission remains an ordinary failed outcome; this grading does not repair either answer.

## Rubric wording and evidence limits

- A4's phrase “with its authorization context” does not say whether it requires administrator authorization at initiation, concrete AshOban actor propagation configuration, or reauthorization as that administrator at execution. The baseline explicitly supplies administrator-authorized initiation and an administrator actor in the action test, so that stated requirement receives credit. It only says to configure execution policy and actor persistence “deliberately”; it does not demonstrate a concrete actor-persistence implementation. If the rubric intended to require such implementation, the frozen wording leaves that stricter requirement ambiguous. No unstated propagation or execution authorization mechanism is credited here.
- A10's “upstream versioned docs” is supported in both answers by exact-version upstream package source references and an explicit version-aware discovery approach. This grading does not establish the correctness of the cited API claims or whether both package versions were actually inspected; no linked material was opened. The prompts permit pseudocode when installed APIs cannot be verified.
- The approximate 150-word prompt target is not one of the 40 scored outcomes. No extra style or length penalty has been added.
- Both headers identify the assistant as Codex based on GPT-6 and say a more specific serving snapshot is unavailable. Both disclaim application execution and Tidewave availability. The candidate header dates its public-documentation inspection to 2026-09-10. The supplied answer files do not contain complete source-revision metadata or a baseline execution date. Those provenance gaps are recorded without inventing metadata or adding scored criteria.
- Both inputs bundle all ten tasks in one saved answer set. The task assignment identifies them as smoke evaluations. The four permitted inputs cannot independently establish fresh-context isolation or equal tool access; the scores assess only the saved reasoning.
