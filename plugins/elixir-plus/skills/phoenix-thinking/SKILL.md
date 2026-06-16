---
name: phoenix-thinking
description: Use when the user works with Phoenix Framework, LiveView, or asks about mount lifecycle, handle_event, handle_params, PubSub, channels, controllers, routes, components, sockets, assigns, key comprehensions, colocated hooks/CSS, JS commands, endpoint tuning, Bandit/Cowboy configuration, or plug pipeline performance. Covers LiveView gotchas like duplicate mount queries. Do NOT use for pure Ecto/database questions (use ecto-thinking) or Ash resources (use ash-thinking).
---

# Phoenix Thinking

Mental shifts for Phoenix applications. These insights challenge typical web framework patterns.

## Tidewave MCP: Your Runtime Connection

If Tidewave MCP tools are available, **they are your primary interface to the running Phoenix app**. Use them before file reads, grep, or web searches.

| Task | Tidewave Tool | Why |
|------|--------------|-----|
| Find a module/function definition | `get_source_location` | Returns exact file + line. Faster than grep, handles deps too |
| Read Phoenix/library docs | `get_docs` | Your exact dependency versions, not stale web results |
| Search dependency documentation | `search_package_docs` | Searches hexdocs filtered to your mix.lock deps |
| Test a function or pipe chain | `project_eval` | Runs in your app's context with all deps, configs, and IEx helpers |
| Debug a request/error | `get_logs` | Server logs with level/grep filtering. Excludes tool-caused logs |
| Query the database | `execute_sql_query` | Runs SQL through your Ecto repos. Safer than manual psql |
| Discover schemas | `get_ecto_schemas` | Lists all Ecto schema modules and file paths |
| Discover Ash resources | `get_ash_resources` | Lists all Ash domains and their resources (if Ash is loaded) |

**Workflow:** When debugging a Phoenix issue, start with `get_logs` to see what happened, use `project_eval` to test hypotheses in the running app, and `execute_sql_query` to verify data state — all without restarting or writing throwaway scripts.

**Not installed?** → `mix igniter.install tidewave` then `claude mcp add --transport http tidewave http://localhost:4000/tidewave/mcp`

## The Iron Law

```
NO DATABASE QUERIES IN MOUNT
```

mount/3 is called TWICE (HTTP request + WebSocket connection). Queries in mount = duplicate queries.

```elixir
def mount(_params, _session, socket) do
  # NO database queries here! Called twice.
  {:ok, assign(socket, posts: [], loading: true)}
end

def handle_params(params, _uri, socket) do
  # Database queries here - once per navigation
  posts = Blog.list_posts(socket.assigns.scope)
  {:noreply, assign(socket, posts: posts, loading: false)}
end
```

**mount/3** = setup only (empty assigns, subscriptions, defaults)
**handle_params/3** = data loading (all database queries, URL-driven state)

**No exceptions:** Don't query "just this one small thing" in mount. Don't "optimize later". LiveView lifecycle is non-negotiable.

## Scopes: Security-First Pattern (Phoenix 1.8+)

Scopes address OWASP #1 vulnerability: Broken Access Control. Authorization context is threaded automatically—no more forgetting to scope queries.

```elixir
def list_posts(%Scope{user: user}) do
  Post |> where(user_id: ^user.id) |> Repo.all()
end
```

## PubSub Topics Must Be Scoped

```elixir
def subscribe(%Scope{organization: org}) do
  Phoenix.PubSub.subscribe(@pubsub, "posts:org:#{org.id}")
end
```

Unscoped topics = data leaks between tenants.

## External Polling: GenServer, Not LiveView

**Bad:** Every connected user makes API calls (multiplied by users).
**Good:** Single GenServer polls, broadcasts to all via PubSub.

## Components Receive Data, LiveViews Own Data

- **Functional components:** Display-only, no internal state
- **LiveComponents:** Own state, handle own events
- **LiveViews:** Full page, owns URL, top-level state

## Async Data Loading

Use `assign_async/3` for data that can load after mount:

```elixir
def mount(_params, _session, socket) do
  {:ok, assign_async(socket, :user, fn -> {:ok, %{user: fetch_user()}} end)}
end
```

## Gotchas from Core Team

