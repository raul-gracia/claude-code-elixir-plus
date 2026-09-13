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

# Split on every shell separator, including newline -- the most common one in
# multi-line scripts. `tr` is used rather than `sed s/…/\n/` because BSD sed
# (macOS) emits a literal "n" for \n in the replacement and would not split at
# all. `&&` and `||` collapse to two separators, which just yields an empty
# segment.
segments=$(printf '%s' "$command" | tr ';|&\n' '\n\n\n\n')

while IFS= read -r segment; do
  [ -n "$segment" ] || continue

  # Quotes, parens and backticks become whitespace so that wrappers such as
  # `bash -c "mix ecto.drop"`, `eval '...'` and `(mix ecto.drop)` are scanned
  # as ordinary words instead of sliding past the word-boundary anchors.
  seg=" $(printf '%s' "$segment" | tr '"'"'"'`()' '     ' | tr -s '[:space:]' ' ') "

  # Printing a command is not running it; skip pure output builtins so that
  # documentation and echoed examples are not denied.
  case "$seg" in
    ' echo '*|' printf '*|' cat '*|' #'*) continue ;;
  esac

  # --- Ecto: irreversible database destruction -----------------------------
  if [[ "$seg" =~ [[:space:]]mix[[:space:]]+ecto\.(drop|reset)([[:space:]]|$) ]]; then
    deny "elixir-plus: 'mix ecto.${BASH_REMATCH[1]}' destroys the database. If you genuinely need it, ask the user to run it themselves; for a reversible step use 'mix ecto.rollback'."
  fi

  # --- Production environment ----------------------------------------------
  if [[ "$seg" =~ [[:space:]]MIX_ENV=[[:space:]]*prod([[:space:]]|$) ]]; then
    deny "elixir-plus: MIX_ENV=prod commands are blocked. Production work goes through the deploy pipeline, not an agent shell. Use MIX_ENV=dev or MIX_ENV=test."
  fi

  # --- Force push -----------------------------------------------------------
  # `git` and `push` are matched separately so global options between them
  # (`git -c x=y push --force`) cannot slip through.
  if [[ "$seg" =~ [[:space:]]git[[:space:]] && "$seg" =~ [[:space:]]push([[:space:]]|$) ]]; then
    force=""
    # --force-with-lease is the safe variant: whole-token matching leaves it
    # alone while still catching bare --force.
    [[ "$seg" =~ [[:space:]](--force|-f)([[:space:]]|$) ]] && force="--force"
    [[ "$seg" =~ [[:space:]]--mirror([[:space:]]|$) ]] && force="--mirror"
    # A leading `+` on a refspec is a force push by another name.
    [[ "$seg" =~ [[:space:]]\+[A-Za-z0-9_/.-]+:?([[:space:]]|$) ]] && force="a '+refspec'"
    if [ -n "$force" ]; then
      deny "elixir-plus: 'git push' with ${force} can destroy remote history. Use '--force-with-lease' instead, which refuses to clobber commits you have not seen."
    fi
  fi
done <<< "$segments"

exit 0
