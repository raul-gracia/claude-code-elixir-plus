#!/usr/bin/env bash
# report() always returns 0, so `[ test ] && report ok || report fail` is safe.
# shellcheck disable=SC2015
# Tests for skills/elixir-runtime/scripts/mix-test-wt.sh with mocked mix,
# direnv and mise on PATH, against real git worktrees in a temp dir.
# Usage: tests/mix-test-wt/run.sh
set -uo pipefail

WRAPPER="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../plugins/elixir-plus/skills/elixir-runtime/scripts" && pwd)/mix-test-wt.sh"
pass=0; fail=0

report() {
  if [ "$1" = "ok" ]; then
    pass=$((pass + 1)); printf '  ok   %s\n' "$2"
  else
    fail=$((fail + 1)); printf '  FAIL %s\n     %s\n' "$2" "$3"
  fi
}
check() { # $1 = name, $2 = haystack, $3 = needle
  case $2 in *"$3"*) report ok "$1" ;; *) report fail "$1" "expected '$3' in: $2" ;; esac
}
check_not() {
  case $2 in *"$3"*) report fail "$1" "did not expect '$3' in: $2" ;; *) report ok "$1" ;; esac
}
check_eq() {
  [ "$2" = "$3" ] && report ok "$1" || report fail "$1" "expected '$3', got '$2'"
}

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export XDG_CACHE_HOME="$T/cache"
export HOME="$T/home"; mkdir -p "$HOME"
BIN="$T/bin"; mkdir -p "$BIN"

# Fake mix: logs argv and the Mix env it sees, then behaves per FAKE_MIX_*.
cat > "$BIN/mix" <<'EOF'
#!/usr/bin/env bash
{
  printf 'ARGS=%s\n' "$*"
  printf 'MIX_ENV=%s\n' "${MIX_ENV-<unset>}"
  printf 'MIX_TEST_PARTITION=%s\n' "${MIX_TEST_PARTITION-<unset>}"
  printf 'MIX_BUILD_ROOT=%s\n' "${MIX_BUILD_ROOT-<unset>}"
  printf 'MIX_BUILD_PATH=%s\n' "${MIX_BUILD_PATH-<unset>}"
  printf 'VIA=%s\n' "${FAKE_VIA-}"
} > "${FAKE_MIX_LOG:?}"
# FAKE_MIX_HOLD=<file>: keep running (holding the lock) until <file> exists;
# the 60 s watchdog turns a broken test into a failure, not a hang. The TERM
# trap goes in before the started marker so a test never signals too early.
[ -n "${FAKE_MIX_HOLD-}" ] && trap '[ -n "${FAKE_MIX_TERMED-}" ] && : > "$FAKE_MIX_TERMED"; exit 143' TERM
[ -n "${FAKE_MIX_STARTED-}" ] && : > "$FAKE_MIX_STARTED"
if [ -n "${FAKE_MIX_HOLD-}" ]; then
  for _ in $(seq 600); do [ -e "$FAKE_MIX_HOLD" ] && break; sleep 0.1; done
