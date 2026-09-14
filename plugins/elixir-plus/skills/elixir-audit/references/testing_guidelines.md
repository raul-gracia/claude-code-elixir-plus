# Elixir Testing Review

## Coverage

- Map each `lib/**/*.ex` to a `test/**/*_test.exs`. Modules with no test file at all are the first list.
- Real numbers come from ExCoveralls (`mix coveralls` / `mix coveralls.html`). Line coverage in Elixir under-reports multi-clause functions, so treat a high number with suspicion and a low number as reliable.
- Coverage targets are only meaningful per layer. Expect: contexts/domain high, schemas moderate, web controllers moderate, `application.ex` and config near zero.
- Zero-coverage modules that are *reachable in production* are the finding. Zero-coverage modules that are dead code are a different (also worth reporting) finding.

## `async: true`

- The fraction of test files with `async: true` is a direct measure of how well the codebase isolates state.
- Reasons a test cannot be async: named processes (`name: __MODULE__`), global ETS tables, `Application.put_env` in setup, `Mox` in global mode, file system writes to fixed paths, `:meck`.
- Each of those is itself a design finding — a test that must be synchronous usually points at global state in the code under test.

## Ecto sandbox

- `setup` should use `Ecto.Adapters.SQL.Sandbox.start_owner!/2` (or `checkout/2`) with `on_exit` returning the connection.
- **Shared mode** (`Sandbox.mode(Repo, {:shared, self()})`) makes the test non-async. Common and correct for LiveView/browser tests; a smell everywhere else.
- Processes spawned by the code under test need explicit `allow/3`, or they get "ownership" errors — flag tests that work around this with `Process.sleep`.
- Flag `async: true` on a test that also uses shared mode; that combination is a race.

## Mocks and doubles

- **Mox** is the idiomatic approach: define a behaviour, inject the implementation via config, `Mox.defmock`, `verify_on_exit!`. Check that `setup :verify_on_exit!` is actually present — without it, unmet expectations pass silently.
- **`:meck` / `Mimic` / `Patch`** replace modules globally. They work, but force `async: false` and couple the test to implementation. Note them; do not necessarily flag them if used consistently.
- **Hand-rolled stub modules** chosen by config are fine and sometimes clearer than Mox.
- The finding to look for: HTTP calls to real services in the test suite. Grep test support for `Req`, `Finch`, `HTTPoison`, `Tesla` without a mock adapter, and check `config/test.exs`.

## Flakiness

- `Process.sleep` in tests is the primary flake source. Replace with `assert_receive`, `Mox` expectations, or polling with a deadline.
- `assert_receive` without a timeout uses 100ms — too short on loaded CI. Check whether failures correlate with CI load.
- Tests depending on ordering, on `Enum` ordering of maps, or on `DateTime.utc_now()` without freezing.
- Tests asserting on full structs (`assert user == %User{...}`) break on unrelated schema changes; prefer asserting the fields under test.

## Test structure

- Four-phase shape (setup, exercise, verify, teardown) visible in each test.
- `describe` blocks per function-under-test, named `"function_name/arity"`.
- One logical assertion per test where practical; a test with 15 asserts is testing the setup.
- `setup` blocks that build more than the test needs — deep factory graphs hide cost and couple tests to unrelated schemas.

## Specific test types worth checking for

- **Doctests** — `doctest MyModule` in the test file wherever `@doc` contains `iex>` examples. Free tests; often forgotten.
- **Property tests** — StreamData for parsers, serializers, encoders, and anything with an inverse (`decode(encode(x)) == x`).
- **LiveView tests** — `Phoenix.LiveViewTest` with `live/2`, `render_click`, `render_submit`, `has_element?`. A LiveView covered only by a controller test that asserts a 200 is effectively untested.
- **Migration tests** — rarely written, but a data-migration with no test is a Critical finding if it is destructive.
- **Contract tests** against external APIs — or at minimum a recorded fixture that is refreshed.

## Factories

- `ExMachina` or plain fixture functions in `test/support/fixtures/` are both fine.
- Flag: factories that insert deep association trees by default (slow, and couples every test to the whole schema), factories with hardcoded unique values that collide under async, factories used to build invalid states that the code then has to tolerate.
