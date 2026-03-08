---
name: using-elixir-skills
description: Auto-triggers when the user works on .ex/.exs files, mentions Elixir/Phoenix/Ecto/OTP, the project has mix.exs, or asks "which skill should I use". Routes to the correct thinking skill BEFORE code exploration. Do NOT invoke this alongside another elixir skill — it's a router, not content.
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