fi
[ -n "${FAKE_MIX_SIGNAL-}" ] && kill -"$FAKE_MIX_SIGNAL" $$
exit "${FAKE_MIX_EXIT:-0}"
EOF
# Fake direnv/mise: record that they wrapped the call, export what an .envrc
# might, then run the rest of the command line.
cat > "$BIN/direnv" <<'EOF'
#!/usr/bin/env bash
[ "$1" = exec ] && [ "$2" = . ] || exit 99
shift 2
if [ -n "${FAKE_DIRENV_BLOCKED-}" ]; then echo "direnv: error .envrc is blocked" >&2; exit 1; fi
export FAKE_VIA="${FAKE_VIA-}direnv;" MIX_ENV=from_envrc MIX_BUILD_PATH=/tmp/from_envrc
exec "$@"
EOF
cat > "$BIN/mise" <<'EOF'
#!/usr/bin/env bash
[ "$1" = exec ] && [ "$2" = -- ] || exit 99
shift 2
export FAKE_VIA="${FAKE_VIA-}mise;"
exec "$@"
EOF
chmod +x "$BIN"/*
export PATH="$BIN:/usr/local/bin:/usr/bin:/bin"
unset MIX_ENV MIX_TEST_PARTITION MIX_BUILD_PATH MIX_BUILD_ROOT MIX_TEST_WT_LOCK_WAIT

# One repository with a main checkout and two linked worktrees.
git -c init.defaultBranch=main init -q "$T/repo"
( cd "$T/repo" && echo 'defmodule P.MixProject do end' > mix.exs \
  && git add mix.exs && git -c user.name=t -c user.email=t@t commit -qm init \
  && git worktree add -q "$T/wt-PLAT-1886" -b a && git worktree add -q "$T/wt-b" -b b )

run() { # $1 = dir, then optional VAR=value env, then wrapper args; sets OUT, ERR, RC, MIXLOG
  local dir=$1 envs=(); shift
  while [ $# -gt 0 ] && [[ $1 =~ ^[A-Z_]+= ]]; do envs+=("$1"); shift; done
  LOG="$T/mix.log"; rm -f "$LOG"
  ( cd "$dir" && env FAKE_MIX_LOG="$LOG" "${envs[@]}" "$WRAPPER" "$@" ) >"$T/out" 2>"$T/err"
  RC=$?
  ERR=$(cat "$T/err")
  [ -f "$LOG" ] && MIXLOG=$(cat "$LOG") || MIXLOG=""
}

echo "argument forwarding"
run "$T/wt-b" -- test/foo_test.exs:12 --only focus
check "test args forwarded after --max-cases 4" "$MIXLOG" "ARGS=test --max-cases 4 test/foo_test.exs:12 --only focus"
check_eq "exit 0 passes through" "$RC" 0
check "status line names the build path" "$ERR" "build=$XDG_CACHE_HOME/mix-build/"
check "status line reports an uncontended lock" "$ERR" "lock=immediate wait="
run "$T/wt-b" -- --max-cases 8 test/x_test.exs
check "caller --max-cases wins" "$MIXLOG" "ARGS=test --max-cases 8 test/x_test.exs"
run "$T/wt-b" -- --max-cases=2
check "caller --max-cases=N wins" "$MIXLOG" "ARGS=test --max-cases=2"
run "$T/wt-b" --precommit
check "precommit runs bare mix precommit" "$MIXLOG" "ARGS=precommit"
check_not "precommit gets no --max-cases" "$MIXLOG" "max-cases"
run "$T/wt-b" --precommit -- --only focus
check_eq "precommit refuses test options (64)" "$RC" 64
check_eq "precommit with options never runs mix" "$MIXLOG" ""
run "$T/wt-b" --bogus
check_eq "unknown option is a usage error" "$RC" 64

echo "build path"
run "$T/wt-b"
check "missing _build uses the cache root" "$MIXLOG" "MIX_BUILD_ROOT=$XDG_CACHE_HOME/mix-build/"
first_root=$(sed -n 's/^MIX_BUILD_ROOT=//p' "$LOG")
[ -d "$first_root" ] && report ok "cache build root is created" || report fail "cache build root is created" "$first_root"
run "$T/wt-b"
check_eq "cache build root is stable across runs" "$(sed -n 's/^MIX_BUILD_ROOT=//p' "$LOG")" "$first_root"
mkdir -p "$T/repo/_build/test"
ln -s "$T/repo/_build" "$T/wt-PLAT-1886/_build"
run "$T/wt-PLAT-1886"
check "symlinked _build uses the cache root" "$MIXLOG" "MIX_BUILD_ROOT=$XDG_CACHE_HOME/mix-build/"
[ -L "$T/wt-PLAT-1886/_build" ] && report ok "symlink is left untouched" || report fail "symlink is left untouched" "symlink changed"
[ "$(sed -n 's/^MIX_BUILD_ROOT=//p' "$LOG")" != "$first_root" ] && report ok "each worktree gets its own cache root" \
  || report fail "each worktree gets its own cache root" "shared $first_root"
mkdir -p "$T/wt-b/_build/dev"
run "$T/wt-b"
check_eq "cache root stays once chosen, even if a real _build appears" "$(sed -n 's/^MIX_BUILD_ROOT=//p' "$LOG")" "$first_root"
rmdir "$T/wt-b/_build/dev" "$T/wt-b/_build"
long="$T/$(printf 'deep-directory-name-%03d/' $(seq 1 14))proj"
mkdir -p "$long" && echo x > "$long/mix.exs"
run "$long"
check_eq "very long project path still runs" "$RC" 0
name=$(sed -n 's/^MIX_BUILD_ROOT=//p' "$LOG"); name=${name##*/}
[ "${#name}" -le 120 ] && report ok "cache dir name stays short" || report fail "cache dir name stays short" "${#name} chars"
mkdir -p "$T/repo/_build"
run "$T/repo"
check "real _build directory is used" "$MIXLOG" "MIX_BUILD_ROOT=$T/repo/_build"
run "$T/repo" MIX_BUILD_PATH=/tmp/fresh-build
check "caller MIX_BUILD_PATH is dropped" "$MIXLOG" "MIX_BUILD_PATH=<unset>"

