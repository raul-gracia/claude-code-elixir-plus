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

# A cancelled or user-denied tool call is not the model failing to make
# progress. Counting those turns three presses of Esc into "you are in a retry
# loop", which blames the user for their own interruption.
[ "$(jqget '.is_interrupt')" = "true" ] && exit 0

session_id=$(jqget '.session_id')
scratchpad_dir=$(jqget '.scratchpad_dir')
tool_name=$(jqget '.tool_name')
[ -n "$tool_name" ] || tool_name="unknown"
# session_id lands in a filesystem path; never let it traverse.
case "$session_id" in
  ''|*[!A-Za-z0-9_-]*) session_id="nosession" ;;
esac

# Target identifies *what* was attempted; message identifies *how* it broke.
target=$(jqget '.tool_input.command // .tool_input.file_path // .tool_input.filePath')
# Claude Code delivers the failure as a top-level `.error` string; the other
# shapes are documented variants kept as fallbacks. Verified against a live
# PostToolUseFailure payload.
message=$(jqget '.error // .tool_error.error.message // .tool_error.message // .tool_response.text')

[ -n "$target$message" ] || exit 0

case "$message" in
  *"doesn't want to proceed"*|*"user doesn't want"*|*"Request interrupted"*) exit 0 ;;
esac

# Normalise so cosmetically-different repeats of the same failure collapse:
# lowercase, drop the directory prefix but KEEP the last two path segments (so
# lib/a/user.ex and lib/b/user.ex stay distinct), collapse digits.
normalise() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -e 's#/[^ ]*/\([^/ ][^/ ]*/[^/ ][^/ ]*\)#\1#g' -e 's/[0-9][0-9]*/N/g' \
    | tr -s '[:space:]' ' ' \
    | cut -c1-400
}

signature=$(printf '%s|%s|%s' "$tool_name" "$(normalise "$target")" "$(normalise "$message")")

# State must never land in the user's project. Prefer the session scratchpad,
# then an XDG/HOME-rooted private dir; /tmp is a last resort because a fixed
# path there is world-predictable on a shared box.
if [ -n "$scratchpad_dir" ] && [ -d "$scratchpad_dir" ]; then
  state_root="$scratchpad_dir/elixir-plus"
elif [ -n "${XDG_STATE_HOME:-}" ]; then
  state_root="$XDG_STATE_HOME/elixir-plus/error-critic"
elif [ -n "${HOME:-}" ]; then
  state_root="$HOME/.local/state/elixir-plus/error-critic"
else
  state_root="${TMPDIR:-/tmp}/elixir-plus-error-critic-$(id -u 2>/dev/null)"
fi
state_dir="$state_root/$session_id"
mkdir -p "$state_dir" 2>/dev/null || exit 0
chmod 700 "$state_root" 2>/dev/null

# Hash with a separator so that cksum's "<crc> <bytes>" pair cannot merge two
# different signatures into one key (12/345 vs 123/45).
hash_of() {
  if command -v sha1sum >/dev/null 2>&1; then printf '%s' "$1" | sha1sum | cut -d' ' -f1
  elif command -v shasum  >/dev/null 2>&1; then printf '%s' "$1" | shasum  | cut -d' ' -f1
  elif command -v md5sum  >/dev/null 2>&1; then printf '%s' "$1" | md5sum  | cut -d' ' -f1
  else printf '%s' "$1" | cksum | tr ' ' '-' | tr -d '\n'
  fi
}
key=$(hash_of "$signature")
[ -n "$key" ] || exit 0

count_file="$state_dir/$key.count"
log_file="$state_dir/$key.log"

# Serialise the read-modify-write; parallel tool calls can otherwise both read
# the same count and lose an increment, making the threshold fire late.
lock_dir="$state_dir/$key.lock"
locked=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if mkdir "$lock_dir" 2>/dev/null; then locked="yes"; break; fi
  command -v sleep >/dev/null 2>&1 && sleep 0.05
done
release_lock() { [ -n "$locked" ] && rmdir "$lock_dir" 2>/dev/null; }
trap release_lock EXIT

count=$(cat "$count_file" 2>/dev/null)
case "$count" in ''|*[!0-9]*) count=0 ;; esac
count=$((count + 1))

{
  printf 'attempt %s: %s\n' "$count" "$(printf '%s' "$message" | tr -s '[:space:]' ' ' | cut -c1-300)"
} >> "$log_file" 2>/dev/null
tail -n 10 "$log_file" > "$log_file.tmp" 2>/dev/null && mv "$log_file.tmp" "$log_file" 2>/dev/null

if [ "$count" -lt "$THRESHOLD" ] 2>/dev/null; then
  printf '%s' "$count" > "$count_file" 2>/dev/null
  exit 0
fi

history=$(cat "$log_file" 2>/dev/null)
attempted=$(printf '%s' "$target" | tr -s '[:space:]' ' ' | cut -c1-200)

# Reset after escalating. Otherwise every later failure of the same signature
# re-injects "STOP retrying", with no way for the user to say "keep going".
printf '0' > "$count_file" 2>/dev/null
: > "$log_file" 2>/dev/null
release_lock

reason=$(cat <<EOF
elixir-plus error-critic: that is ${count} failures of the SAME operation in this session.

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
