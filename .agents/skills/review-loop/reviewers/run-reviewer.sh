#!/bin/bash
# Runs one reviewer round under a 30-minute watchdog and records its result files.
# `_shared.md` beside this file says how to call it and how to read what it leaves.
#
# Usage: run-reviewer.sh <round> <output dir> <invocation...>
#
# Leaves in <output dir>: review-<round>.json (stdout), .err (stderr), .exit (exit code, 124 on a
# timeout) and .timeout (only when the watchdog fired).

round="$1"
out="$2"
shift 2

if [ -z "$round" ] || [ ! -d "$out" ] || [ $# -eq 0 ]; then
  echo "usage: run-reviewer.sh <round> <output dir> <invocation...>" >&2
  exit 2
fi

# A retry of the same round, or another loop in the same session, must not read a stale exit file.
rm -f "$out/review-$round".{json,err,exit,timeout}

"$@" > "$out/review-$round.json" 2> "$out/review-$round.err" &
pid=$!

# macOS ships no `timeout`, so the deadline is kept here. 124 is the code `timeout` would give.
( sleep 1800 && kill "$pid" 2>/dev/null && echo 124 > "$out/review-$round.timeout" ) &
watchdog=$!

wait "$pid"
rc=$?
kill "$watchdog" 2>/dev/null
[ -f "$out/review-$round.timeout" ] && rc=124
echo "$rc" > "$out/review-$round.exit"
