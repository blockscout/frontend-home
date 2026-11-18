# Reviewer: `cursor`

The Cursor CLI (`agent`) running home's `review-changes` skill headlessly against the loop's child. Tag:
`cursor`, passed as `--as cursor` on every run.

## Invocation

```bash
agent -p --trust --approve-mcps --output-format json [--model <id>] \
  "/review-changes pr --as cursor --child <child> [--round follow-up]"
```

- `--child` and `--round` are filled in as [`_shared.md`](_shared.md#background-run-and-polling) says.
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

## Failure signals

The terms [`_shared.md`](_shared.md#deciding-the-run) decides the run by. Read them from the exit code and
stdout:

- **Transport failure**: exit non-zero other than `124`, or empty stdout.
- **Provider stop**: none.
