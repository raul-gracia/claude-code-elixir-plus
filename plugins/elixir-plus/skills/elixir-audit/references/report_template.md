# Audit Report Template

Two variants. Pick by mode (Step 1 of SKILL.md).

---

## Variant A — Orientation report (private notes, new codebase)

````markdown
# {{APP_NAME}} — Codebase Orientation

**Private notes.** Written for my own onboarding, not as a review of the team's work.

**Generated**: {{DATE}}
**Commit**: {{GIT_SHA}}
**Stack**: Elixir {{ELIXIR_VERSION}} / OTP {{OTP_VERSION}} {{(from .tool-versions / mise.toml / Dockerfile / CI, or "requirement only" from mix.exs)}} / {{Phoenix x.y, LiveView x.y, Ecto x.y, Ash x.y, Oban x.y}}
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

| Severity | Finding | Location | Note | Fix |
|---|---|---|---|---|

---

## 5. Questions for the tech lead

Short list. Things the code cannot answer and that I should not guess at.

1. {{...}}

---

## 6. Scope and method

- **Method**: source only — no Mix, no dependency fetch, no test run, no database.
- **Commit audited**: {{GIT_SHA}}; {{working tree clean | working tree had uncommitted changes, so this describes the files on disk, not HEAD | not a git checkout}}
- **Paths read**: {{...}}
- **Paths not read**: {{...}}
- **Existing tool output used**: {{e.g. `.credo.exs`, `.sobelow-skips`, `cover/excoveralls.json` (generated <date>, older than HEAD's commit date) | none}}
- **Judged from source only**: {{e.g. coverage (test-file mapping), dependency cycles, compile warnings, dependency CVEs}}
- **Commands to run yourself**: {{the commands from SKILL.md's "Source only" list whose output was not found}}
- **Not covered**: {{areas needing runtime access or production data}}
````

---

## Variant B — Review report (deliverable)

````markdown
# {{APP_NAME}} — Elixir Application Audit

**Generated**: {{DATE}}
**Commit**: {{GIT_SHA}}
**Elixir / OTP**: {{ELIXIR_VERSION}} / {{OTP_VERSION}} {{(source: .tool-versions / mise.toml / Dockerfile / CI, or "requirement only" from mix.exs)}}
**Stack**: {{Phoenix x.y, LiveView x.y, Ecto x.y, Ash x.y, Oban x.y}}
**Scope**: {{Full application | Targeted: paths}}

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

## 1. Security

### {{SEVERITY}}: {{Finding title}}

**Location**: `path/to/file.ex:NN`
**Category**: {{<category>, named as in the official anti-patterns guide or Sobelow's check list where one applies}}
**Checked against**: {{<package version and doc/source>, when the finding rests on a default or version behaviour; otherwise omit}}

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

{{Umbrella dependency direction (`in_umbrella` deps) and cross-context references read from source, plus modules `use`d/`import`ed across most of the app. Report what the source shows as `<finding>` entries with their evidence. Measured cycles and hotspots need `mix xref graph`; list it under "Commands to run yourself".}}

---

## 3. Testing

### Test posture

- **Modules with a test file**: X / Y (by mapping `lib/**/*.ex` to `test/**/*_test.exs`); X more exercised only through context- or integration-level tests
- **Test files**: X (X async, X sync — XX% async)
- **Coverage**: not measured by this audit. {{Cite an existing report with its age, or list `mix coveralls` under "Commands to run yourself".}}

**Modules reachable in production with no test at any level** (no own test file, and no context or integration test exercising them):

| Module | Lines | Why it matters |
|---|---|---|

## 4. Ecto & Data Layer

## 5. Process & OTP Design

## 6. Code Quality

{{Group by the pattern names used in the official Elixir anti-patterns guide (hexdocs.pm/elixir) so findings are searchable against it.}}

## 7. Phoenix Web Layer

### Router audit

| Scope | Pipeline | Auth plug | `live_session` / `on_mount` | OK? |
|---|---|---|---|---|

Live navigation within a `live_session` skips the plug pipeline, so LiveView authorization must come from `on_mount`/`mount`.

## 8. LiveView

## 9. Ash

## 10. External Services & Failure Handling

## 11. Build, Deps & Config

---

## Scope and method

- **Method**: source only — no Mix, no dependency fetch, no test run, no database.
- **Commit audited**: {{GIT_SHA}}; {{working tree clean | working tree had uncommitted changes, so this describes the files on disk, not HEAD | not a git checkout}}
- **Paths read**: {{...}}
- **Paths not read**: {{...}}
- **Existing tool output used**: {{e.g. `.credo.exs`, `.sobelow-skips`, `cover/excoveralls.json` (generated <date>, older than HEAD's commit date) | none}}
- **Judged from source only**: {{e.g. coverage (test-file mapping), dependency cycles, compile warnings, dependency CVEs}}
- **Commands to run yourself**: {{the commands from SKILL.md's "Source only" list whose output was not found}}
- **Not covered**: {{areas needing runtime access or production data}}

{{Be explicit about what was not read and what was judged without a tool. An audit that does not state its blind spots invites false confidence.}}
````

---

## Rules for both variants

- Every finding carries `file.ex:NN`. No location, no finding — except a project-level finding (e.g. "no CI step runs the test suite"), which cites the evidence instead: the file whose content or absence shows it.
- "Why it matters **here**" must reference this codebase, not a general principle. If the consequence cannot be stated concretely, the finding is Low at best.
- Show the fix as code, not prose, whenever the fix is under ~10 lines.
- Do not pad the count. Twelve verified findings beat sixty unverified ones, and the reader will check the first three.
- Unverified tool output is not a finding. When the team's existing scanner output is used, read the code before reporting anything it lists.
