#!/usr/bin/env bash
# mix-test-wt.sh: run `mix test` or `mix precommit` in a git worktree without
# fighting the repository's other worktrees for CPU, memory or build output.
#
# Usage: mix-test-wt.sh [--precommit] [--lock-wait SECONDS] [-- <mix test args>]
#
# Run it from the Mix project root (the umbrella root for umbrellas).
#
# - Build path: <project>/_build when it is a real directory. Otherwise (missing
#   or a symlink) a stable per-worktree root under
#   ${XDG_CACHE_HOME:-~/.cache}/mix-build/, passed as MIX_BUILD_ROOT. It is kept
#   across runs; the first run in a worktree compiles from scratch. Another
#   checkout's build output is never copied, moved or re-linked, and a caller's
#   MIX_BUILD_PATH is dropped.
# - Lock: one flock per repository (all worktrees share it), held from before
#   compilation until the command ends. Default wait 1800 s (--lock-wait or
#   MIX_TEST_WT_LOCK_WAIT). On timeout it exits 75.
# - Environment: runs through `direnv exec .` when .envrc exists and
#   `mise exec --` when mise config exists. A caller's MIX_ENV and
#   MIX_TEST_PARTITION are kept; an unset MIX_TEST_PARTITION is derived from
#   the worktree directory name (skipped when --partitions is passed).
# - Test mode adds `--max-cases 4` unless the caller passed --max-cases.
#   --precommit runs `mix precommit` and accepts no test options.
# - The command's exit status is passed through unchanged.
#
# Exit codes of its own: 64 usage error, 69 flock missing, 75 lock wait timed out.

set -uo pipefail

PROG=mix-test-wt
DEFAULT_MAX_CASES=4

say() { printf '%s: %s\n' "$PROG" "$*" >&2; }
usage() {
  say "usage: mix-test-wt.sh [--precommit] [--lock-wait SECONDS] [-- <mix test args>]"
  exit 64
}

mode="test"
lock_wait=${MIX_TEST_WT_LOCK_WAIT:-1800}
mix_args=()

while [ $# -gt 0 ]; do
  case $1 in
    --precommit) mode=precommit; shift ;;
    --lock-wait)
      [ $# -ge 2 ] || usage
      lock_wait=$2; shift 2 ;;
    --lock-wait=*) lock_wait=${1#--lock-wait=}; shift ;;
    --) shift; mix_args=("$@"); break ;;
    -h|--help) usage ;;
    *) say "unknown option '$1' (put mix test arguments after --)"; usage ;;
  esac
done

case $lock_wait in
  ''|*[!0-9]*) say "--lock-wait must be a whole number of seconds, got '$lock_wait'"; exit 64 ;;
esac

