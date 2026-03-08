# Skill Evaluation Plan

Run these evals in a fresh Claude Code session inside an Elixir project (e.g. `~/Code/ashdemo` or any repo with `mix.exs`).

## How to Run

1. Open a new Claude Code session in an Elixir project directory
2. Run `/skill-creator`
3. Point it at `~/Code/claude-code-elixir-plus/plugins/elixir-plus/skills/`
4. Use the eval/benchmark features to test each skill below

## Eval Test Cases

### 1. using-elixir-skills (Router Skill)

**Should trigger on:**
- "I need to add a feature to this Elixir app"
- "help with Elixir"
- "which skill should I use?"

**Should NOT trigger on:**
- "write a Python script"
- "help me with this JavaScript"

**Success criteria:** Routes to the correct sub-skill, doesn't try to write code itself.

---

### 2. elixir-thinking

**Should trigger on:**
- "should I use a GenServer here or just a module?"
- "how should I structure this module?"
- "refactor this to use pattern matching"
- "I'm coming from Ruby/OOP, how do I think about this?"

**Should NOT trigger on:**
- "add a LiveView page" (→ phoenix-thinking)
- "create a migration" (→ ecto-thinking)
- "add a background job" (→ oban-thinking)

**Success criteria:** Mentions Iron Law (no process without runtime reason), references paradigm shifts.

---

### 3. phoenix-thinking

**Should trigger on:**
- "why is mount called twice?"
- "add a LiveView page"
- "handle real-time updates with PubSub"
- "create a form component"

**Should NOT trigger on:**
- "add a database table" (→ ecto-thinking)
- "create an Ash resource" (→ ash-thinking)

**Success criteria:** Mentions Iron Law (no DB queries in mount), references handle_params for data loading.

---

### 4. ecto-thinking

**Should trigger on:**
- "add a new database table"
- "fix N+1 queries"
- "how should contexts talk to each other?"
- "create a migration with composite foreign keys"

**Should NOT trigger on:**
- "create an Ash resource with policies" (→ ash-thinking)
- "add a LiveView form" (→ phoenix-thinking)

**Success criteria:** Mentions bounded contexts, cross-context ID references, preload vs join trade-offs.

---

### 5. otp-thinking

**Should trigger on:**
- "this GenServer is slow"
- "add background processing with Task"
- "should I use Broadway or Oban?"
- "design a supervision tree"

**Should NOT trigger on:**
- "add a background job with Oban" (→ oban-thinking)
- "create an Ash resource" (→ ash-thinking)

**Success criteria:** Mentions Iron Law (GenServer is bottleneck by design), references ETS pattern and abstraction decision tree.

---

### 6. oban-thinking

**Should trigger on:**
- "add a background job"
- "retry failed jobs"
- "add email sending async"
- "unique jobs to prevent duplicates"

**Should NOT trigger on:**
- "consume from SQS/Kafka" (→ otp-thinking, Broadway)
- "create a GenServer for state" (→ otp-thinking)

**Success criteria:** Mentions Iron Law (JSON serialization), warns about atom keys in perform/1.

---

### 7. ash-thinking

**Should trigger on:**
- "create an Ash resource"
- "add policies to this resource"
- "set up AshAuthentication"
- "define a code interface"

**Should NOT trigger on:**
- "create an Ecto schema" (→ ecto-thinking)
- "add a Phoenix context" (→ ecto-thinking or phoenix-thinking)

**Success criteria:** Mentions Iron Law (resources are the API), warns against wrapping Ash in Phoenix contexts.

---

## Overlap Tests (Critical)

These test that the RIGHT skill fires when topics overlap:

| Prompt | Expected Skill | NOT |
|--------|---------------|-----|
| "add a form in LiveView with Ecto changeset" | phoenix-thinking | ecto-thinking |
| "create a schema with belongs_to" | ecto-thinking | ash-thinking |
| "create an Ash resource with actions" | ash-thinking | ecto-thinking |
| "process SQS messages" | otp-thinking | oban-thinking |
| "add a cron job with Oban" | oban-thinking | otp-thinking |
| "GenServer that manages user sessions" | otp-thinking | elixir-thinking |
| "pattern match on function heads" | elixir-thinking | phoenix-thinking |

## Benchmark Metrics

After running evals, record:
- **Trigger accuracy**: % of test cases where correct skill fired
- **False positive rate**: % where wrong skill fired
- **Token usage**: Compare before/after description changes