### assign_new Goes Stale on Reconnect

`assign_new/3` skips its function if the key already exists in assigns. On LiveView reconnect (the second mount over the WebSocket), prior assigns may still be present—so locale, `current_user`, timezone, or any per-mount state silently goes STALE.

```elixir
# BAD: current_user frozen from the dead render, never refreshed on reconnect
assign_new(socket, :current_user, fn -> Accounts.get_user!(user_id) end)

# GOOD: re-derived fresh on every mount
assign(socket, :current_user, Accounts.get_user!(user_id))
```

**Rule:** Use `assign/3` for anything derived fresh per mount. Reserve `assign_new` only for values intentionally carried across the dead→live render that don't change.

### Authorize in EVERY handle_event, Not Just mount

Mount-level auth doesn't protect events—a client can push any event over the socket regardless of what mount rendered. Re-check authorization (via the scope/`current_user`) inside every `handle_event` that mutates or reveals data.

```elixir
def handle_event("delete", %{"id" => id}, socket) do
  post = Blog.get_post!(socket.assigns.scope, id)  # scoped fetch
  if post.user_id == socket.assigns.current_user.id do
    Blog.delete_post(post)
    {:noreply, stream_delete(socket, :posts, post)}
  else
    {:noreply, put_flash(socket, :error, "Not authorized")}
  end
end
```

### raw/1 on Untrusted Content = XSS

`raw/1` / `{:safe, ...}` bypasses HEEx's automatic HTML escaping. Rendering user-supplied strings through it is stored/reflected XSS. Sanitize first (e.g. `HtmlSanitizeEx`) or don't use `raw` at all.

### Big Lists Belong in Streams, Not Assigns

A collection in regular assigns is kept in socket state for diffing—that's O(n) memory PER connected user. For lists over ~100 items, or any unbounded list, use `stream/3` + `stream_insert`/`stream_delete`.

```elixir
# BAD: 5k messages × every connected user, held in memory for diffing
assign(socket, :messages, Chat.list_messages(scope))

# GOOD: rendered once, dropped from socket state
stream(socket, :messages, Chat.list_messages(scope))
```

### Key Comprehensions for Mutable Lists (LiveView 1.1)

A plain `:for` comprehension resends the **entire list** over the wire whenever its assign changes. Add a `:key` (a stable identifier) and LiveView optimises the diff — on reorder/insert it sends index remaps so the client moves DOM nodes instead of re-rendering them.

```heex
<div :for={post <- @posts} :key={post.id}>
  {post.title}
</div>
```

This is a **third list-rendering option** alongside streams and live components, with less bookkeeping than either:
- **Key comprehensions** → general mutable / reordered lists.
- **Streams** → when you accept the manual `stream_insert`/`stream_delete` bookkeeping (and want items dropped from socket memory — see above).
- **Live components** → only when separate change-tracking is genuinely warranted.

### Hidden Inputs for Required Embedded Fields

With `cast_embed`/embedded schemas, a required field that isn't rendered as a visible input won't be sent on submit—so the changeset fails validation in confusing ways. Add `<.input type="hidden" .../>` (or `hidden_input`) for those fields so they round-trip.

### LiveView terminate/2 Requires trap_exit

`terminate/2` only fires if you're trapping exits—which you shouldn't do in LiveView.

**Fix:** Use a separate GenServer that monitors the LiveView process via `Process.monitor/1`, then handle `:DOWN` messages to run cleanup.

### start_async Duplicate Names: Later Wins

Calling `start_async` with the same name while a task is in-flight: the **later one wins**, the previous task's result is ignored.

**Fix:** Call `cancel_async/3` first if you want to abort the previous task.

### Channel Intercept Socket State is Stale

The socket in `handle_out` intercept is a snapshot from subscription time, not current state.

**Why:** Socket is copied into fastlane lookup at subscription time for performance.

**Fix:** Use separate topics per role, or fetch current state explicitly.

### CSS Class Precedence is Stylesheet Order

When merging classes on components, precedence is determined by **stylesheet order**, not HTML order. If `btn-primary` appears later in the compiled CSS than `bg-red-500`, it wins regardless of HTML order.

**Fix:** Use variant props instead of class merging.

