# Running a reviewer: the shared procedure

**Not a reviewer.** `--reviewer` never names this file; the underscore marks it. Every reviewer file in this
directory gives its own invocation, flags and failure table, and is run and read as below.

## Background run and polling

The run exceeds the foreground command cap, so launch it as **one Bash call with `run_in_background: true`**
(the Claude Code flag `release` uses for the same kind of long command), with stdout and the exit code
captured to the scratchpad. The **30-minute deadline** is the script's own: macOS ships no `timeout` and a
reviewer CLI has no wall-clock limit to rely on, so a shell watchdog kills the run and records exit `124`
itself — the same code `timeout` would give. Pass no `timeout` on the Bash call: a tool limit at or under
the watchdog's would end the script before it could record anything, and a real timeout would read as a
transport failure.

```bash
rm -f <scratchpad>/review-<round>.{json,err,exit,timeout}
<invocation> \
  > <scratchpad>/review-<round>.json 2> <scratchpad>/review-<round>.err &
pid=$!
( sleep 1800 && kill "$pid" 2>/dev/null && echo 124 > <scratchpad>/review-<round>.timeout ) &
watchdog=$!
wait "$pid"; rc=$?
kill "$watchdog" 2>/dev/null
[ -f <scratchpad>/review-<round>.timeout ] && rc=124
echo "$rc" > <scratchpad>/review-<round>.exit
```

`<invocation>` is the command from the reviewer file's Invocation section, filled in per the rules under it
— this script is what runs, so a round-2 run without `--round follow-up` is a second `first` round. The
first line clears what an earlier run left under the same names: a retry of the same round, or another loop
in the same session, would otherwise find a stale exit file and read it as its own.

Record the start time first (`date -u +%FT%TZ`); the outcome check in the reviewer file compares against it.
The background call reports back when the script exits; until then, poll for the exit file and edit nothing
in the child's tree.

## Reading a failure table

Rows are tested top to bottom; the first match rules. A retry's result is tested against the same table from
the top.

A review that ran gets no retry, whatever the CLI reported: a second `first` round would post a duplicate
set of findings under the same tag. Nor does an agent that finished without posting — the retry would repeat
the same thirty minutes to the same end.
