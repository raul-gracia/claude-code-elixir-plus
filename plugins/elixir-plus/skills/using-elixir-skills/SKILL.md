---
name: using-elixir-skills
description: Auto-triggers when the user works on .ex/.exs files, mentions Elixir/Phoenix/Ecto/OTP, the project has mix.exs, or asks "which skill should I use". Routes to the correct thinking skill BEFORE code exploration. Do NOT invoke this alongside another elixir skill — it's a router, not content.
---

Invoke the relevant skill BEFORE exploring code or writing any Elixir.

## Tidewave MCP Server

**Before routing to a skill, check if Tidewave MCP tools are available** (look for tools like `project_eval`, `get_docs`, `get_logs`, `execute_sql_query` in your MCP tool list).

**If Tidewave tools are available:** Every skill below assumes you will use them as your PRIMARY way to explore and interact with the codebase. Prefer Tidewave tools over file reads and grep for:
- Documentation lookup → `get_docs` / `search_package_docs`
- Finding source code → `get_source_location`
- Testing code → `project_eval`
- Database queries → `execute_sql_query`
- Debugging → `get_logs` + `project_eval`
- Schema discovery → `get_ecto_schemas` / `get_ash_resources`

**If Tidewave tools are NOT available:** Suggest the user install it:

```sh
# With Igniter (recommended - auto-configures endpoint)
mix igniter.install tidewave

# Then connect Claude Code to the MCP server
claude mcp add --transport http tidewave http://localhost:4000/tidewave/mcp
```

Tidewave is a dev-only dependency (`only: :dev`) that gives you runtime access to the running Phoenix app — documentation, database, logs, code evaluation, and schema introspection. It replaces the need for separate tools and web searches for library docs.

## Skill Triggers

| Trigger | Skill |
|---------|-------|
| Code, architecture, patterns, structs, protocols | `elixir-thinking` |
| Deciding whether to use GenServer/process vs plain module/functions | `elixir-thinking` |
| LiveView, PubSub, mount, socket, component, route | `phoenix-thinking` |
| Context, schema, Ecto, changeset, Repo, migration | `ecto-thinking` |
| GenServer, Supervisor, Task, ETS, Broadway (implementation) | `otp-thinking` |
| Choosing between Broadway vs Oban | `otp-thinking` |
| Oban, job queue, background job, async processing | `oban-thinking` |
| Ash resource, domain, policies, actions, code interface | `ash-thinking` |

## Disambiguation

- **"Should I use a GenServer or just a module?"** → `elixir-thinking` (process decision), NOT `otp-thinking`
- **"Should I use Broadway or Oban?"** → `otp-thinking` (infrastructure choice), NOT `oban-thinking`
- **"Ecto changeset in a LiveView form"** → `phoenix-thinking` (outer framework), NOT `ecto-thinking`
