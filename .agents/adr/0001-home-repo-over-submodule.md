# Home repo instead of a shared submodule

| | |
| --- | --- |
| Status | Accepted |

## Decision

The skills, rules and developer tools shared by the Blockscout frontend repositories live in this
repository, the **home repo** (https://www.aihero.dev/the-home-repo-pattern): agent sessions start here,
and the project repositories, the children, are cloned inside it and gitignored. This replaces the first
design, a read-only git submodule mounted in each consumer (prototype blockscout/frontend#3883, closed
unmerged), which passed every check but only with sync hooks on every git operation, agent hooks to
initialise it in each fresh worktree, a pointer bump in every consumer for every skill edit, read-only
enforcement and an exclude line per tool, where in home a skill edit is an ordinary commit and a child
has no trace of the shared content. The costs accepted, so that sessions started inside `frontend` notice
no change in phase 1, are frozen copies of the moved skills and rules in `frontend` (loaded a second time
in a home session), settings and hooks duplicated between the two, committed symlinks for the child's
skills, and task worktrees of two branches with home's own creation and cleanup hooks.
