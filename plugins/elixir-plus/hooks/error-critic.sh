#!/usr/bin/env bash
# PostToolUseFailure guard: break retry loops.
#
# Counts structurally-identical failures within a session. On the Nth repeat
# (default 3) it injects a consolidated history and tells the model to stop
# guessing and escalate -- the enforced form of the "stop after 2-3 failed
# attempts" rule that prose in CLAUDE.md does not reliably trigger.
#
# PostToolUseFailure cannot block (the tool already ran), so the lever is
# additionalContext, not a permission decision.
#
# Fail-open by design: no `set -e`.

THRESHOLD="${ELIXIR_PLUS_ERROR_CRITIC_THRESHOLD:-3}"

input=$(cat 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0

# Extract each field separately. A combined TSV read would silently shift
# fields when an optional key (scratchpad_dir) is absent, which once sent state
# into the user's project directory.
jqget() { printf '%s' "$input" | jq -r "$1 // \"\"" 2>/dev/null; }

session_id=$(jqget '.session_id')
scratchpad_dir=$(jqget '.scratchpad_dir')
tool_name=$(jqget '.tool_name')
[ -n "$session_id" ] || session_id="nosession"
[ -n "$tool_name" ] || tool_name="unknown"

# Target identifies *what* was attempted; message identifies *how* it broke.
target=$(jqget '.tool_input.command // .tool_input.file_path // .tool_input.filePath')
# Claude Code delivers the failure as a top-level `.error` string; the other
# shapes are documented variants kept as fallbacks. Verified against a live
# PostToolUseFailure payload.
message=$(jqget '.error // .tool_error.error.message // .tool_error.message // .tool_response.text')

[ -n "$target$message" ] || exit 0

# Normalise so cosmetically-different repeats of the same failure collapse:
# lowercase, strip absolute paths, collapse digits and whitespace.
normalise() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -e 's#/[a-z0-9_./-]*/#/#g' -e 's/[0-9][0-9]*/N/g' \
    | tr -s '[:space:]' ' ' \
    | cut -c1-400
}

signature=$(printf '%s|%s|%s' "$tool_name" "$(normalise "$target")" "$(normalise "$message")")

# State lives outside the user's repo. Prefer the session scratchpad so it is
# cleaned up automatically; fall back to a temp dir keyed by session.
# Always key by session_id rather than trusting the parent dir to be
# session-scoped, so counts from one session can never leak into another.
if [ -n "$scratchpad_dir" ] && [ -d "$scratchpad_dir" ]; then
  state_dir="$scratchpad_dir/elixir-plus/$session_id"
else
  state_dir="${TMPDIR:-/tmp}/elixir-plus-error-critic/$session_id"
fi
mkdir -p "$state_dir" 2>/dev/null || exit 0

key=$(printf '%s' "$signature" | cksum 2>/dev/null | tr -d ' \n')
[ -n "$key" ] || exit 0
count_file="$state_dir/$key.count"
log_file="$state_dir/$key.log"

count=$(cat "$count_file" 2>/dev/null)
case "$count" in ''|*[!0-9]*) count=0 ;; esac
count=$((count + 1))
printf '%s' "$count" > "$count_file" 2>/dev/null

# Keep a short, bounded attempt history for the escalation message.
{
  printf 'attempt %s: %s\n' "$count" "$(printf '%s' "$message" | tr -s '[:space:]' ' ' | cut -c1-300)"
} >> "$log_file" 2>/dev/null
tail -n 10 "$log_file" > "$log_file.tmp" 2>/dev/null && mv "$log_file.tmp" "$log_file" 2>/dev/null

[ "$count" -ge "$THRESHOLD" ] 2>/dev/null || exit 0

history=$(cat "$log_file" 2>/dev/null)
attempted=$(printf '%s' "$target" | tr -s '[:space:]' ' ' | cut -c1-200)

reason=$(cat <<EOF
elixir-plus error-critic: this is failure #${count} of the SAME operation in this session.

Attempted: ${attempted}

History:
${history}

STOP retrying. Repeating a failing command with small variations is not progress.
Do one of these instead:
1. State the failure to the user and ask how to proceed, or
2. Change approach entirely -- read the failing source/test, or use runtime
   introspection (Tidewave) to inspect real state rather than guessing, or
3. Explain explicitly why the next attempt differs in kind, not in detail.

Do not claim the problem is fixed without running the verification and showing
its output.
EOF
)

jq -n --arg ctx "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUseFailure",
    additionalContext: $ctx
  },
  systemMessage: "elixir-plus: retry loop detected -- escalating instead of retrying."
}' 2>/dev/null

exit 0