### Upload Content-Type Can't Be Trusted

The `:content_type` in `%Plug.Upload{}` is user-provided. Always validate actual file contents (magic bytes) and rewrite filename/extension.

### Read Body Before Plug.Parsers for Webhooks

To verify webhook signatures, you need the raw body. But Plug.Parsers consumes it.

```elixir
{:ok, body, conn} = Plug.Conn.read_body(conn)
verify_signature!(conn, body)
%{conn | body_params: JSON.decode!(body)}
```

Don't use `preserve_req_body: true`—it keeps the entire body in memory for ALL requests.

## Colocation: Keep JS and CSS Next to the Component

### Colocated JS Hooks (LiveView 1.1)

Write a hook inline next to the component instead of a separate file in `assets/`. It's extracted at compile time into a `phoenix-colocated` folder and bundled by ESBuild like any normal import — so **no CSP problems** and no `assets/` naming conflicts. ESBuild wiring is auto-included in new Phoenix 1.8 projects.

```heex
<div id="my-chart" phx-hook=".MyChart">
  <script :type={Phoenix.LiveView.ColocatedHook} name=".MyChart">
    export default { mounted() { /* ... */ } }
  </script>
</div>
```

### Colocated CSS (LiveView 1.2)

Same model with an inline `<style>` tag, extracted at compile time and bundled into `app.css`. Optional **scoping** exists but is **NOT on by default** — native CSS `@scope` is too new and Firefox breaks when morphdom mutates the DOM. Don't rely on scoped colocated CSS in production yet.

### Pure Client-Side Interactivity → Web Components, Not Hooks

For purely client-side behaviour, reach for a **web component**, not a `phx-hook` — hooks "get complicated fast" once they manage their own state and lifecycle. Use hooks for the LiveView↔JS bridge; use web components for self-contained client widgets.

## JS Commands and Forms

### Push JS Structs Over the Wire (LiveView 1.2)

You can put `JS` commands (e.g. `JS.toggle_class`) **inside a `push_event` payload** — no need to encode them into a template attribute and reference them from `liveSocket` JS. Auto-encoded when using Jason or the built-in JSON module; for other encoders call `JS.to_encodable/1` yourself.

```elixir
# server
{:noreply, push_event(socket, "highlight", %{toggle: JS.toggle_class("ring", to: "#banner")})}
```

```js
// hook — run the pushed JS command on the element
this.handleEvent("highlight", ({toggle}) => this.js().execJS(this.el, toggle))
```

### Opt Out of Unused-Field Form Tracking (LiveView 1.2)

Since 1.0, every untouched form input sends a separate "unused field" message over the wire. A per-field attribute lets you opt out — worth it for forms with many inputs.

### Message a Parent From a Function Component

Pass a function as an attribute (the current idiom — acknowledged imperfect):

```heex
<.child on_select={fn id -> send(self(), {:selected, id}) end} />
```

## Performance

For endpoint/Bandit/Cowboy tuning, plug pipeline optimization, LiveView diff minimization, PubSub scaling, connection draining, and telemetry, see [references/performance.md](references/performance.md).

Key rules:
- Set `nodelay: true` in transport options for low-latency APIs
- Use `stream/3` for large lists in LiveView (not full assigns)
- Remove unnecessary plugs from hot API pipelines (each one costs per request)
- Monitor `[:vm, :total_run_queue_lengths]` — if > 0, schedulers are saturated

## Red Flags - STOP and Reconsider

- Database query in mount/3
- `assign_new` for per-mount state (current_user, locale, timezone) — goes stale on reconnect
- `handle_event` that mutates/reveals data without re-checking authorization
- `raw/1` on user-supplied content (XSS)
- Large/unbounded list in assigns instead of `stream/3`
- Required embedded-schema field with no rendered (or hidden) input
- Unscoped PubSub topics in multi-tenant app
- LiveView polling external APIs directly
- Using terminate/2 for cleanup (won't fire without trap_exit)
- Calling start_async with same name without cancel_async first
- Relying on socket.assigns in Channel intercepts (stale!)
- CSS class merging for component customization (use variants)
- Trusting `%Plug.Upload{}.content_type` for security

**Any of these? Re-read The Iron Law and the Gotchas section.**
