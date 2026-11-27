# frontend-home

The home repo for the Blockscout frontend repositories: shared agent skills, rules and developer tools.
Agent sessions start here. The project repositories, the **children**, are cloned inside it and
gitignored.

**Status: phase 1.** See [blockscout/frontend#3882](https://github.com/blockscout/frontend/issues/3882).
The children are `frontend`, `app-sdk` and `frontend-configs`, and the layout may still change.

| Path | What it is |
|---|---|
| `.agents/` | Agent instructions, skills and rules, reached by Claude Code and Cursor through symlinks ([`.agents/README.md`](.agents/README.md)) |
| `.claude/settings.json`, `.claude/hooks/` | Claude Code project settings and the hooks behind [task worktrees](#task-worktrees) |
| `.claude/agents/` | Claude Code subagent definitions, which only Claude Code reads |
| `children.txt` | The children, by name and repository URL |
| `scripts/` | Cloning the children, the check that the ignore files list them, and the links to their skills |
| `tools/` | Developer tools a child installs from home as a pinned git dependency ([`tools/doc-links/CONTEXT.md`](tools/doc-links/CONTEXT.md), [`tools/code-complexity/CONTEXT.md`](tools/code-complexity/CONTEXT.md)), and the command that moves the pin ([`tools/home-bump/CONTEXT.md`](tools/home-bump/CONTEXT.md)) |
| `configs/` | Configs a child imports from the same dependency ([`configs/cspell/CONTEXT.md`](configs/cspell/CONTEXT.md)) |

## Setup

For a machine with nothing. Needed first: `git` with SSH access to GitHub, Node as in `.nvmrc`, pnpm
(`corepack enable` takes the version from `package.json`), `jq`, an authenticated `gh`, and Claude Code.
The hooks call `jq`, and cleanup asks `gh` whether a branch has landed.

```bash
git clone git@github.com:blockscout/frontend-home.git
cd frontend-home
./scripts/bootstrap.sh         # clones every child in children.txt, beside this README
pnpm install                   # home's own tools
pnpm -C frontend install       # the main clone's child; a task worktree installs its own
pnpm lint:children && pnpm lint:skill-links   # the layout is whole
claude                         # sessions start here, at the home root
```

- **Use a fresh directory**, with a fresh clone of each child inside it. A child clone that already exists
  elsewhere, with its own worktrees, stays where it is and is not moved in.
- **A child's local files** (`frontend/.env.local` and whatever else its `.worktreeinclude` lists) are
  created once in the main clone's child. Every task worktree gets a copy from there.
- **The first session asks to approve the `playwright` MCP server** from `.mcp.json`.
- **The children's skills are already there**: the links in `.agents/skills/` are committed and resolve
  once the child is cloned ([Children](#children)). A child's own instructions and rules load when a file
  inside it is read.

The hooks in `.claude/settings.json` then do the rest:

| When | What happens |
|---|---|
| Session start | Every child is fetched; proven task worktrees idle for three days are removed and the others reported ([Cleanup](#cleanup)) |
| A worktree is asked for (`--worktree`, mid-session, an isolated subagent) | A [task worktree](#task-worktrees) is made or reopened |
| First command in a task worktree that needs dependencies | They are installed in the home worktree and in each child inside it |
| A worktree-isolated subagent starts | It is told to read the child's always-loaded instructions |
| A worktree is removed at exit or left mid-session | The whole task worktree is retired, when proven |

Phase 1 runs with a log of every miss: a missing skill, a command run in the wrong directory, a stale
worktree. It is kept in [`phase-1-log.md`](phase-1-log.md).

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
  `pnpm test:hooks` runs the creation and cleanup hooks against scratch repositories.
- Dependencies are not installed at creation. The first command that needs them installs them, in the
  home worktree and in each child inside it.

### Cleanup

A task worktree is retired as a whole: the child worktrees, their branches, the home worktree and its
branch. `.claude/hooks/worktree-cleanup.sh` does it, and only for a worktree that is **proven**: nothing
uncommitted in home or in a child, the home worktree's commit on another home branch or the head of a
merged home pull request, and every child branch landed. The script's header has the proofs. Anything unproven is left whole.

- **At session start** every proven worktree that has been idle for three days is removed, and the rest
  are listed with the reason each one stays. This runs in sessions started in the main home clone, not in
  a task worktree. `.claude/hooks/worktree-cleanup.sh prune --report < /dev/null` lists without removing.
- **At an interactive exit**, or when Claude leaves a worktree mid-session, the same proof decides with no
  idle window. Claude Code only looks for changes in the home worktree and can remove without asking, so
  the hook is the last check. An unproven worktree stays even when removal was chosen at the prompt.
- **A subagent's worktree** is never removed by Claude Code. The session-start pass is what retires it.
- To discard an unproven worktree, remove it by hand: `git worktree remove --force` in the child and then
  in home, and `git branch -D` for both branches.

## Writing a shared file

A shared skill or rule is read while working in a child, the active child that `.agents/AGENTS.md` defines:

- Refer to another shared file by relative path (`./adr.md`).
- Refer to a file the child owns by its path from the child's root (`.agents/GLOSSARY.md`). It resolves in
  the active child, and `pnpm lint:doc-links` looks for it in every child.
- Name a file in home itself as home's (home's `children.txt`).
