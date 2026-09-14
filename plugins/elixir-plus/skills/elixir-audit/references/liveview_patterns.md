# LiveView Review

## Authorization — the highest-severity LiveView class

**`mount/3` authorization does not cover `handle_event/3`.** A LiveView that checks permissions in `mount` and then handles `"delete"` with `params["id"]` lets any connected user delete any record by sending a crafted event over the socket. The client controls the payload entirely; hidden form fields, `phx-value-*` attributes, and DOM ids are attacker-controlled.

Audit procedure:
1. List every `handle_event/3` clause that acts on an id or mutates state.
2. For each, confirm it re-derives authorization from `socket.assigns.current_user` and the target record — not from the payload alone.
3. Flag any that scope only by the param.

The idiomatic fix is scoping every lookup by the actor (`Blog.get_post!(current_user, id)`), so the query itself cannot return another user's record.

Also check:
- `on_mount` hooks (`Phoenix.LiveView.on_mount/1`) used for shared session/auth rather than repeating it in each `mount`
- `live_session` grouping views that share an auth requirement — and that navigation *between* live_sessions forces a full remount
- `handle_params/3` re-authorizing when the id changes on `push_patch`
- Uploads: `allow_upload` with `accept`, `max_entries`, `max_file_size`; the consume callback validating content, not trusting the client-supplied filename or type

## Socket state and memory

Every connected client holds its own process and assigns. A 500-row list in assigns times 2,000 users is real memory.

- **Large collections in assigns** → `stream/3` (LiveView 0.18+). Streams keep items in the DOM, not in the process.
- **`temporary_assigns`** for append-only data (logs, chat) when streams do not fit.
- Whole schemas in assigns where a few fields are rendered — and worse, schemas with preloaded associations.
- Duplicated derived state in assigns that could be computed in `render` (cheap) or as a function component.
- Check what happens on reconnect: state rebuilt from the DB, or lost?

## Rendering and change tracking

- Work in `render/1` beyond composing markup — DB calls, `Enum.sort` over a large list, date formatting of every row. `render` runs on every state change.
- Change tracking is per-assign. Assigning a whole map when one field changed re-renders everything that touches it.
- `assign_new/3` for values that should not be recomputed on reconnect.
- Function components (`attr`/`slot` declared) instead of nested `<%= if %>` blocks.
- `phx-update="stream"` used with streams; manual DOM manipulation fighting LiveView.

## N+1 per event

A `handle_event` that reloads a collection and preloads per item, on every keystroke of a `phx-change` form, is a common and invisible load generator. Check:
- `phx-change` handlers doing DB work — debounce (`phx-debounce`) and/or validate in memory
- Events that reload the full list when one row changed (streams solve this)

## Process concerns

- `handle_info/2` growing a catch-all clause that swallows unexpected messages
- PubSub subscriptions in `mount` without checking `connected?(socket)` — mount runs twice (static render, then the socket), so unguarded subscriptions and DB calls run twice
- Timers (`Process.send_after`) started in mount without the `connected?` guard, or never cancelled
- Long-running work in a handler blocking the LiveView process — use `start_async`/`assign_async` (LiveView 0.20+) or a supervised Task

## Forms

- `to_form/2` with a changeset, and `used_input?`/`phx-feedback-for` for error display timing
- Validation on `phx-change` mirroring the server-side validation on submit
- Hidden fields trusted (`<input type="hidden" name="user_id">`) — always attacker-controlled
- `phx-trigger-action` flows (for non-LiveView POSTs like login) checked carefully

## Testing

`Phoenix.LiveViewTest` — `live/2`, `render_click/2`, `render_submit/2`, `render_change/2`, `has_element?/3`, `assert_patch/2`, `assert_redirect/2`.

A LiveView covered only by a controller test asserting `html_response(conn, 200)` is untested — that only exercises the static render, not a single event handler. Flag this pattern; it is common and it is exactly where the authorization bugs above hide.
