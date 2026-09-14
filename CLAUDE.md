# CLAUDE.md

Agent-facing guide for working in this repo. README.md is user-facing; this file captures conventions and gotchas you need before editing.

## What this repo is

A Claude Code plugin marketplace publishing one plugin (`elixir-plus`) with two skills (`elixir-runtime`, `elixir-audit`), six hooks, and ElixirLS integration for Elixir/Phoenix/Ash work. Auto-installed via `claude plugins install elixir-plus@claude-code-elixir-plus`. Sister repo: `claude-code-raul-skills` (everything non-Elixir) at `~/Code/claude-code-raul-skills/`.

Scope is strictly the Elixir ecosystem, and deliberately thin. General Elixir/OTP/Phoenix/Ecto/Ash pedagogy lives in the model's training data, so this plugin does not restate it. Two things do earn a place here:

1. **Durable non-training-data payload** — the Tidewave MCP runtime grant, the closed-source Oban Pro reference, the AshOban workflow procedure (domain-state recovery, execution identity, versioned operational facts; behavioral evaluations under `evals/ash-workflows/`), and version-gated facts (each with a sunset note). Keep the capability entrypoint small, route framework details to installed-version documentation, and load specialized references only when relevant. This is `elixir-runtime`.
2. **Repeatable workflows** — a defined execution order, stack-gated review questions, and an output shape, so the same task produces the same passes every time. Knowing the material is not the same as running a consistent procedure over it. This is `elixir-audit`.

A new skill must clear one of those two bars. Restating what the model already knows clears neither.

Anything broader (Ruby, fullstack, deployment via Kamal, infra, business strategy) goes in the sister repo. Elixir-specific skills live here even when a same-shaped sibling exists there — `elixir-audit` mirrors the sister repo's `rg-rails-audit` in structure, but the language rule wins over the family rule.

## Repo layout

```
.claude-plugin/marketplace.json   marketplace manifest (one entry: elixir-plus)
plugins/elixir-plus/
  .claude-plugin/plugin.json      plugin manifest (name + version drive plugin manager)
  hooks/                          shell hooks: session-start, format, compile, credo, block-dangerous-ops, error-critic
  skills/<skill-name>/
    SKILL.md                      skill content; frontmatter name MUST equal dir name
    references/*.md               progressive-disclosure deep-dives
README.md                         user-facing
EVAL_PLAN.md                      plugin evaluation methodology (legacy, kept for reference)
evals/ash-workflows/              current behavioral evaluation prompts, rubric and evidence
plans/                           approved implementation plans and completion evidence
```

## Naming convention (HARD RULES)

### Skills are NOT prefixed

Unlike the sister repo (`claude-code-raul-skills`), skills here have no prefix. The directory is `elixir-runtime`. Frontmatter `name:` matches the directory exactly. Do not add prefixes.

### Plugin manifest names (the bug that broke updates in April 2026)

There are three places a "name" appears in this repo. They must align like this:

| File | Field | Correct value | Why |
|---|---|---|---|
| `.claude-plugin/marketplace.json` | top-level `name` | `claude-code-elixir-plus` | marketplace name, with `claude-code-` prefix |
| `.claude-plugin/marketplace.json` | `plugins[0].name` | `elixir-plus` | plugin name, no prefix |
| `plugins/elixir-plus/.claude-plugin/plugin.json` | `name` | `elixir-plus` | MUST match `marketplace.json` `plugins[0].name` and the directory name |
| Directory | `plugins/elixir-plus/` | `elixir-plus` | matches plugin manifest |

The `claude-code-` prefix belongs only on the marketplace. If `plugin.json` `name` carries it, the plugin manager's "update" lookup queries `marketplace.json` for a plugin named `claude-code-elixir-plus` (which doesn't exist there) and fails with `Plugin claude-code-elixir-plus not found in marketplace`. Fixed in commit `e1a9070`.

### Triggering plugin manager updates

The plugin manager only re-fetches when `plugins/elixir-plus/.claude-plugin/plugin.json` `version` changes. After any user-visible change (new skill, hook fix, content edit), bump that version. The `marketplace.json` `metadata.version` is decorative; the plugin's own `version` is what installed clients compare.

Semver: bump major for breaking changes, minor for new skills/hooks, patch for content fixes.

## Skills

One capability skill: `elixir-runtime`. It is auto-injected via the `SessionStart` hook when `mix.exs` exists, and also supports native selection for Elixir/Phoenix and Ash/AshOban tasks via its `description`. It carries:

- The Tidewave MCP capability table + "prefer runtime introspection over grep" guidance + install one-liner.
- Version-gated facts (Elixir 1.18 JSON, Phoenix 1.8 scopes, Ecto 3.12 `Repo.transact`, OTP 24 sets/`:pg`), each with an explicit sunset annotation so they get deleted once models train past them.
- A pointer to the Oban Pro reference (closed-source, genuinely under-represented in training data).
- Installed-version Ash documentation routing and resource/trigger introspection pointers.
- A conditional AshOban workflow reference covering reconstruction, identity and operational traps, with a separate behavioral evaluation suite.

