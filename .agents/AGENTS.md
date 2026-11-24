# Home repo for the Blockscout frontend repositories

Agent sessions for the Blockscout frontend repositories start here. Home holds the shared skills and rules.
The project repositories, the **children**, are cloned inside it and gitignored. `children.txt` lists them.

## Work in the active child

The **active child** is the child a request is about:

- In a task worktree, it is the only child inside.
- Otherwise, infer it from the request: a path, a pull request, an issue, a repository named. If the request
  does not settle it, ask.

A root-relative path in a skill, a rule or a request names a file in the active child. A skill's glossary
path resolves to `<child>/.agents/GLOSSARY.md`. A path meant for home itself says so. Run `git`, `gh` and
package-manager commands from the active child's directory.

"The branch" in a skill is the active child's branch. A task worktree's home branch only names the worktree
and never identifies a task.

In a task worktree, keep each Bash call plain: one command, no loop, script or heredoc. The harness refuses a
command it cannot verify stays inside the worktree. Write and change files with the Write and Edit tools.

Work on home's own files has no active child. There a rule's paths, such as where a new record or
`CONTEXT.md` is listed, name home's files, and commands run at the home root.

The active child sets the default, not a boundary. When a skill names another child or a folder outside
home, as `resolve-config-request` does with the `frontend-configs` checkout, use it as named.

Before the first change in a child, read a file inside it. That loads the child's own instructions, and its
rules load for the files they match.

A skill that is a symlink in `.agents/skills/` is a child's skill: see
[Child skills](./README.md#child-skills) before editing one.

## Per-directory context

- `tools/doc-links/` — the doc-link checker.
- `tools/code-complexity/` — the Cognitive Complexity and CRAP gate: what a failure means, the consumer's
  config file, and what the engine must not hold.
- `tools/home-bump/` — a consumer's pin of home, and the command that moves it.
- `configs/cspell/` — the cspell base config the children import, and which word list a word goes in.

## Architecture decision records (ADRs)

See `./rules/adr.md` when proposing or adding a new record.

- `adr/0001-home-repo-over-submodule.md` — why the shared agent setup is a home repo and not a submodule in
  each consumer, and the costs accepted for phase 1.
- `adr/0002-one-home-package-for-every-tool.md` — why every command and library export ships in the one
  `frontend-home` package, who supplies a runtime dependency, and the build budget.

## Editing this instruction set

Before changing anything under `.agents/`, read `./README.md`. It owns the provider symlinks and the rules
contract.