echo "environment"
run "$T/wt-PLAT-1886"
check_eq "partition derived from worktree name" "$(sed -n 's/^MIX_TEST_PARTITION=//p' "$LOG")" "_wt_plat_1886"
check "MIX_ENV left unset" "$MIXLOG" "MIX_ENV=<unset>"
run "$T/wt-b" MIX_TEST_PARTITION=7 MIX_ENV=ci
check "caller MIX_TEST_PARTITION kept" "$MIXLOG" "MIX_TEST_PARTITION=7"
check "caller MIX_ENV kept" "$MIXLOG" "MIX_ENV=ci"
run "$T/wt-b" -- --partitions 4
check "no partition derived with --partitions" "$MIXLOG" "MIX_TEST_PARTITION=<unset>"
echo 'export FOO=1' > "$T/wt-b/.envrc"
echo '[tools]' > "$T/wt-b/mise.toml"
run "$T/wt-b" MIX_ENV=ci
check "runs through direnv then mise" "$MIXLOG" "VIA=direnv;mise;"
check "caller MIX_ENV beats .envrc" "$MIXLOG" "MIX_ENV=ci"
check "MIX_BUILD_PATH from .envrc is dropped" "$MIXLOG" "MIX_BUILD_PATH=<unset>"
run "$T/wt-b"
check "MIX_ENV from .envrc applies when caller set none" "$MIXLOG" "MIX_ENV=from_envrc"
run "$T/wt-b" FAKE_DIRENV_BLOCKED=1
check_eq "blocked .envrc exits 78" "$RC" 78
check "blocked .envrc says how to fix it" "$ERR" "direnv allow"
check_eq "blocked .envrc never runs mix" "$MIXLOG" ""
rm "$T/wt-b/.envrc" "$T/wt-b/mise.toml"
mkdir -p "$T/wt-b/.config/mise" && echo '[tools]' > "$T/wt-b/.config/mise/config.toml"
run "$T/wt-b"
check "mise config under .config/mise/ is found" "$MIXLOG" "VIA=mise;"
rm -r "$T/wt-b/.config"
run "$T/wt-b"
check_eq "no direnv/mise without their config" "$(sed -n 's/^VIA=//p' "$LOG")" ""

echo "exit status and signals"
run "$T/wt-b" FAKE_MIX_EXIT=3
check_eq "failure status passes through" "$RC" 3
check_not "plain failure prints no kill notice" "$ERR" "killed"
run "$T/wt-b" FAKE_MIX_SIGNAL=KILL
check_eq "SIGKILL passes through as 137" "$RC" 137
check "kill notice names SIGKILL" "$ERR" "killed by SIGKILL (exit 137)"
check "kill notice does not claim OOM" "$ERR" "OOM is one possible cause"
check_eq "kill notice is one line" "$(grep -c killed "$T/err")" 1
run "$T/wt-b" FAKE_MIX_SIGNAL=TERM
check_eq "SIGTERM passes through as 143" "$RC" 143

