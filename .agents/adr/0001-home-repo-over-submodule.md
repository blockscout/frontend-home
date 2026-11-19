# Home repo instead of a shared submodule

| | |
| --- | --- |
| Status | Accepted |

## Decision

The skills, rules and developer tools shared by the Blockscout frontend repositories live in this
repository, the **home repo** (https://www.aihero.dev/the-home-repo-pattern): agent sessions start here,
and the project repositories, the children, are cloned inside it and gitignored. This replaces the first
design, a read-only git submodule mounted in each consumer, because the submodule charged every consumer
for keeping it in sync and every skill edit for a pointer bump, and the home repo charges neither. The
price is duplication between home and `frontend` for as long as sessions started inside `frontend` must
notice no change, which is phase 1.

## Alternatives

**A read-only git submodule in each consumer.** The prototype (blockscout/frontend#3883, closed unmerged)
mounted the shared repository at `devkit/` in `frontend` and linked individual skills and rules into the
consumer's agent config. Every check in its results table passed. It was dropped for what passing took:

- **Sync hooks on every git operation.** The pointer followed a switch, merge and rebase only through
  three husky hooks and the `prepare` script. A `git reset --hard` across a pointer change still left the
  submodule modified, and a checkout of an older commit left `devkit/` behind untracked.
- **Three agent hooks for worktrees.** A fresh worktree has an empty submodule, so session start, subagent
  start and entering a worktree mid-session each needed a hook to initialise it, and Cursor needed its own.
- **A pointer bump for every skill edit.** A change was a pull request in the shared repository and then a
  second change in each consumer to move the pointer, with a CI check that the pointer sits on the shared
  main branch.
- **Read-only enforcement.** The shared content had to be protected inside a consumer by an agent deny
  rule and a `pre-commit` check.
- **One exclude line per tool** (`tsc`, ESLint, cspell, Vitest) in every consumer.

## Consequences

- **Frozen copies.** Each skill and rule moved to home is still in `frontend`, marked as not to be edited
  there. A home change reaches a session started in `frontend` only when copied over by hand, and until
  then the two disagree.
- **The double rule load.** In a home session a frozen rule in the child loads alongside its home
  original on a matching read.
- **Duplicated settings.** `frontend` keeps its own project settings and hooks, and home has adapted
  copies of the same hooks. A fix in one has to be made in the other.
- **Child skills reach a home session through committed symlinks**, because a gitignored child's skills
  are not discovered. The links are a second list to keep in step with the child, guarded by a check.
- **A task worktree is two branches**, one in home that never gets a pull request and the task branch in
  the child. Claude Code does not retire a hook-created worktree, so home carries its own cleanup hook.

Removing the first three is tracked in blockscout/frontend-home#6.
