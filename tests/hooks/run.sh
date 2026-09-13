#!/usr/bin/env bash
# Regression tests for the elixir-plus guardrail hooks.
# Usage: tests/hooks/run.sh
set -uo pipefail

HOOKS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../plugins/elixir-plus/hooks" && pwd)"
pass=0; fail=0

report() {
  if [ "$1" = "ok" ]; then
    pass=$((pass + 1)); printf '  ok   %s\n' "$2"
  else
    fail=$((fail + 1)); printf '  FAIL %s\n     %s\n' "$2" "$3"
  fi
}

# --- block-dangerous-ops ----------------------------------------------------
bdo() { printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(jq -Rn --arg c "$1" '$c')" \
          | "$HOOKS/block-dangerous-ops.sh" 2>/dev/null; }

assert_deny() {
  local out; out=$(bdo "$1")
  local decision; decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null)
  if [ "$decision" = "deny" ]; then report ok "deny: $1"; else report fail "deny: $1" "expected deny, got '$decision'"; fi
}

assert_allow() {
  local out; out=$(bdo "$1")
  if [ -z "$out" ]; then report ok "allow: $1"; else report fail "allow: $1" "expected no output, got: $out"; fi
}

echo "block-dangerous-ops"
assert_deny  'mix ecto.drop'
assert_deny  'mix ecto.reset'
assert_deny  'cd apps/web && mix ecto.reset'
assert_deny  'mix   ecto.drop --quiet'
assert_deny  'MIX_ENV=prod mix release'
assert_deny  'MIX_ENV=prod mix ecto.migrate'
assert_deny  'git push --force'
assert_deny  'git push -f origin main'
assert_deny  'git add . && git commit -m wip && git push --force'

assert_allow 'mix ecto.migrate'
assert_allow 'mix ecto.rollback --step 1'
assert_allow 'mix ecto.create'
assert_allow 'mix test'
assert_allow 'MIX_ENV=test mix test'
assert_allow 'git push origin main'
assert_allow 'git push --force-with-lease origin main'
assert_allow 'grep -f patterns.txt lib/ && git push origin main'
assert_allow 'tar -xzf release.tar.gz'
assert_allow 'echo "do not run mix ecto.drop"'

# --- error-critic -----------------------------------------------------------
echo "error-critic"
STATE=$(mktemp -d)
trap 'rm -rf "$STATE"' EXIT

ec() { # $1 = command, $2 = error message, $3 = session
  printf '{"session_id":%s,"scratchpad_dir":%s,"cwd":"/tmp","tool_name":"Bash","tool_input":{"command":%s},"tool_error":{"error":{"message":%s}}}' \
    "$(jq -Rn --arg s "$3" '$s')" "$(jq -Rn --arg d "$STATE" '$d')" \
    "$(jq -Rn --arg c "$1" '$c')" "$(jq -Rn --arg m "$2" '$m')" \
    | "$HOOKS/error-critic.sh" 2>/dev/null
}

out1=$(ec 'mix test' 'undefined function foo/1' s1)
out2=$(ec 'mix test' 'undefined function foo/1' s1)
[ -z "$out1" ] && report ok "1st failure stays silent" || report fail "1st failure stays silent" "got: $out1"
[ -z "$out2" ] && report ok "2nd failure stays silent" || report fail "2nd failure stays silent" "got: $out2"

out3=$(ec 'mix test' 'undefined function foo/1' s1)
ctx=$(printf '%s' "$out3" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)
[ -n "$ctx" ] && report ok "3rd identical failure escalates" || report fail "3rd identical failure escalates" "no additionalContext in: $out3"
case "$ctx" in *"failure #3"*) report ok "escalation names the attempt count" ;;
  *) report fail "escalation names the attempt count" "context: $ctx" ;; esac
case "$ctx" in *"STOP retrying"*) report ok "escalation says stop" ;;
  *) report fail "escalation says stop" "context: $ctx" ;; esac
evt=$(printf '%s' "$out3" | jq -r '.hookSpecificOutput.hookEventName // ""' 2>/dev/null)
[ "$evt" = "PostToolUseFailure" ] && report ok "emits correct hookEventName" || report fail "emits correct hookEventName" "got '$evt'"