wait_for() { # $1 = file, optional $2 = text it must contain; up to 10 s
  for _ in $(seq 100); do
    if [ -e "$1" ] && { [ -z "${2-}" ] || grep -qF -- "$2" "$1"; }; then return 0; fi
    sleep 0.1
  done
  return 1
}

# TERM sent to the wrapper reaches mix and the wrapper reports mix's status.
( cd "$T/wt-b" && FAKE_MIX_LOG="$T/term.log" FAKE_MIX_STARTED="$T/term.started" \
    FAKE_MIX_HOLD="$T/term.never" FAKE_MIX_TERMED="$T/term.termed" exec "$WRAPPER" >/dev/null 2>&1 ) &
wpid=$!
wait_for "$T/term.started"
kill -TERM "$wpid"
wait "$wpid"; rc=$?
[ -e "$T/term.termed" ] && report ok "TERM to the wrapper reaches mix" || report fail "TERM to the wrapper reaches mix" "mix saw no TERM"
check_eq "wrapper exits with mix's TERM status" "$rc" 143

echo "lock"
lock_holder() { # start a run in worktree $1 whose mix holds the lock until release_holder
  rm -f "$T/held.started" "$T/release"
  ( cd "$1" && FAKE_MIX_LOG="$T/held.log" FAKE_MIX_STARTED="$T/held.started" FAKE_MIX_HOLD="$T/release" \
      exec "$WRAPPER" >/dev/null 2>&1 ) &
  HOLDER=$!
  wait_for "$T/held.started"
}
release_holder() { : > "$T/release"; wait "$HOLDER" 2>/dev/null; }

lock_holder "$T/wt-PLAT-1886"
run "$T/wt-b" --lock-wait 1
check_eq "lock timeout exits 75" "$RC" 75
check "timeout message says not to rerun unchanged" "$ERR" "do not rerun the same command unchanged"
check "waiting line shows lock age" "$ERR" "waiting up to 1s for lock held since 20"
check "waiting line names the holder" "$ERR" "$T/wt-PLAT-1886"
check_eq "timed-out run never starts mix" "$MIXLOG" ""
release_holder

# The main checkout waits for a linked worktree's run, then proceeds.
lock_holder "$T/wt-PLAT-1886"
rm -f "$T/c.log" "$T/c.err"
( cd "$T/repo" && FAKE_MIX_LOG="$T/c.log" exec "$WRAPPER" --lock-wait 30 >/dev/null 2>"$T/c.err" ) &
cpid=$!
wait_for "$T/c.err" "waiting up to 30s" && report ok "main checkout waits on a worktree's lock" \
  || report fail "main checkout waits on a worktree's lock" "no waiting line"
[ ! -e "$T/c.log" ] && report ok "waiting run does not start mix while the lock is held" \
  || report fail "waiting run does not start mix while the lock is held" "mix started"
release_holder
wait "$cpid"; rc=$?
check_eq "contended run succeeds once the lock is released" "$rc" 0
check "status line reports the contended lock" "$(cat "$T/c.err")" "lock=acquired-after-wait wait="

# SIGKILL to the wrapper: mix keeps running and keeps the lock.
lock_holder "$T/wt-PLAT-1886"
kill -KILL "$HOLDER"; wait "$HOLDER" 2>/dev/null
run "$T/wt-b" --lock-wait 1
check_eq "lock stays held by mix after the wrapper is SIGKILLed" "$RC" 75
: > "$T/release"
run "$T/wt-b" --lock-wait 10
check_eq "lock is released once the orphaned mix exits" "$RC" 0

git -c init.defaultBranch=main init -q "$T/other"; echo x > "$T/other/mix.exs"
lock_holder "$T/wt-PLAT-1886"
run "$T/other" --lock-wait 1
check_eq "a different repository has its own lock" "$RC" 0
release_holder

run "$T/wt-b" --lock-wait abc
check_eq "non-numeric --lock-wait is a usage error" "$RC" 64

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
