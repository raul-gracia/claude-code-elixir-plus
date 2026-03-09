# claude-code-elixir-plus

A Claude Code plugin that gives Claude deep, opinionated knowledge of Elixir, Phoenix, Ecto, OTP, Oban, and Ash Framework. It bundles seven thinking skills (loaded on demand), four automated hooks (format, compile, credo, session context injection), and ElixirLS integration. The skills encode Iron Laws, paradigm shifts, and gotchas distilled from core team guidance -- things Claude doesn't reliably know on its own.

## Installation

```bash
# Add from marketplace
claude plugin add claude-code-elixir-plus

# Or install from source
claude plugin install /path/to/claude-code-elixir-plus
```

## Skills

The plugin ships with a **router skill** (`using-elixir-skills`) and six **domain skills**. The router auto-triggers whenever you work on `.ex`/`.exs` files or mention Elixir topics, and dispatches to the correct domain skill before any code is written.

| Skill | Triggers When You... | Covers |
|-------|---------------------|--------|
| `using-elixir-skills` | Open/edit `.ex`/`.exs` files, mention Elixir/Phoenix/Ecto/OTP, or project has `mix.exs` | Routes to the correct thinking skill. Do not invoke alongside another skill. |
| `elixir-thinking` | Ask about modules, structs, protocols, pattern matching, error handling, testing, or "should I use a GenServer?" | Iron Law: no process without a runtime reason. OOP-to-FP paradigm shifts, the three decoupled dimensions, performance tuning (BEAM VM, binaries, iodata). |
| `phoenix-thinking` | Work with LiveView, PubSub, components, routes, controllers, sockets | Iron Law: no database queries in mount. Mount-is-called-twice gotcha, handle_params for data loading, endpoint/Bandit tuning. |
| `ecto-thinking` | Work with schemas, changesets, migrations, Repo, contexts, Ecto.Multi | Context-as-bounded-context design, cross-context references by ID not association, DDD patterns as pipelines. |
| `otp-thinking` | Work with GenServer, Supervisor, Task, ETS, Broadway, or ask "Broadway vs Oban?" | Iron Law: GenServer is a bottleneck by design. ETS read-bypass pattern, supervision tree design, scheduler tuning. |
| `oban-thinking` | Work with Oban jobs, retries, unique jobs, scheduling | Iron Law: job args are JSON (atoms become strings). Idempotency patterns, queue configuration. |
| `ash-thinking` | Work with Ash.Resource, Ash.Domain, actions, policies, code_interface | Iron Law: resources are the API, not modules. Actions replace context functions, policy design. |

### Reference files

Some skills include supplementary reference docs loaded when deeper context is needed:

| File | Lines | Skill |
|------|-------|-------|
| `elixir-thinking/references/performance.md` | 251 | BEAM VM performance, memory, GC, binary handling |
| `phoenix-thinking/references/performance.md` | 290 | Endpoint tuning, Bandit/Cowboy config, socket optimization |
| `otp-thinking/references/performance.md` | 264 | Process bottleneck diagnosis, scheduler tuning, ETS optimization |
| `oban-thinking/references/oban-pro.md` | 168 | Oban Pro workflows, batches, cascades |
| `ash-thinking/references/auth.md` | 71 | AshAuthentication patterns |

### How the router works

`using-elixir-skills` is injected into every session via the `SessionStart` hook (when `mix.exs` exists in the working directory). It acts as a dispatch table: when you mention a topic, Claude consults the routing table and invokes the matching domain skill *before* exploring code or writing anything. Disambiguation rules handle overlapping concerns (e.g., "Ecto changeset in a LiveView form" routes to `phoenix-thinking`, not `ecto-thinking`).

## Hooks

Four hooks run automatically -- no configuration needed after install.

| Hook | Event | Fires When | What It Does | Timeout |
|------|-------|------------|-------------|---------|
| `session-start.sh` | `SessionStart` | Session starts, resumes, clears, or compacts | Injects the `using-elixir-skills` routing table into context (only if `mix.exs` exists) | default |
| `format-elixir.sh` | `PostToolUse` (Edit/Write) | After any file edit or write | Runs `mix format` on the changed `.ex`/`.exs` file | 15s |
| `compile-elixir.sh` | `PostToolUse` (Edit/Write) | After any file edit or write | Runs `mix compile --warnings-as-errors` on changed `.ex` files (skips `.exs`) | 60s |
| `credo-elixir.sh` | `PreToolUse` (Commit) | Before a git commit | Runs `mix credo` on the file; blocks commit if issues found | 30s |

All hooks walk up from the edited file to find `mix.exs`, so they work in umbrella apps and nested project structures. The credo hook silently skips if credo is not installed in the project.

## LSP

The plugin configures ElixirLS as the language server for `.ex`, `.exs`, `.heex`, and `.leex` files:

- **Dialyzer**: enabled
- **Fetch deps**: disabled (does not auto-run `mix deps.get`)
- **Suggest specs**: enabled

ElixirLS must be installed and available on your PATH as `elixir-ls`.

## Updating

```bash
claude plugin update claude-code-elixir-plus
```

## License

MIT
