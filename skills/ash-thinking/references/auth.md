# AshAuthentication Patterns

AshAuthentication integrates auth strategies directly into Ash resources. Identity and tokens are just actions and attributes.

## Password Strategy

```elixir
defmodule MyApp.Accounts.User do
  use Ash.Resource,
    extensions: [AshAuthentication]

  authentication do
    tokens do
      enabled? true
      token_resource MyApp.Accounts.Token
      signing_secret fn _, _ -> Application.fetch_env(:my_app, :token_signing_secret) end
    end

    strategies do
      password :password do
        identity_field :email
        hashed_password_field :hashed_password
      end
    end
  end
end
```

## Magic Link Strategy

```elixir
authentication do
  strategies do
    magic_link do
      identity_field :email
      sender fn user, token, _opts ->
        MyApp.Emails.send_magic_link(user.email, token)
      end
    end
  end
end
```

## OAuth2

```elixir
authentication do
  strategies do
    oauth2 :github do
      client_id fn _, _ -> System.fetch_env!("GITHUB_CLIENT_ID") end
      client_secret fn _, _ -> System.fetch_env!("GITHUB_CLIENT_SECRET") end
      authorize_url "https://github.com/login/oauth/authorize"
      token_url "https://github.com/login/oauth/access_token"
    end
  end
end
```

## Key Concepts

- **Token resource**: Separate Ash resource for token storage/revocation
- **Strategies compose**: A user can have password + OAuth + magic link simultaneously
- **`subject_name`**: Identifies the resource type in tokens (default: resource name)
- **Phoenix integration**: `AshAuthentication.Phoenix` provides LiveView components and plugs

## Gotchas

- Tokens are JWTs by default—revocation needs a token resource with `revocation? true`
- Magic link tokens expire (default 10 minutes, configurable)
- OAuth requires registering callback URLs with the provider
- `current_user` assign is set by `AshAuthentication.Plug` in the router pipeline
