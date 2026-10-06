# Request-path performance for Bandit/Plug, SQLite and OTP 28+

These are measured findings, not general advice. They come from October 2026 work on the `once-campfire-elixir` port (DHH's Elixir/Go/Rust comparison): our own profiling plus community PRs #1 (zachdaniel) and #5 (lau) on `basecamp/once-campfire-elixir`. The hardware was 4 pinned shared vCPUs, so treat the numbers as ratios. Revisit each item when its stated version condition changes.

## Measure before changing anything

- Profile inside a release without rebuilding it. Releases omit `:tools`, so load it from the Erlang install over `rpc`: `Path.wildcard("/usr/local/lib/erlang/lib/tools-*/ebin") |> Enum.each(&:code.add_patha(String.to_charlist(&1)))`, then `:code.load_abs` the `eprof`/`tprof` modules.
- Prefer `:tprof` (OTP 27+) with `%{type: :call_time}` across all processes. eprof misses short-lived processes such as job tasks, over-weights call-heavy pure functions, and charges descheduled time to `gen_server:handle_msg/3`, so a large `handle_msg` share is not real CPU. NIF times (SQLite, zlib, crypto) are trustworthy.
- Find serialization by scaling, not by profiles. Compare throughput at 1 and 16 connections on N cores; a healthy app scales about N×. Stock Campfire scaled 1.5× on its sidebar where Go scaled 3.9×, which exposed a single-process bottleneck.
- Compare apps by CPU per request: cgroup `cpu.stat` `usage_usec` before and after a run, divided by successful responses. Check cores busy (rps × CPU per request) too. Below about 90% means the load generator or network is the limit, not the app.
- Containers often default to soft `nofile` 1024, and the BEAM does not raise it (Go and Rust runtimes raise it to the hard limit at boot). Around 1,000 websockets the BEAM fails to accept connections while the Go and Rust apps keep working. Pass `--ulimit nofile=65536:65536` to every app under test, and raise `LimitNOFILE` for load generators started under systemd.

## OTP 28+ re-imports regex literals on every use

*(Verified on Elixir 1.19.5/OTP 28 and Elixir 1.20.4/OTP 29. Revisit when Elixir or OTP caches exported regexes.)*

- A compiled `~r` literal, in a function body or a module attribute, runs `:re.import/1` each time it is evaluated. That costs about 2.2 µs per use (3.8 µs against 1.6 µs for a cached regex). Campfire paid it about 240 times per request, roughly 0.5 ms of a 3.6 ms page.
- A module attribute holding many regexes is the worst case. Referencing `@routes` or `@buckets` (a route table of compiled regexes) materialises and re-imports every regex in the literal on each request. Keep sources in the attribute and compile once at runtime into `:persistent_term` (`Regex.compile!/2` on first use), or compile routes into function-head pattern matches as PR #1 did.
- A drop-in fix needs no call-site changes. Define a `sigil_r` macro that, inside function bodies, expands to a `:persistent_term`-cached `Regex.compile!/2` of the literal source, and import it with `import Kernel, except: [sigil_r: 2]`.

## Hot-path costs that look free in code review

- `System.get_env/1,2` runs `os:getenv` plus a Unicode conversion on every call. Campfire made about 26 per request, including inside `Clock.now/0` and secret-key lookups. Read once and cache in `:persistent_term`.
- Memoize per-request work in `conn.private`, not the process dictionary. Bandit reuses one process per keep-alive connection, so process-dictionary memos leak into the next request. Campfire looked the session and user up twice per request, decrypted the session cookie repeatedly, and parsed the User-Agent 11 to 13 times. A pure parse can live in a bounded ETS table keyed by the raw header.
- Write cookies only when they change. Re-signing, encrypting and percent-encoding a session cookie with a rolling expiry on every response was a visible slice of each request. The Rust port writes on change or on the activity refresh only.
- Avoid the `+sbwt none +sbwtdcpu none +sbwtdio none` VM flags unless a measurement supports them. They stop idle schedulers spinning, which frees CPU for co-located processes, but schedulers then take longer to wake. Single-client throughput was 102 req/s with the flags and 581 without, and 16-connection throughput did not improve.

## Single-process bottlenecks in databases and caches

- A GenServer owning the only SQLite (exqlite) connection serializes every query in the app. Use one writer connection for writes and transactions plus a pool of read-only WAL connections. Cache prepared statements and their column lists per connection (call `Sqlite3.reset/1` before reuse) and fetch with a large chunk size.
- Running reads in the calling process avoids a message hop and the row copy. Check out a connection with `:ets.insert_new({index, self()})` as the lock, and reclaim locks whose owner is no longer alive, because a process killed during a NIF call never runs its `after` block. Fall back to a queued reader process when every connection is busy. PR #3 used DBConnection instead.
- Agent or GenServer caches serialize just like connections. Use ETS with `read_concurrency: true`; large binaries come back as shared references, not copies. `:ets.info(t, :memory)` does not count off-heap binaries, so bound the byte size with your own `:atomics` counter.
- A single Redix connection per app, plus Rails-format cache entries (Marshal + zlib) decompressed on every hit, cost about 8% of CPU. In-process ETS fragments remove both.

## Responses, compression and page caching

- Per-request gzip of large pages dominates. Deflating a ~460 KB page at level 6 was 25% of CPU. A lower level only helps before caching (PR #2 measured 14 to 22%).
- Random per-request bytes defeat every cache. Rails-style masked CSRF tokens make each page unique; removing them made pages byte-identical, which enabled gzip reuse and page caching, and gave 2.3× on the room page by itself in PR #5. A fixed mask gives up BREACH protection, so replace tokens with `Sec-Fetch-Site`/`Origin` checks, as the Rust port and PR #5 did.
- Reuse compressed bytes. Cache gzip output keyed by the body's ETag and restamp only the 4-byte mtime in the gzip header. To go further, splice pre-compressed fragments. Deflate each fragment with the previous part's last 32 KB as a preset dictionary (`:zlib.deflateSetDictionary/2`), sync-flush it, and combine CRCs with `:erlang.crc32_combine/3`. The Rust port and PRs #1 and #5 do this. Output stays within about 1% of compressing the page whole, and whole-page deflate and hashing per request disappear.
- A read cache keyed by table write generations was PR #5's largest single step. Writes bump a per-table generation after commit, results are stored under the generations they read, and the WAL change counter catches commits from outside the app. CPU per request fell about 5× on the sidebar and search and 2.3× on the room and messages pages.
- If CPU is the constraint, drop a separate proxy in front of the app (Thruster or another sidecar). Serve from Bandit directly with an in-process cache for `public, max-age` responses.

## WebSocket fan-out with Bandit

- Bandit's default WebSocket `timeout` closes listen-only sockets after about 60 s without client traffic. Action Cable style clients mostly listen, so they reconnect every minute. Pass `timeout: :infinity` in the WebSock options and rely on send timeouts for stuck clients (PR #1).
- Encode each broadcast once. Build the frame binary once per distinct subscription identifier and `send/2` that same binary to every subscriber, instead of sending the term for each process to encode. Per-subscriber JSON decode and encode was about 67% of cable CPU.
- `zachdaniel/bandit` (branch `batched-websocket-writes`) coalesces queued frames into one socket write, and fan-out was about 60% higher with it. It is a fork, so check whether upstream Bandit has merged it before depending on it.
- One process per socket and per-socket framing kept fan-out about 2× behind the Rust port even after these changes. The remaining gap is structural.

## When native code (NIFs) is worth it

- Native code was mostly not the bottleneck, because zlib, SHA-256, SQLite and Gumbo were already native. The wins came from avoiding work.
- Convert external programs that talk JSON over a Port into NIFs when they sit on the request path. PR #1 did this for the Gumbo HTML parser with identical output on 4,782 inputs.
- Reserve Rustler for chunky, self-contained work of roughly tens of µs or more per call, such as rich-text sanitize-and-render. Native calls over about 1 ms need dirty schedulers, and a crash in C code under the NIF takes down the VM.
