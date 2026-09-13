#!/usr/bin/env bash
# PreToolUse guard: deny destructive Elixir/git commands before they run.
#
# Fail-open by design: no `set -e`. A crash in this hook must never wedge a
# session, so every failure path falls through to exit 0 (normal permission
# flow). Denials are expressed as JSON data, not exit codes.

input=$(cat 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0

command=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -n "$command" ] || exit 0

deny() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }' 2>/dev/null
  exit 0
}

# Split on shell separators and test each segment on its own, so a flag in one
# segment cannot be attributed to a command in another
# (e.g. `grep -f pats.txt && git push` must NOT read as a force push).
segments=$(printf '%s' "$command" \
  | tr '\n' ' ' \
  | sed -e 's/&&/\n/g' -e 's/||/\n/g' -e 's/;/\n/g' -e 's/|/\n/g')

while IFS= read -r segment; do
  seg=" $(printf '%s' "$segment" | tr -s '[:space:]' ' ') "

  # --- Ecto: irreversible database destruction -----------------------------
  if [[ "$seg" =~ [[:space:]]mix[[:space:]]+ecto\.(drop|reset)([[:space:]]) ]]; then
    deny "elixir-plus: 'mix ecto.${BASH_REMATCH[1]}' destroys the database. If you genuinely need it, ask the user to run it themselves; for a reversible step use 'mix ecto.rollback'."
  fi

  # --- Production environment ----------------------------------------------
  if [[ "$seg" =~ [[:space:]]MIX_ENV=[\"\']?prod ]]; then
    deny "elixir-plus: MIX_ENV=prod commands are blocked. Production work goes through the deploy pipeline, not an agent shell. Use MIX_ENV=dev or MIX_ENV=test."
  fi

  # --- Force push -----------------------------------------------------------
  # --force-with-lease is the safe variant and stays allowed.
  if [[ "$seg" =~ [[:space:]]git[[:space:]]+push[[:space:]] ]]; then
    if [[ "$seg" =~ [[:space:]](--force|-f)[[:space:]] ]]; then
      deny "elixir-plus: 'git push --force' can destroy remote history. Use '--force-with-lease' instead, which refuses to clobber commits you have not seen."
    fi
  fi
done <<< "$segments"

exit 0
