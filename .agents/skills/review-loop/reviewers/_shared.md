# Running a reviewer: the shared procedure

**Not a reviewer.** `--reviewer` never names this file; the underscore marks it. Every reviewer file in this
directory gives its own invocation, flags and failure signals, and is run and decided as below.

## Background run and polling

The run exceeds the foreground command cap, so launch it as **one Bash call with `run_in_background: true`**
(the Claude Code flag `release` uses for the same kind of long command), with stdout and the exit code
captured to the scratchpad. The **30-minute deadline** is the script's own: macOS ships no `timeout` and a
reviewer CLI has no wall-clock limit to rely on, so a shell watchdog kills the run and records exit `124`
itself — the same code `timeout` would give.

Pass **`timeout: 2100000`** (35 minutes) on the Bash call. A session Claude Code runs unattended — `-p`, an
Agent SDK application, CI, a cloud session — stops a background command at a limit of its own, 30 minutes by
default and 10 in a `-p` run. A limit at or under the watchdog's ends the script before it records anything,
and a real timeout then reads as a transport failure. In another harness, give the background command a
limit above 30 minutes by whatever means it has.

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

Record the start time first (`date -u +%FT%TZ`); [Deciding the run](#deciding-the-run) compares against it.
The background call reports back when the script exits; until then, poll for the exit file and edit nothing
in the child's tree.

## Deciding the run

Every provider is decided by this one table. The reviewer file's **Failure signals** section supplies the
two provider-specific terms the table uses: what a **transport failure** looks like in that CLI's result,
and any **provider stop**.

First check the PR, from the child's directory, for a review posted since the start time whose body ends in
`— Reviewed by <name> …` (the `reviews` endpoint in
[`../../review-changes/gh-commands.md`](../../review-changes/gh-commands.md)). Then read the exit code and
the result as the reviewer file says.

| Observation | Meaning | Action |
| --- | --- | --- |
| Footer-bearing review newer than the start time | the review ran | read its outcome; the exit code is irrelevant |
| No such review, exit `124` | timeout | stop the loop |
| No such review, a provider stop matches | the stop the reviewer file names | stop the loop; report it in the reviewer file's words |
| No such review, a transport failure signal | transport failure | retry once, same invocation; this row again on the retry is a reviewer failure: stop the loop |
| No such review, no row above matches | the agent ran to completion but posted nothing | stop the loop; report that the agent finished without a footer-bearing review |

Rows are tested top to bottom; the first match rules. A retry's result is tested against the same table from
the top.

Only a transport failure is retried:

- **A review that ran** would post a duplicate set of findings under the same tag on a second `first` round,
  whatever the CLI reported.
- **An agent that finished without posting** would repeat the same thirty minutes to the same end.
- **A provider stop** is tested before the transport row because the reviewer file names it as a condition a
  retry does not clear.
