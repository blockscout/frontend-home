# frontend-home

The home repo for the Blockscout frontend repositories: shared agent skills, rules and developer tools.
Agent sessions start here. The project repositories, the **children**, are cloned inside it and
gitignored.

**Status: phase 1.** See [blockscout/frontend#3882](https://github.com/blockscout/frontend/issues/3882).
`frontend` is the only child, and the layout may still change.

| Path | What it is |
|---|---|
| `.agents/` | Agent instructions, skills and rules, reached by Claude Code and Cursor through symlinks ([`.agents/README.md`](.agents/README.md)) |
| `.claude/settings.json`, `.claude/hooks/` | Claude Code project settings and the hooks behind [task worktrees](#task-worktrees) |
| `children.txt` | The children, by name and repository URL |
| `scripts/` | Cloning the children, the check that the ignore files list them, and the links to their skills |
| `tools/` | Developer tools run in a child |

## Children

`scripts/bootstrap.sh` clones every child in `children.txt` that is missing, beside this README. A child
already present is left as it is.

Each child is listed in two ignore files: `.gitignore` keeps it out of home's history, and `.ignore` lets a
search from the home root reach it. `pnpm lint:children` fails when either file disagrees with
`children.txt`.

A child's skills reach a home session through committed symlinks in `.agents/skills/`.
`scripts/skill-links.sh` writes them and `pnpm lint:skill-links` checks them
([`.agents/README.md`](.agents/README.md#child-skills)).

## Task worktrees

A **task worktree** is a home worktree with a child worktree inside it, at `.claude/worktrees/<name>`. It
mirrors the home layout, so every relative path, skill and rule works in it unchanged. The name decides
what is inside:

```bash
claude --worktree frontend-issue-1234   # `frontend` only, on branch `issue-1234`
claude --worktree scratch               # every child present, each on a branch `scratch` cut from its HEAD
```

With a `<child>-` prefix the branch is the child's own when it has one, the remote's when only the remote
has it, and otherwise a new one cut from the child's remote main branch. The same name reopens the
worktree. A worktree entered mid-session and a worktree-isolated subagent go through the same hook; a
subagent's generated name has no child prefix, so it gets the children of its parent session.

- **A task worktree is two branches**: the task branch in the child and a branch named as the worktree in
  home. The home branch only holds the worktree and never gets a pull request.
- **A session in a task worktree runs that worktree's copy of the settings and hooks**, as of the home
  commit it was cut from. A hook fix reaches an existing worktree only by merging it into the worktree's
  home branch.
- **The hooks find home from their own location**, never from `CLAUDE_PROJECT_DIR` or the working
  directory, and clear inherited git variables before calling git in another repository.
  `pnpm test:hooks` runs the creation hook against scratch repositories.
- Dependencies are not installed at creation. The first command that needs them installs them, in the
  home worktree and in each child inside it.

## Writing a shared file

A shared skill or rule is read while working in a child, the active child that `.agents/AGENTS.md` defines:

- Refer to another shared file by relative path (`./adr.md`).
- Refer to a file the child owns by its path from the child's root (`.agents/GLOSSARY.md`). It resolves in
  the active child, and `pnpm lint:doc-links` looks for it in every child.
- Name a file in home itself as home's (home's `children.txt`).
