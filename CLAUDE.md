# CLAUDE.md

Agent-facing guide for working in this repo. README.md is user-facing; this file captures conventions and gotchas you need before editing.

## What this repo is

A Claude Code plugin marketplace publishing one plugin (`elixir-plus`) with seven thinking skills, four hooks, and ElixirLS integration for Elixir/Phoenix/Ash work. Auto-installed via `claude plugins install elixir-plus@claude-code-elixir-plus`. Sister repo: `claude-code-raul-skills` (everything non-Elixir) at `~/Code/claude-code-raul-skills/`.

Scope is strictly Elixir ecosystem: Elixir, Phoenix, Ecto, OTP, Oban, Ash, plus a router. Anything broader (Ruby, fullstack, deployment via Kamal, infra, business strategy) goes in the sister repo.

## Repo layout

```
.claude-plugin/marketplace.json   marketplace manifest (one entry: elixir-plus)
plugins/elixir-plus/
  .claude-plugin/plugin.json      plugin manifest (name + version drive plugin manager)
  hooks/                          shell hooks: session-start, format, compile, credo
  skills/<skill-name>/
    SKILL.md                      skill content; frontmatter name MUST equal dir name
    references/*.md               progressive-disclosure deep-dives
README.md                         user-facing
EVAL_PLAN.md                      plugin evaluation methodology (legacy, kept for reference)
```

## Naming convention (HARD RULES)

### Skills are NOT prefixed

Unlike the sister repo (`claude-code-raul-skills`), skills here have no prefix. Directories are `elixir-thinking`, `phoenix-thinking`, etc. Frontmatter `name:` matches the directory exactly. Do not add prefixes.

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

The seven skills follow a router + domain-skills pattern:

- `using-elixir-skills` — router, auto-injected via `SessionStart` hook when `mix.exs` exists. Edits to its routing table affect every other skill's discoverability.
- `elixir-thinking`, `phoenix-thinking`, `ecto-thinking`, `otp-thinking`, `oban-thinking`, `ash-thinking` — domain skills. Each has Iron Laws (non-negotiable rules), paradigm shifts, and gotchas distilled from core team guidance.

Reference docs live in `skills/<skill>/references/*.md` for content too deep for upfront load. Examples: `elixir-thinking/references/performance.md`, `oban-thinking/references/oban-pro.md`. Reference them from `SKILL.md` so they load on demand.

## Hooks

Four hooks ship with the plugin, registered via `plugin.json`:

| Hook | Event | Path | Purpose |
|---|---|---|---|
| `session-start.sh` | `SessionStart` | `hooks/session-start.sh` | Inject `using-elixir-skills` routing table when `mix.exs` exists |
| `format-elixir.sh` | `PostToolUse` (Edit/Write) | `hooks/format-elixir.sh` | Run `mix format` on changed `.ex`/`.exs` |
| `compile-elixir.sh` | `PostToolUse` (Edit/Write) | `hooks/compile-elixir.sh` | Run `mix compile --warnings-as-errors` (skips `.exs`) |
| `credo-elixir.sh` | `PreToolUse` (commit) | `hooks/credo-elixir.sh` | Run `mix credo`; block commit on issues |

All hooks walk up from the edited file to find `mix.exs`, so umbrella apps and nested project structures work without configuration. The credo hook silently skips when credo is not installed in the target project.

When editing hooks: keep them fast (timeouts in `plugin.json`: 15s format, 60s compile, 30s credo). Failing hooks block real user work. Test changes in a real `mix.exs` project before committing.

## LSP

`plugin.json` registers ElixirLS for `.ex`, `.exs`, `.heex`, `.leex` extensions:
- `dialyzerEnabled: true`
- `fetchDeps: false` (plugin does not auto-run `mix deps.get`)
- `suggestSpecs: true`

Requires `elixir-ls` on PATH. The plugin does not bundle the binary.

## Adding a new skill

1. `mkdir plugins/elixir-plus/skills/<name>-thinking/` (suffix `-thinking` for consistency, no `rg-` prefix)
2. Write `SKILL.md` with frontmatter:
   ```yaml
   ---
   name: <name>-thinking
   description: <Use when... triggers... Do NOT use for...>
   ---
   ```
3. Update `using-elixir-skills/SKILL.md` routing table to dispatch to the new skill on the right keywords.
4. If the skill needs deep-dive content, put it in `skills/<name>-thinking/references/*.md`.
5. Add a row to `README.md`.
6. Bump `plugins/elixir-plus/.claude-plugin/plugin.json` `version`.
7. Commit + push.

The `description` field drives router dispatch. Be specific about Elixir-version features (e.g. Ash 3.x), the file extensions and module patterns that trigger it, and what to defer to other skills. The router uses negative routing too ("Do NOT use for X — use Y") to prevent overlap.

## Commit conventions

- Imperative subject ("Add X", "Fix Y", "Bump Z"), no Co-Authored-By lines (per user preference).
- One logical change per commit.
- For skill content edits, bump `plugin.json` `version` in the same commit so installed clients pick up the change on next update.

## Sister repo

When the user mentions Kamal, Hetzner, Ruby, fullstack JS/TS, business strategy, marketing, design, or humanizer skills, those live in `~/Code/claude-code-raul-skills/` and follow a different convention (all skills are `rg-` prefixed). Do not duplicate skills across the two repos.