if [ "$mode" = precommit ] && [ ${#mix_args[@]} -gt 0 ]; then
  say "--precommit takes no mix arguments; test options are never passed to aliases"
  exit 64
fi

if [ ! -f mix.exs ]; then
  say "no mix.exs in $PWD; run from the Mix project root"
  exit 64
fi

if ! command -v flock >/dev/null 2>&1; then
  say "flock not found (Linux: util-linux; macOS: brew install util-linux)"
  exit 69
fi

sha1() {
  if command -v sha1sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha1sum | cut -d' ' -f1
  else
    printf '%s' "$1" | shasum -a 1 | cut -d' ' -f1
  fi
}

project=$(pwd -P)
worktree=$(git rev-parse --show-toplevel 2>/dev/null) || worktree=$project
common_dir=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
  || common_dir=$project
cache_root=${XDG_CACHE_HOME:-$HOME/.cache}/mix-build
mkdir -p "$cache_root"

# --- build path -------------------------------------------------------------
if [ -d "$project/_build" ] && [ ! -L "$project/_build" ]; then
  build_root=$project/_build
else
  slug=$(printf '%s' "${project#/}" | tr -c 'A-Za-z0-9._-' '_')
  build_root=$cache_root/$slug-$(sha1 "$project" | cut -c1-8)
  mkdir -p "$build_root"
fi

# --- test partition ---------------------------------------------------------
has_arg() { # $1 = option name; matches "--opt" and "--opt=value"
  local a
  for a in "${mix_args[@]+"${mix_args[@]}"}"; do
    case $a in "$1"|"$1"=*) return 0 ;; esac
  done
  return 1
}

partition_set=${MIX_TEST_PARTITION+x}
partition=${MIX_TEST_PARTITION-}
if [ -z "$partition_set" ] && ! has_arg --partitions; then
  partition=_$(basename "$worktree" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_' '_' | cut -c1-40)
  partition_set=x
fi

# --- lock -------------------------------------------------------------------
lock_file=$cache_root/$(sha1 "$common_dir").lock
exec 9>>"$lock_file"

file_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }
fmt_epoch() { date -u -d "@$1" +%FT%TZ 2>/dev/null || date -u -r "$1" +%FT%TZ; }

wait_start=$(date +%s)
if flock -n 9; then
  lock_outcome=immediate
else
  holder=$(head -n1 "$lock_file" 2>/dev/null)
  say "waiting up to ${lock_wait}s for lock held since $(fmt_epoch "$(file_mtime "$lock_file")")${holder:+ ($holder)}"
  if flock -w "$lock_wait" 9; then
    lock_outcome=acquired-after-wait
  else
    say "lock wait timed out after ${lock_wait}s (exit 75). Report this to the user; do not rerun the same command unchanged while the other run holds the lock."
    exit 75
  fi
fi
waited=$(( $(date +%s) - wait_start ))
printf 'pid %s, %s, %s\n' "$$" "$mode" "$worktree" > "$lock_file"

# --- command ----------------------------------------------------------------
if [ "$mode" = precommit ]; then
  mix_cmd=(mix precommit)
else
  mix_cmd=(mix test)
  has_arg --max-cases || mix_cmd+=(--max-cases "$DEFAULT_MAX_CASES")
  mix_cmd+=("${mix_args[@]+"${mix_args[@]}"}")
fi

# Applied after direnv/mise so an .envrc cannot override what the caller set.
env_cmd=(env -u MIX_BUILD_PATH "MIX_BUILD_ROOT=$build_root")
[ -n "$partition_set" ] && env_cmd+=("MIX_TEST_PARTITION=$partition")
[ -n "${MIX_ENV+x}" ] && env_cmd+=("MIX_ENV=$MIX_ENV")

cmd=()
if [ -f .envrc ] && command -v direnv >/dev/null 2>&1; then
  cmd+=(direnv exec .)
fi
for f in mise.toml .mise.toml .config/mise.toml mise/config.toml .tool-versions; do
  if [ -f "$f" ] && command -v mise >/dev/null 2>&1; then
    cmd+=(mise exec --)
    break
  fi
done
cmd+=("${env_cmd[@]}" "${mix_cmd[@]}")

say "build=$build_root lock=$lock_outcome wait=${waited}s partition=${partition_set:+$partition} mode=$mode"

# Run in the background so TERM/INT/HUP sent to this wrapper reach mix too.
# The child does not inherit the lock fd, so a daemon it leaves behind cannot
# hold the lock forever. Stdin is passed through explicitly (async commands
# otherwise get /dev/null).
exec 8<&0
"${cmd[@]}" 0<&8 8<&- 9>&- &
child=$!
exec 8<&-
trap 'kill -TERM "$child" 2>/dev/null' TERM INT HUP

while :; do
  wait "$child"
  status=$?
  kill -0 "$child" 2>/dev/null || break
done

if [ "$status" -gt 128 ] && [ "$status" -le 192 ]; then
  sig=$(kill -l "$((status - 128))" 2>/dev/null || echo "$((status - 128))")
  say "mix was killed by SIG${sig#SIG} (exit $status). The cause is not known; if SIGKILL, OOM is one possible cause, so check free -m and system logs before retrying."
fi

exit "$status"
