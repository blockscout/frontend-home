# Reviewer: `cursor`

The Cursor CLI (`agent`) running home's `review-changes` skill headlessly against the loop's child. Tag:
`cursor`, passed as `--as cursor` on every run.

## Invocation

```bash
agent -p --trust --approve-mcps --output-format json [--model <id>] \
  "/review-changes pr --as cursor --child <child> [--round follow-up]"
```

- `--child <child>` on every run, the child the loop settled. A headless run has nobody to ask for it.
- `--round follow-up` on every round after the first; the first round passes no `--round`.
- `--model <id>` only when the loop was given one. Otherwise Cursor's default model.
- `--trust --approve-mcps` are mandatory: trust and MCP approval are per absolute path, so a fresh
  worktree prompts without them and a headless run hangs on the prompt.
- Run from the **home worktree root**: the home root, or the task worktree's root when the loop runs in
  one. Never from the child. Cursor loads home's `.agents/skills/` natively there and the slash invocation
  attaches the skill; the child is reached as a directory inside the workspace, so neither `--workspace`
  nor `--add-dir` is needed.

## Running it

Launch the invocation in the background, under the watchdog, and poll it as [`_shared.md`](_shared.md)
says.

## Failure detection

Read the exit code and stdout, then check the PR, from the child's directory, for a review posted since the start time whose body ends
in `— Reviewed by cursor …` (the `reviews` endpoint in
[`../../review-changes/gh-commands.md`](../../review-changes/gh-commands.md)).

| Observation | Meaning | Action |
| --- | --- | --- |
| Footer-bearing review newer than the start time | the review ran | read its outcome; the exit code is irrelevant |
| No such review, exit `124` | timeout | stop the loop |
| No such review, exit non-zero other than `124`, or empty stdout | transport failure | retry once, same invocation; this row again on the retry is a reviewer failure: stop the loop |
| No such review, exit `0`, non-empty stdout | the agent ran to completion but posted nothing | stop the loop; report that the agent finished without a footer-bearing review |

The table is read as [`_shared.md`](_shared.md#reading-a-failure-table) says.
