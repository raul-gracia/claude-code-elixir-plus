---
name: ash-thinking
description: This skill should be used when the user asks to "create an Ash resource", "add policies", "define actions", "set up authentication", "use AshGraphql or AshJsonApi", or mentions Ash.Resource, Ash.Domain, code_interface, policies, aggregates, calculations, notifiers, or AshAuthentication. Essential for avoiding Phoenix-context-around-Ash anti-pattern.
---

# Ash Thinking

Mental shifts for building with the Ash Framework. These insights prevent the most common mistakes.

## The Iron Law

```
RESOURCES ARE THE API, NOT MODULES
```

The resource definition IS the contract. It declares what can be done (actions), who can do it (policies), what data exists (attributes), and how things relate (relationships). Don't write Phoenix contexts around Ash resources—the resource IS your context.

## Actions Replace Context Functions

**Traditional:** Write context modules with `create_user/1`, `update_user/2`.
**Ash:** Define actions on the resource. Call via code interface.

```elixir
# BAD: wrapping Ash in a context
defmodule MyApp.Accounts do
  def create_user(attrs), do: User.create!(attrs)
end

# GOOD: define actions + code interface on the resource
defmodule MyApp.Accounts.User do
  use Ash.Resource

  actions do
    defaults [:read]
    create :register do
      accept [:email, :name]
      change set_attribute(:role, :member)
    end
  end

  code_interface do
    define :register
  end
end

# Call directly
MyApp.Accounts.User.register!(attrs)
```

## Policies Are Declarative Authorization

Don't write middleware or plugs. Policies are composable gates checked inside Ash—no accidental bypasses.

```elixir
policies do
  policy action_type(:read) do
    authorize_if relates_to_actor_via(:user)
  end

  policy action(:destroy) do
    authorize_if actor_attribute_equals(:role, :admin)
  end
end
```

## Ash.Changeset ≠ Ecto.Changeset

Ash changesets are data transformation pipelines, not validation objects. They can add/remove attributes mid-action, run custom logic, and trigger notifications. Don't think "form validation"—think "data pipeline."

## Code Interfaces Are Not Optional

Code interfaces expose actions as functions—they're your app's public API and single source of truth.

```elixir
code_interface do
  define :register, args: [:email, :name]
  define :by_email, args: [:email], action: :read
  define :deactivate
end
```

Without them, callers must construct changesets manually—brittle and unidiomatic.

## Calculations and Aggregates Are Lazy

Don't load relationships to compute values in Elixir. Define calculations on the resource—loaded only when requested.

```elixir
calculations do
  calculate :full_name, :string, expr(first_name <> " " <> last_name)
end

aggregates do
  count :post_count, :posts
end
```

## Domains Group Resources

Ash.Domain replaces Phoenix contexts as the organizational boundary. A domain groups related resources and exposes them.

```elixir
defmodule MyApp.Accounts do
  use Ash.Domain

  resources do
    resource MyApp.Accounts.User
    resource MyApp.Accounts.Token
  end
end
```

## Gotchas

- **Pagination is opt-in**: Add `pagination offset?: true` to read actions explicitly
- **Notifiers fire after commit**: Expect notifications after the transaction, not during
- **Policies run per-record on reads**: Add filters to avoid N+1 authorization checks
- **Relationships are lazy**: Use `Ash.load!/2` or `load` in the action to populate them
- **`authorize?: false` skips ALL policies**: Use sparingly, typically only in seeds/migrations

## Red Flags - STOP and Reconsider

- Wrapping Ash resources in Phoenix context modules
- Bypassing policies with `authorize?: false` in production code
- Calling `Ash.create!/2` directly instead of via code interface
- Mixing Ecto changesets and Ash changesets in the same flow
- Resources with no code interface defined
- Policy checks that query the database (N+1 in authorization)

**Any of these? Re-read The Iron Law.**
