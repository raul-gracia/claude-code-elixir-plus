---
name: using-elixir-skills
description: This skill should be used when the user works on any .ex or .exs file, mentions Elixir/Phoenix/Ecto/OTP, the project has a mix.exs, or asks "which skill should I use", "new to Elixir", "help with Elixir". Routes to the correct thinking skill BEFORE exploring code. Triggers on "implement", "add", "fix", "refactor" in Elixir projects.
---

Invoke the relevant skill BEFORE exploring code or writing any Elixir.

## Skill Triggers

| Trigger | Skill |
|---------|-------|
| Code, architecture, patterns, structs, protocols | `elixir-thinking` |
| LiveView, PubSub, mount, socket, component, route | `phoenix-thinking` |
| Context, schema, Ecto, changeset, Repo, migration | `ecto-thinking` |
| GenServer, Supervisor, Task, ETS, Broadway | `otp-thinking` |
| Oban, job queue, background job, async processing | `oban-thinking` |
| Ash resource, domain, policies, actions, code interface | `ash-thinking` |
