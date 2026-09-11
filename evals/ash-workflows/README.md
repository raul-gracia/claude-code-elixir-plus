# Evaluate Ash workflow guidance in context

Use this suite to evaluate `elixir-runtime` changes that affect Ash background work. It replaces the retired skill-dispatch scenarios in `EVAL_PLAN.md` for this scope and keeps task prompts separate from grading criteria.

## Run isolated reasoning evaluations for comparison

1. Save the baseline and candidate skill folders, including referenced files. Record the source commit or file hashes for each condition.
2. Give a fresh agent only the skill folder and [prompts.md](prompts.md), with the same public-documentation tool access for both conditions. Ask for implementation approaches rather than running application operations. Do not provide [rubric.md](rubric.md), the talk, implementation plans or another agent's answers.
3. Save the complete answers and record the harness/model identity. Prefer a separate context for every task when making a release-quality comparison; a single batched context per condition is a cheaper smoke test whose tasks may influence each other.
4. Grade against the frozen rubric after answers are complete. Record per-criterion decisions with evidence and report ties or uncertain results. A single run cannot establish an improvement across models or Claude Code sessions.

For a discovery smoke test, expose only the baseline or candidate frontmatter description and ask whether it applies to an Ash-only prompt such as "change the eligibility rule for this AshOban trigger", alongside an unrelated prompt such as "fix a React modal". Report the classification as a reasoning check. Actual native dispatch requires a fresh session in the target harness; session-hook injection is a different mechanism.

## Verify behavior in an application test environment

These acceptance scenarios require a disposable database and the target application's dependencies. Use its installed-version AshOban documentation, `Oban` manual testing mode where supported, and test doubles for external providers; do not run this protocol against a live service.

| Scenario | Arrange and execute | Observable requirement |
| --- | --- | --- |
| Eligibility changes after enqueueing | Enqueue eligible work, deactivate or otherwise invalidate the record, then drain the relevant worker queue. | No forbidden business effect occurs. |
| Lost pending jobs | Persist eligible domain intent without its pending job, invoke the recovery scheduler, then execute its work. | Intent is recovered with the required actor/tenant context and completed once under the provider's deduplication contract. |
| Provider success before commit | Make a provider double accept an operation, fail the local completion step, and retry with the same operation identifier. | The provider deduplicates within its supported key lifetime; expired/ambiguous outcomes follow the chosen reconciliation rule. |
| Permanent failure and correction | Exhaust a permanently invalid record, run another scheduler pass, then correct it through the retry action. | Terminal state prevents new work until correction restores eligibility. |
| Changed authorization | Schedule with an actor, change/revoke/delete that actor before execution, and include another tenant's record. | Execution follows current authorization without cross-tenant access or silent privilege escalation. |
| Resend and vendor history | Resend a previously delivered operation; feed duplicate and out-of-order vendor events. | Required delivery/event history remains inspectable and state follows the documented reconciliation policy. |

Keep eligibility assertions separate from enqueue assertions and side-effect tests. `assert_would_schedule` checks a predicate; `assert_triggered` checks queued work; `schedule_and_run_triggers` executes work. Verify helper availability and drain scope in the installed version's documentation or source, and use lower-level `Oban.Testing` scheduling/draining when needed. For testing locking claims, use actual concurrent database sessions rather than treating a sequential state-change test as proof of race safety.

Selecting a specific resource/trigger limits newly scheduled work; queue/database isolation must be established separately. [`Oban.drain_queue/2`](https://oban.hexdocs.pm/Oban.html#drain_queue/2) executes all available jobs in the selected queue, including unrelated workers' jobs. Before any drain, use an isolated test queue or an Oban instance with isolated job storage, or ensure only intended jobs are visible to the drain.

## Record structural checks and evidence limits

Validate skill frontmatter and local links, parse the plugin manifest, and exercise the session hook in temporary directories with and without `mix.exs`. Package the skill into a temporary artifact and inspect the included references. These checks establish that the instructions can be loaded, not that generated Ash code is correct.

Save run results under `results/`, with raw model answers in an adjacent directory. The [2026-09-10 comparison](results/2026-09-10.md) records the first run. Keep raw answers unchanged, even when they contain prose the repository would otherwise edit. Label every application scenario as passed, failed or not run, with the actual commands and environment when it was run.