# Cosmetic drift (line numbers, absolute paths) must still collapse to one signature.
ec 'mix test' 'lib/app/foo.ex:12: undefined function bar/1' s2 >/dev/null
ec 'mix test' 'lib/app/foo.ex:48: undefined function bar/1' s2 >/dev/null
out_drift=$(ec 'mix test' 'lib/app/foo.ex:99: undefined function bar/1' s2)
[ -n "$(printf '%s' "$out_drift" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)" ] \
  && report ok "near-identical errors collapse to one signature" \
  || report fail "near-identical errors collapse to one signature" "got: $out_drift"

# Genuinely different failures must not accumulate toward the threshold.
ec 'mix compile' 'error A' s3 >/dev/null
ec 'mix format' 'error B' s3 >/dev/null
out_distinct=$(ec 'mix credo' 'error C' s3)
[ -z "$out_distinct" ] && report ok "distinct failures do not accumulate" \
  || report fail "distinct failures do not accumulate" "got: $out_distinct"

# Sessions are isolated from each other.
out_newsession=$(ec 'mix test' 'undefined function foo/1' s4)
[ -z "$out_newsession" ] && report ok "counts are per-session" \
  || report fail "counts are per-session" "got: $out_newsession"

# Threshold is configurable.
out_thresh=$(ELIXIR_PLUS_ERROR_CRITIC_THRESHOLD=1 ec 'mix dialyzer' 'boom' s5)
[ -n "$out_thresh" ] && report ok "threshold env override works" \
  || report fail "threshold env override works" "got: $out_thresh"

# Real Claude Code payload shape: failure text arrives as top-level `.error`,
# and `scratchpad_dir` is absent entirely. Verified against a captured
# PostToolUseFailure event.
real() { # $1 = command, $2 = error, $3 = session, $4 = state dir override
  local sp="$4"
  if [ -n "$sp" ]; then
    printf '{"session_id":%s,"scratchpad_dir":%s,"cwd":"/home/raul/proj","hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{"command":%s},"error":%s,"is_interrupt":false}' \
      "$(jq -Rn --arg s "$3" '$s')" "$(jq -Rn --arg d "$sp" '$d')" \
      "$(jq -Rn --arg c "$1" '$c')" "$(jq -Rn --arg m "$2" '$m')"
  else
    printf '{"session_id":%s,"cwd":%s,"hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{"command":%s},"error":%s,"is_interrupt":false}' \
      "$(jq -Rn --arg s "$3" '$s')" "$(jq -Rn --arg d "${REAL_CWD:-/nonexistent}" '$d')" \
      "$(jq -Rn --arg c "$1" '$c')" "$(jq -Rn --arg m "$2" '$m')"
  fi | "$HOOKS/error-critic.sh" 2>/dev/null
}

real 'mix compile' 'Exit code 1
** (Mix) Could not find a Mix.Project' r1 "$STATE" >/dev/null
real 'mix compile' 'Exit code 1
** (Mix) Could not find a Mix.Project' r1 "$STATE" >/dev/null
out_real=$(real 'mix compile' 'Exit code 1
** (Mix) Could not find a Mix.Project' r1 "$STATE")
ctx_real=$(printf '%s' "$out_real" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)
case "$ctx_real" in *"Could not find a Mix.Project"*)
    report ok "reads top-level .error from real payload" ;;
  *) report fail "reads top-level .error from real payload" "history lost the error text: $ctx_real" ;;
esac

# With scratchpad_dir absent, state must NOT be written into cwd.
PROJ=$(mktemp -d)
REAL_CWD="$PROJ" real 'mix test' 'boom' r2 "" >/dev/null
if [ -d "$PROJ/elixir-plus" ]; then
  report fail "never writes state into the project dir" "created $PROJ/elixir-plus"
else
  report ok "never writes state into the project dir"
fi
rm -rf "$PROJ"

# --- fail-open contract -----------------------------------------------------
echo "fail-open"
for h in block-dangerous-ops error-critic; do
  for bad in '' 'not json at all' '{}' '{"tool_input":{}}'; do
    printf '%s' "$bad" | "$HOOKS/$h.sh" >/dev/null 2>&1
    rc=$?
    [ "$rc" -eq 0 ] && report ok "$h exits 0 on malformed input: '${bad:0:20}'" \
      || report fail "$h exits 0 on malformed input: '${bad:0:20}'" "exit $rc"
  done
done

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
