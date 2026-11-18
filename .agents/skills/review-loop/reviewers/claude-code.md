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

- `--child` and `--round` are filled in as [`_shared.md`](_shared.md#background-run-and-polling) says.
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

## Failure signals

The terms [`_shared.md`](_shared.md#deciding-the-run) decides the run by. Read them from the exit code and
the result:

```bash
jq '{is_error, denied: [.permission_denials[]?.tool_name]}' <scratchpad>/review-<round>.json
```

- **Transport failure**: exit non-zero other than `124`, empty stdout, or `is_error: true`.
- **Provider stop**: `denied` non-empty. Report `no review; denials present:` and the denied tools. The
  result does not say whether a denial is what stopped the run, and where one did, auto mode refuses the
  same call again.

**Denials go in the loop's report whenever `denied` is non-empty**, a round whose review ran included: name
the round and the tools. A review that worked around a refused call may have covered less than it says.
