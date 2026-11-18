# Reviewer: `claude-code`

The Claude Code CLI (`claude`) running home's `review-changes` skill headlessly against the loop's child.
Tag: `claude-code`, passed as `--as claude-code` on every run.

The reviewer is its own `claude -p` process, started from Bash. When the loop itself runs in Claude Code,
that process is what gives the review a fresh context: a subagent of the loop's session is not a substitute.

## Invocation

```bash
claude -p --output-format json --permission-mode auto --strict-mcp-config \
  --model <id> --effort high --name review-<child>-<PR number>-r<round> \
  "/review-changes pr --as claude-code --child <child> [--round follow-up]"
```

- `--child <child>` on every run, the child the loop settled. A headless run has nobody to ask for it.
- `--round follow-up` on every round after the first; the first round passes no `--round`.
- `--model <id>` is the loop's `--model` when it was given one. Otherwise `claude-opus-5-5`.
- `--permission-mode auto` is mandatory. A `-p` run denies every tool call that would prompt, and the
  project's allow rules do not load in a worktree that was never trusted. Auto mode rules on each call
  instead, and a call it refuses is recorded in the result's `permission_denials`.
- `--strict-mcp-config` with no `--mcp-config` loads no MCP server. The review needs none.
- `--name` keeps the session findable: `claude --resume review-<child>-<PR number>-r<round>` opens a round
  that went wrong. The child is in the name because home and a child can share a PR number, and both run
  from the same root.
- Run from the **home worktree root**: the home root, or the task worktree's root when the loop runs in
  one. Never from the child. Claude Code loads home's `.claude/skills/` there and the slash invocation
  attaches the skill; the child is reached as a directory inside the workspace, so `--add-dir` is not
  needed. `-p` skips the trust dialog, so a fresh worktree does not prompt.

## Running it

Launch the invocation in the background, under the watchdog, and poll it as [`_shared.md`](_shared.md)
says.

## Failure detection

Read the exit code and the result, then check the PR, from the child's directory, for a review posted since
the start time whose body ends in `— Reviewed by claude-code …` (the `reviews` endpoint in
[`../../review-changes/gh-commands.md`](../../review-changes/gh-commands.md)).

```bash
jq '{is_error, subtype, denied: [.permission_denials[]?.tool_name]}' <scratchpad>/review-<round>.json
```

| Observation | Meaning | Action |
| --- | --- | --- |
| Footer-bearing review newer than the start time | the review ran | read its outcome; the exit code is irrelevant |
| No such review, exit `124` | timeout | stop the loop |
| No such review, `denied` non-empty | no review; denials present | stop the loop; report `no review; denials present:` and the denied tools |
| No such review, and exit non-zero other than `124`, empty stdout, or `is_error: true` | transport failure | retry once, same invocation; this row again on the retry is a reviewer failure: stop the loop |
| No such review, exit `0`, `is_error: false` | the agent ran to completion but posted nothing | stop the loop; report that the agent finished without a footer-bearing review |

The table is read as [`_shared.md`](_shared.md#reading-a-failure-table) says. A run that ended with denials
and no review gets no retry either: the result does not say whether a denial is what stopped it, and where
one did, auto mode refuses the same call again.

**Denials go in the loop's report whenever `denied` is non-empty**, a round whose review ran included: name
the round and the tools. A review that worked around a refused call may have covered less than it says.
