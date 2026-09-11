# Plan for Ash runtime guidance improvements

Track this work in [DC-198](https://linear.app/digital-chronos/issue/DC-198/improve-ash-and-ashoban-guidance-in-elixir-plus). The source is [Zach Daniel's workload modeling talk](https://www.youtube.com/watch?v=ZhUfURGmlqY); verify API details against package documentation because captions omit slide code.

The approved scope covers all six actions below, including the conditional AshOban workflow reference and the Pro chunk integration. Keep one capability skill, preserve the existing hooks, and keep general framework tutorials upstream. Work on `dc-198-ash-runtime`, starting from `66f0e31c05a9d4020ad5663aead9fa2f5a5ca387`.

## Actions, deliverables and acceptance criteria

| Action | Implementation | Acceptance evidence |
| --- | --- | --- |
| 1. Discover Ash and load version-matched guidance | Expand the `elixir-runtime` description; inspect dependency versions and usage rules; add resource and trigger introspection pointers; load the new reference only for Ash background work. | Ash-only prompts select the skill; unrelated prompts do not. Guidance works without a running Tidewave server and does not invent installed dependencies. |
| 2. Evaluate ownership of workflow state | Add a short domain-state review procedure and lifecycle scenarios. Keep completion history, eligibility and recovery in the model when business requirements need them; retain the ordinary-worker option for temporary tasks. | Evaluate deactivation, reactivation, resend and loss of pending jobs. A one-off migration does not require a permanent domain abstraction. |
| 3. Capture AshOban operational traps | Add a versioned fact table for explicit scheduler configuration, retry exhaustion, worker naming and persistent schedule removal. Include source links and concrete revisit conditions. | Verify against AshOban 0.8.14 documentation; older-project scenarios require installed-version verification instead of applying new APIs blindly. |
| 4. Cover prompt execution and recovery | Explain immediate `run_oban_trigger` plus periodic reconciliation when required; cover admission rules, terminal state and external-side-effect crash windows. | Evaluate missed enqueueing, scheduler rescheduling after retry exhaustion, and provider success before database commit. No exactly-once guarantee from a lock or outbox alone. |
| 5. Preserve identity and workflow history | Separate execution actor from initiating actor, carry tenant context, and plan identity reconstruction during recovery. Distinguish delivery history and vendor observations from mutable workflow state. | Evaluate changed permissions, deleted actors, tenant isolation, resend history, duplicate and out-of-order vendor events. |
| 6. Replace historical evaluation coverage | Add isolated task prompts and a separate grading rubric; run baseline and candidate reasoning evaluations with fresh contexts. Document the real-app execution protocol using version-supported AshOban test helpers. | Record raw answers, individual criterion results, structural checks and limitations. Do not label reasoning evaluations as database or delivery tests. |

## File changes and loading boundaries

- Edit `plugins/elixir-plus/skills/elixir-runtime/SKILL.md` for discovery, documentation routing and a conditional reference link.
- Add `references/ash-oban.md` for the approved workflow procedure, version facts and test-helper routing. Keep it concise and load it only when the task involves Ash background work.
- Extend `references/oban-pro.md` with AshOban chunk behavior and its limits. Keep Pro-specific execution details there.
- Add `evals/ash-workflows/` with task prompts, a grading rubric and recorded results. Preserve `EVAL_PLAN.md` as historical and link readers to the current evaluation.
- Update `README.md` and repository `CLAUDE.md` to describe the approved scope accurately. Bump the plugin version to `2.0.2` for the content update; upstream released `2.0.1` while this work was underway.

## Execution order and verification procedure

1. Freeze the prompts and rubric, then capture the unchanged baseline skill. Start its isolated evaluation while preparing the candidate.
2. Verify version-sensitive claims against upstream documentation and implement actions 1 through 5, including Pro integration. Do not copy a broad extension catalog or unverified slide syntax.
3. Run the candidate against the same prompts with the same tool access. Score both conditions against the frozen rubric; record omissions as failures and unavailable evidence as unverified.
4. Validate frontmatter, relative links and JSON manifests. Exercise the session hook in temporary directories with and without `mix.exs`, and package the skill to a temporary artifact.
5. Run the humanizer check on authored prose, then the independent review/fix loop. Fix verified high and medium findings and rerun affected checks.
6. Record the final evidence, commit the reviewed change with `DC-198` in the subject, and push the branch. Update the ticket and write a short vault handoff. Integration into main remains a separate decision.

## Evaluation limits and follow-up boundaries

This repository is a Markdown plugin rather than an Ash application. Reasoning evaluations can reveal instruction failures, but they cannot prove database locking, delivery idempotency or authorization behavior in a deployed application. Document those executable acceptance scenarios for a target application and report whether they were actually run.

Use the baseline comparison to decide how much reference text earns its place. Report ties and inconclusive results plainly; a single run in this harness does not establish a Claude Code performance improvement. No dependency installation, production operation or cross-harness configuration change is required by this plan.

## Completion evidence for the six actions

Actions 1 through 5 are implemented in the [skill entrypoint](../plugins/elixir-plus/skills/elixir-runtime/SKILL.md), [AshOban reference](../plugins/elixir-plus/skills/elixir-runtime/references/ash-oban.md) and [Pro integration reference](../plugins/elixir-plus/skills/elixir-runtime/references/oban-pro.md). Action 6 is recorded in the [evaluation results](../evals/ash-workflows/results/2026-09-10.md), including full answers, per-criterion grading and an application execution protocol.

The independent reasoning comparison tied at 39/40. The revised description selected AshOban in the description-only check where the baseline was uncertain; native Claude Code dispatch was not exercised. Frontmatter, manifests, local links, session-hook behavior and skill packaging passed. Application execution scenarios remain not run because this plugin repository has no application runtime.

Before final review, the branch incorporated upstream `f0915eb`, preserving its LiveView update. This changes the release version to `2.0.2`. The archived candidate inputs predate that inherited update, two sentence joins in the Pro reference, and the review clarification about queue isolation. The evaluation results distinguish those later edits from the frozen comparison. The two-round independent review corrected one queue-isolation ambiguity and ended with no remaining findings. Frontmatter, manifests, links, hooks, packaging and prose checks passed after the correction. DC-198 and the vault handoff track the reviewed branch and its integration status.
