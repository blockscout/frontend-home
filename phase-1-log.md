# Phase 1 usage log

Every miss in daily use of home, for the two weeks that gate phase 2
([blockscout/frontend#3882](https://github.com/blockscout/frontend/issues/3882)). One line per miss, added
when it happens.

| Date | Kind | What happened | Fixed by |
|---|---|---|---|
| 2026-11-19 | Check | In a task worktree the child's spell check checked 0 files and passed, in `pnpm lint:cspell` and in the pre-commit hook. cspell's `useGitignore` applied home's `.gitignore`, which ignores `/.claude/worktrees/`. The main clone's child was not affected (3625 files), nor was CI. `--no-must-find-files` hid the empty run. An audit of the child's other checks in a task worktree (eslint, tsc, vitest, playwright, doc-links, react-doctor, ripgrep) found the same files as in the main clone. | Fixed by [blockscout/frontend#3913](https://github.com/blockscout/frontend/pull/3913): `gitignoreRoot` in the child's `cspell.jsonc`, and `lint:cspell` without `--no-must-find-files`. A second child that uses cspell needs the same setting. |
| 2026-11-19 | Tooling | In a task worktree the harness refused 11 compound commands that contained `git` (loops, `set -e` scripts, heredocs), across 6 sessions of one task. The refusal comes from Claude Code's guard for worktree sessions, which cannot verify that such a command stays inside the worktree. Likely not specific to home: not verified in a worktree session of a standalone clone. | Fixed by [#12](https://github.com/blockscout/frontend-home/pull/12): a line in `AGENTS.md` under "Work in the active child". |
| 2026-11-19 | Skill | `implement-ticket` step 1 resolves the task folder from the branch `issue-<number>`. The home worktree's branch was `frontend-address-portfolio`; `issue-3855` was the child's branch. Cost: three calls to find the task. Five more child documents resolve a task from the branch the same way. | Fixed by [#12](https://github.com/blockscout/frontend-home/pull/12): a line in `AGENTS.md` under "Work in the active child", so the child's skills stay unchanged. |
