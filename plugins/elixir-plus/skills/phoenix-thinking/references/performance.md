# Phoenix Performance

## Table of Contents
- [Endpoint and Server Tuning](#endpoint-and-server-tuning)
- [Plug Pipeline Optimization](#plug-pipeline-optimization)
- [LiveView Performance](#liveview-performance)
- [PubSub Performance](#pubsub-performance)
- [Connection Draining and Deploys](#connection-draining-and-deploys)
- [Telemetry for Performance](#telemetry-for-performance)
- [Static Asset Performance](#static-asset-performance)

## Endpoint and Server Tuning

### Bandit Configuration (Phoenix 1.8+)

```elixir
config :my_app, MyAppWeb.Endpoint,
  http: [
    port: 4000,
    thousand_island_options: [
      num_acceptors: System.schedulers_online() * 2,
      num_connections: :infinity,
      max_connections_retry_wait: 0,
      transport_options: [nodelay: true]
    ]
  ]
```

| Option | Effect | Default |
|--------|--------|---------|
| `num_acceptors` | Parallel connection accept loops | 100 |
| `num_connections` | Max concurrent connections | 16_384 |
| `max_connections_retry_wait` | Backoff when at max connections | 1000ms |
| `nodelay: true` | Disable Nagle's algorithm (TCP_NODELAY) | false |

**`nodelay: true`** is critical for low-latency APIs — Nagle buffers small packets, adding up to 40ms delay.

**`num_acceptors = schedulers * 2`** reduces blocking on the Accept syscall under high connection rates.

### Cowboy Configuration (if using Cowboy)

```elixir
config :my_app, MyAppWeb.Endpoint,
  http: [
    port: 4000,
    protocol_options: [
      max_keepalive: 1_000,
      idle_timeout: 60_000,
      request_timeout: 30_000
    ],
    transport_options: [
      num_acceptors: 100,
      max_connections: :infinity,
      socket_opts: [nodelay: true]
    ]
  ]
```

### Bandit vs Cowboy

| Aspect | Bandit | Cowboy |
|--------|--------|--------|
| HTTP/2 | Native | Native |
| WebSocket | Native | Native |
| Process model | One process per connection | One process per connection |
| Performance | Slightly faster on benchmarks | Battle-tested, wider adoption |
| Config | Thousand Island options | Protocol + transport options |
| Default in | Phoenix 1.8+ | Phoenix < 1.8 |

Both are excellent. Bandit is the modern default.

## Plug Pipeline Optimization

### Measuring Plug Cost

Every plug in the pipeline runs on every request. At high RPS, even cheap plugs add up.

**Plugs removed in a 1M RPS benchmark (and their cost):**

| Plug | Per-Request Cost | Why It's Expensive |
|------|-----------------|-------------------|
| `Plug.Telemetry` | 2x `System.monotonic_time()` + map alloc | Two monotonic time calls + metadata map |
| `Plug.RequestId` | UUID generation | Random bytes + formatting |
| `Plug.Session` | Cookie parsing + session map | Crypto verification + deserialization |
| `Plug.Static` | Path matching against filesystem | String comparison on every request |
| `Plug.MethodOverride` | Header check | Minor but unnecessary for APIs |

### Hot Path Optimization

For API endpoints that need maximum throughput:

```elixir
# Instead of Phoenix.Controller.json/2 (does Application.get_env lookup)
send_resp(conn, 200, json_body)

# Instead of :accepts plug (parses Accept header every request)
pipeline :benchmark do
  plug :put_format, "json"
end
```

### Plug.Parsers Tuning

```elixir
plug Plug.Parsers,
  parsers: [:json, :urlencoded],
  pass: ["*/*"],
  json_decoder: JSON,       # Elixir 1.18+ built-in, faster than Jason
  length: 1_048_576          # 1MB max body (default 8MB)
```

`length` limits request body size — smaller = faster rejection of oversized requests.

## LiveView Performance

### Minimize Diff Payloads

LiveView sends only diffs over WebSocket. Large assigns = large diffs = slow updates.

```elixir
# Bad: entire list re-sent on any change
assign(socket, :items, updated_items)

# Good: temporary assigns — cleared after render, only diff sent
mount: {:ok, assign(socket, items: items), temporary_assigns: [items: []]}

# Best: streams — server tracks only IDs, not full data
stream(socket, :items, items)
```

### Stream for Large Lists

```elixir
def mount(_params, _session, socket) do
  {:ok, stream(socket, :items, Items.list())}
end

def handle_event("delete", %{"id" => id}, socket) do
  item = Items.delete!(id)
  {:noreply, stream_delete(socket, :items, item)}
end
```

Streams send only insert/delete operations, not the full list.

### Debounce and Throttle Client Events

```heex
<input phx-keyup="search" phx-debounce="300" />
<button phx-click="submit" phx-throttle="1000">Save</button>
```

- `phx-debounce`: Wait N ms after last event before sending
- `phx-throttle`: Send at most once per N ms

### Avoid Large Assigns

Assigns are serialized over the WebSocket. Don't store:
- Large data structures (paginate instead)
- Binary data (store paths/URLs, not file contents)
- Data the template doesn't use (it still gets tracked for diffs)

## PubSub Performance

### FastLane Optimization

Phoenix PubSub uses a FastLane for broadcasts — messages go directly to subscriber processes without intermediate GenServer serialization.

### Topic Sharding for High Throughput

```elixir
# Bad: single topic, all subscribers process every message
Phoenix.PubSub.broadcast(PubSub, "orders", msg)

# Good: sharded topics, subscribers only get relevant messages
Phoenix.PubSub.broadcast(PubSub, "orders:#{region}", msg)
```

### Adapter Choice

| Adapter | Use Case |
|---------|----------|
| `Phoenix.PubSub.PG2` (default) | Single node or Erlang cluster |
| Redis adapter | Cross-language, non-Erlang nodes |

PG2 is faster (no network hop). Use Redis only when non-BEAM services need to participate.

## Connection Draining and Deploys

### Graceful Shutdown

```elixir
# In endpoint config
config :my_app, MyAppWeb.Endpoint,
  drainer: [
    batch_size: 1000,      # Close N connections per batch
    batch_interval: 100,    # ms between batches
    shutdown: 30_000        # Total drain timeout
  ]
```

### Rolling Deploy Pattern

1. New instance starts and passes health check
2. Load balancer shifts traffic to new instance
3. Old instance stops accepting new connections
4. Old instance drains existing connections (WebSocket, SSE, long-poll)
5. Old instance shuts down after drain timeout

### WebSocket Connection Limits

```elixir
# Limit LiveView connections per IP (in endpoint or reverse proxy)
# Phoenix doesn't have built-in rate limiting — use Hammer or Plug.Throttle

# Or limit at transport level
socket "/live", Phoenix.LiveView.Socket,
  websocket: [
    timeout: 45_000,          # Idle timeout
    compress: true,            # Compress WebSocket frames
    max_frame_size: 1_000_000  # 1MB max frame
  ]
```

## Telemetry for Performance

### Key Events to Monitor

```elixir
# Request timing
[:phoenix, :endpoint, :start]    # Request received
[:phoenix, :endpoint, :stop]     # Response sent (duration in metadata)

# Router
[:phoenix, :router_dispatch, :start]
[:phoenix, :router_dispatch, :stop]

# LiveView
[:phoenix, :live_view, :mount, :start]
[:phoenix, :live_view, :mount, :stop]
[:phoenix, :live_view, :handle_event, :start]
[:phoenix, :live_view, :handle_event, :stop]

# Socket connections
[:phoenix, :socket_connected]

# VM (via telemetry_poller)
[:vm, :memory]
[:vm, :total_run_queue_lengths]    # Scheduler saturation indicator
```

### Quick Telemetry Attach

```elixir
:telemetry.attach("slow-requests", [:phoenix, :endpoint, :stop], fn _event, %{duration: d}, meta, _config ->
  if d > System.convert_time_unit(100, :millisecond, :native) do
    Logger.warning("Slow request: #{meta.conn.request_path} #{d / 1_000_000}ms")
  end
end, nil)
```

### Run Queue Length

`[:vm, :total_run_queue_lengths, :total]` — if consistently > 0, schedulers are saturated. Add CPUs or optimize hot paths.

## Static Asset Performance

### Production: Use a Reverse Proxy

`Plug.Static` checks the filesystem on every request. In production:

```elixir
# Remove or limit Plug.Static
plug Plug.Static,
  at: "/",
  from: :my_app,
  gzip: true,           # Serve pre-compressed files
  cache_control_for_etags: "public, max-age=31536000"  # 1 year cache
```

Better: serve static files from nginx/CDN, bypass Phoenix entirely.

### Fingerprinting

Phoenix Mix.Tasks.Phx.Digest generates fingerprinted filenames (`app-abc123.js`). Combined with far-future cache headers, browsers cache indefinitely and bust on deploy.

```bash
mix phx.digest              # Generate fingerprinted assets
mix phx.digest.clean        # Clean old fingerprints
```
