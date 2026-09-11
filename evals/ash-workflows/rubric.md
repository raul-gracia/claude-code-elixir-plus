# Grading criteria for Ash workflow evaluation

Keep this file away from the agents answering `prompts.md`. Freeze the criteria before either condition runs, and grade the saved answers using the same standard. A criterion passes only when the answer states or demonstrates it; plausible unstated knowledge receives no credit.

## Criteria for each independent task

| Task | Required outcomes, each worth one point |
| --- | --- |
| A1 | Domain state determines pending work and completion independently of job retention; reactivation and explicit resend preserve required history; reconciliation can reconstruct eligible work; execution rechecks eligibility and addresses duplicate effects. |
| A2 | Durable authenticated ingestion with a deduplication identity; immediate trigger plus recovery scan; eligibility and recovery cadence reflect the workload; terminal failures leave the eligible set until an explicit retry. |
| A3 | Identifies remote success followed by local failure; reuses an operation-scoped provider key; treats the 24-hour expiry and ambiguous outcomes explicitly; does not claim that locking or an outbox alone guarantees exactly-once delivery. |
| A4 | Sets `scheduler_cron false`; enqueues from the administrator action with its authorization context; distinguishes enqueue assertions from worker-effect tests; states how eligibility is checked at execution. |
| A5 | Explains new jobs after per-job retry exhaustion; transitions to a domain failure state excluded by the predicate; keeps terminal error handling small and reliable; restores eligibility through an explicit correction/retry action. |
| A6 | Distinguishes initiating actor from execution actor; checks current authorization and handles revoked/deleted actors without silently escalating; persists tenant and initiator information needed by reconstruction; retains audit evidence after actor deletion. |
| A7 | Preserves vendor events and deduplicates them; avoids regressing solely on arrival order; separates external observations from controlled internal transitions; supports auditable corrections or reconciliation. |
| A8 | Explains one scheduled job per record and Pro chunk batching; distinguishes atomic SQL updates from per-record remote effects; handles stable worker identities and persistent cron retirement; offers ordinary batching/per-record processing without assuming Pro. |
| A9 | Accepts a normal Oban worker or justified lightweight chain; persists progress and makes reruns safe; avoids forcing permanent Ash resources for a temporary operation; identifies validation/cleanup after completion. |
| A10 | Uses the lockfile's versions and upstream versioned docs; does not claim unavailable runtime introspection; distinguishes eligibility, enqueue and effect tests using supported helpers or lower-level alternatives; reports runtime behavior as unverified without dependencies and execution. |

## How to compare the conditions

Compare the unchanged baseline skill with the candidate skill under the same tool access. Save the full answers, model/harness identity, source revision, execution date and any environment limitations. Use a fresh context for each condition; batching these tasks in one context is a smoke test and must be reported as such.

There are 40 required outcomes. Any exactly-once claim unsupported by the provider contract, silent authorization escalation, or automatic periodic cancellation in A4 is a release blocker even when the aggregate score is high. Fix the candidate and rerun the affected task with a fresh evaluator if one occurs; report the original failure and the retest separately.

A single comparison is descriptive evidence. It does not demonstrate statistical improvement, implicit skill selection by Claude Code, or correctness of generated application code. Keep raw evaluation answers intact even when their prose differs from the repository's editorial conventions.