Keep general Elixir/OTP/Phoenix/Ecto/Ash tutorials upstream. The AshOban reference is the specifically approved workflow scope from DC-198; preserve contextual choices such as ordinary workers for temporary imports. New guidance must justify its context cost with a capability, a verified compatibility issue or evaluated behavior. Retain source versions and concrete revisit conditions for operational facts.

One workflow skill: `elixir-audit`. It is invoked explicitly (`/elixir-audit`, optionally with a path for a targeted pass) and is never injected by a hook. `SKILL.md` holds the execution order, the questions to answer per section (stack-specific sections gated on the stack detected from `mix.lock` plus each app's `mix.exs`), the severity rubric and the output shape; its only bundled reference is `references/report_template.md`. It restates no API or default facts: it points the auditor to primary sources (the official Elixir anti-patterns guide, Sobelow's check list, the installed versions' hexdocs or `deps/` source) and conditionally loads `elixir-runtime`'s `ash-oban.md` and `oban-pro.md`. It is a source-reading audit: it never runs Mix, the test suite or a database, reads existing tool output when the repo has it, and lists the commands the user can run for measured metrics. Keep it a procedure: new content must change what the audit does or reports, not restate framework knowledge; do not add fact checklists back.

Reference docs live in `skills/<skill>/references/*.md` and are linked from `SKILL.md` for conditional loading. `elixir-runtime`'s references are `ash-oban.md`, `oban-pro.md` and `performance.md`; `elixir-audit`'s only reference is `report_template.md`. Keep Pro chunk mechanics in `oban-pro.md`. `performance.md` holds only measured findings with their source and revisit conditions.

## Hooks

Six hooks ship with the plugin, registered via `hooks/hooks.json`:

| Hook | Event | Path | Purpose |
|---|---|---|---|
| `session-start.sh` | `SessionStart` | `hooks/session-start.sh` | Inject `elixir-runtime` skill when `mix.exs` exists |
| `format-elixir.sh` | `PostToolUse` (Edit/Write) | `hooks/format-elixir.sh` | Run `mix format` on changed `.ex`/`.exs` |
| `compile-elixir.sh` | `PostToolUse` (Edit/Write) | `hooks/compile-elixir.sh` | Run `mix compile --warnings-as-errors` (skips `.exs`) |
| `credo-elixir.sh` | `PreToolUse` (commit) | `hooks/credo-elixir.sh` | Run `mix credo`; block commit on issues |

The other two are guardrails: `block-dangerous-ops.sh` (`PreToolUse` Bash) and `error-critic.sh` (`PostToolUseFailure`); see README.md "Guardrail hooks".

All hooks walk up from the edited file to find `mix.exs`, so umbrella apps and nested project structures work without configuration. The credo hook silently skips when credo is not installed in the target project.

When editing hooks: keep them fast (timeouts in `plugin.json`: 15s format, 60s compile, 30s credo). Failing hooks block real user work. Test changes in a real `mix.exs` project before committing.

## LSP

`plugin.json` registers ElixirLS for `.ex`, `.exs`, `.heex`, `.leex` extensions:
- `dialyzerEnabled: true`
- `fetchDeps: false` (plugin does not auto-run `mix deps.get`)
- `suggestSpecs: true`

Requires `elixir-ls` on PATH. The plugin does not bundle the binary.

## Adding a new skill

Only add a skill if it clears one of the two bars in "What this repo is": durable non-training-data payload (a capability/tool grant, a closed-source library reference, or a version fact with a sunset note) or a repeatable workflow (defined execution order, review questions, output shape) — NOT general pedagogy the model already knows.

1. `mkdir plugins/elixir-plus/skills/<name>/` (no `rg-` prefix)
2. Write `SKILL.md` with frontmatter:
   ```yaml
   ---
   name: <name>
   description: <Use when... triggers...>
   ---
   ```
3. If the skill needs deep-dive content, put it in `skills/<name>/references/*.md` and link it from `SKILL.md`.
4. Add a row to `README.md`.
5. Bump `plugins/elixir-plus/.claude-plugin/plugin.json` `version`.
6. Commit + push.

The `description` field drives native skill dispatch — the model reads it to decide when the skill applies, so no hand-coded router is needed. Be specific about the file extensions, module patterns, and Elixir-version features that make it relevant.

## Commit conventions

- Imperative subject ("Add X", "Fix Y", "Bump Z"), no Co-Authored-By lines (per user preference).
- One logical change per commit.
- For skill content edits, bump `plugin.json` `version` in the same commit so installed clients pick up the change on next update.

## Sister repo

When the user mentions Kamal, Hetzner, Ruby, fullstack JS/TS, business strategy, marketing, design, or humanizer skills, those live in `~/Code/claude-code-raul-skills/` and follow a different convention (all skills are `rg-` prefixed). Do not duplicate skills across the two repos.
