# frontend-home

The home repo for the Blockscout frontend repositories: shared agent skills, rules and developer tools.
Agent sessions start here. The project repositories, the **children**, are cloned inside it and
gitignored.

**Status: phase 1.** See [blockscout/frontend#3882](https://github.com/blockscout/frontend/issues/3882).
`frontend` is the only child, and the layout may still change.

| Path | What it is |
|---|---|
| `.agents/` | Agent instructions, skills and rules, reached by Claude Code and Cursor through symlinks ([`.agents/README.md`](.agents/README.md)) |
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

## Writing a shared file

A shared skill or rule is read while working in a child, the active child that `.agents/AGENTS.md` defines:

- Refer to another shared file by relative path (`./adr.md`).
- Refer to a file the child owns by its path from the child's root (`.agents/GLOSSARY.md`). It resolves in
  the active child, and `pnpm lint:doc-links` looks for it in every child.
- Name a file in home itself as home's (home's `children.txt`).
