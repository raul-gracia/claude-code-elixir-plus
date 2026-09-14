# Audit Report Template

Two variants. Pick by mode (Step 1 of SKILL.md).

---

## Variant A — Orientation report (private notes, new codebase)

```markdown
# {{APP_NAME}} — Codebase Orientation

**Private notes.** Written for my own onboarding, not as a review of the team's work.

**Generated**: {{DATE}}
**Commit**: {{GIT_SHA}}
**Stack**: Elixir {{ELIXIR_VERSION}} / OTP {{OTP_VERSION}} / {{Phoenix x.y, LiveView x.y, Ecto x.y, Ash x.y, Oban x.y}}
**Shape**: {{single app | umbrella with N apps}}, {{N}} modules, {{N}} test files

---

## 1. How this app is put together

{{Two or three paragraphs: what the app does, the main layers, where a request enters and what it touches on the way through.}}

### Supervision tree

{{Annotated list from application.ex — what each child is for, which ones are singletons, which hold state.}}

### Contexts / domains

| Context | Responsibility | Key modules | Notes |
|---|---|---|---|

### Request path

{{Endpoint → router pipeline → controller/LiveView → context → Repo. Note where it deviates.}}

---

## 2. Conventions to follow in my first PRs

The house style, inferred from the code rather than from docs:

- **Naming**: {{...}}
- **Error handling**: {{tagged tuples vs raising, where `with` is used}}
- **Testing**: {{framework choices, factory style, async rate, what a typical test looks like}}
- **Where new code goes**: {{for the kind of work I'll be doing}}
- **Review load**: {{typical PR size in git history, what reviewers comment on}}

### The closest existing example to my first task

{{path/to/file.ex — the file to copy the shape of.}}

---

## 3. Things that will trip me up

Ordered by how likely I am to hit them in week one.

| # | Thing | Where | Why it bites |
|---|---|---|---|

---

## 4. Risks I can see (not raising yet)

Things worth knowing, to bring up only if asked or if one blocks a task. Each has file:line so I can point at it if it comes up.

| Severity | Finding | Location | Note |
|---|---|---|---|

---

## 5. Questions for the tech lead

Short list. Things the code cannot answer and that I should not guess at.

1. {{...}}
```

---

## Variant B — Review report (deliverable)

```markdown
# {{APP_NAME}} — Elixir Application Audit

**Generated**: {{DATE}}
**Commit**: {{GIT_SHA}}
**Elixir / OTP**: {{ELIXIR_VERSION}} / {{OTP_VERSION}}
**Stack**: {{Phoenix x.y, LiveView x.y, Ecto x.y, Ash x.y, Oban x.y}}
**Scope**: {{Full application | Targeted: paths}}
**Metrics collected**: {{Coverage / Static analysis / Security scan / none}}

---

## Executive Summary

| Category | Critical | High | Medium | Low | Total |
|----------|----------|------|--------|-----|-------|
| Security | | | | | |
| Architecture & Boundaries | | | | | |
| Testing | | | | | |
| Ecto & Data Layer | | | | | |
| Process & OTP Design | | | | | |
| Code Quality | | | | | |
| Phoenix Web Layer | | | | | |
| LiveView | | | | | |
| Ash | | | | | |
| External Services | | | | | |
| Build, Deps & Config | | | | | |
| **Total** | | | | | |

### Top findings

1. **{{Most critical}}** — `{{file.ex:NN}}`
2. **{{Second}}** — `{{file.ex:NN}}`
3. **{{Third}}** — `{{file.ex:NN}}`

### What I would fix first

{{Three to five items in order, with rough effort. This is the section people actually act on.}}

---

## Metrics

### Coverage

**When ExCoveralls data was collected:**

- **Overall line coverage**: XX.X%
- **Modules with tests**: X / Y
- **Test files**: X (X async, X sync — XX% async)

| Directory | Modules | Coverage | Note |
|---|---|---|---|
| lib/{{app}}/ | X / Y | XX.X% | |
| lib/{{app}}_web/ | X / Y | XX.X% | |

**Zero-coverage modules reachable in production:**

| Module | Lines | Why it matters |
|---|---|---|

**When coverage was not collected**: state that, give the test-file-to-module ratio and the async rate instead, and say explicitly that coverage figures are absent rather than estimated.

### Static analysis

**When Credo/Dialyzer data was collected:**

| Credo category | Count |
|---|---|
| Warnings | |
| Refactoring opportunities | |
| Software design | |
| Readability | |
| Consistency | |

| Dialyzer finding type | Count |
|---|---|

**When not collected**: omit this section.

### Security scan

**When Sobelow / deps.audit data was collected:**

| Tool | High | Medium | Low |
|---|---|---|---|
| Sobelow | | | |

| Dependency | Current | CVE / status |
|---|---|---|

Note which Sobelow findings were manually verified and which were dismissed as false positives, with reasons.

**When not collected**: omit this section.

---

## 1. Security

### {{SEVERITY}}: {{Finding title}}

**Location**: `path/to/file.ex:NN`
**Category**: {{e.g. Atom exhaustion}}

**What**: {{one or two sentences}}

```elixir
# current
{{code}}
```

**Why it matters here**: {{concrete consequence in this codebase — which endpoint, which data, what an attacker or a load spike does with it}}

**Fix**:

```elixir
# suggested
{{code}}
```

**Effort**: {{trivial | small | medium | large}}

---

## 2. Architecture & Boundaries

{{Same finding format.}}

### Dependency graph

{{Cycles from `mix xref graph --format cycles`, and compile-connected hotspots. Each cycle is a finding.}}

---

## 3. Testing

## 4. Ecto & Data Layer

## 5. Process & OTP Design

## 6. Code Quality

{{Group by the anti-pattern names from elixir_antipatterns.md so findings are searchable against the official docs.}}

## 7. Phoenix Web Layer

### Router audit

| Scope | Pipeline | Auth plug | OK? |
|---|---|---|---|

## 8. LiveView

## 9. Ash

## 10. External Services & Failure Handling

## 11. Build, Deps & Config

---

## Appendix: what was not covered

{{Be explicit. Paths not read, tools that failed and why, areas needing runtime access or production data to assess. An audit that does not state its blind spots invites false confidence.}}
```

---

## Rules for both variants

- Every finding carries `file.ex:NN`. No location, no finding.
- "Why it matters **here**" must reference this codebase, not a general principle. If the consequence cannot be stated concretely, the finding is Low at best.
- Show the fix as code, not prose, whenever the fix is under ~10 lines.
- Do not pad the count. Twelve verified findings beat sixty unverified ones, and the reader will check the first three.
- Unverified tool output is not a finding. Read the code before reporting anything a scanner produced.
