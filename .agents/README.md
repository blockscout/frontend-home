# Agent configuration

Every agent document in home has one source here. Claude Code and Cursor reach it through symlinks.

| Path | What it is | Reached by |
|---|---|---|
| `AGENTS.md` | Always-loaded instructions | `.claude/CLAUDE.md`; Cursor loads it only from the root, so a root `AGENTS.md` link too |
| `rules/*.md` | Rules, scoped to file patterns | `.claude/rules/`, and one `.cursor/rules/<name>.mdc` per rule |
| `skills/*/SKILL.md` | Workflows loaded on invocation | `.claude/skills/` |
| `skills/<name>` symlinks | The children's skills, one link per skill | `.claude/skills/`, as home's own |

## The rules contract

Claude Code and Cursor discover rules differently, so a rule file carries frontmatter for both. Each tool
ignores the keys it does not recognise.

```yaml
---
description: what this rule covers
paths:                        # Claude Code — YAML list of globs
  - "**/*.{ts,tsx}"
globs: "**/*.ts,**/*.tsx"     # Cursor — the same patterns, comma-separated in one string
alwaysApply: false
---
```

Keep `paths` and `globs` in step by hand. Nothing warns when they drift.

- **A new rule needs a new Cursor symlink.** Cursor reads only `.cursor/rules/*.mdc`. Claude Code needs no
  per-file step, because `.claude/rules` links the whole directory.

  ```bash
  ln -s "../../.agents/rules/<name>.md" ".cursor/rules/<name>.mdc"
  ```

- **A rule with no `paths` loads at launch, in every session.** A document meant to be read on demand sits
  outside `rules/`, with a pointer to it from `AGENTS.md` or a skill.

## Frozen rules in a child

A **frozen rule** is a rule that moved to home and is still in the child, for sessions started inside the
child. In a home session the frozen rule and its home original match the same files, so both would load.
Home's `.claude/settings.json` skips each frozen rule with one `claudeMdExcludes` entry:

```json
"claudeMdExcludes": [ "**/<child>/.agents/rules/<name>.md" ]
```

The `**/` prefix covers the main clone and every task worktree. A session started inside the child reads
the child's settings only, so it still loads the frozen rule.

- **Keep the entries in step with the children by hand.** Nothing checks them. When a child freezes a
  rule, add its entry. When a frozen rule is removed or becomes the child's own again, delete its entry.
- **A stale entry hides a rule.** A child rule under an excluded name never loads in a home session.
- **Cursor ignores the setting**, so a frozen rule loads twice there.

## Local rules in a child

A **local rule** holds what one child adds to a home rule or does differently: its commands, its file
names, its exceptions. For home rule `<name>` it is the child's `.agents/rules/<name>-local.md`, with the
same `paths` and `globs`. Both load on a matching read, in a home session and in a session started inside
the child.

- **The home rule names the local rule in its opening lines**, and says the child's rule wins where the two
  disagree. A home rule names no other file of a child.
- **A local rule is the child's own.** Edit it in the child. It is never frozen and gets no
  `claudeMdExcludes` entry.
- **A frozen rule cannot carry local content.** The exclusion hides the whole file from a home session, so
  what is local sits in the local rule, never in the frozen copy.

## Child skills

A session started in home has a child's skills only through the committed symlinks in `skills/`. Each is named
as the skill and points into the child: `skills/<name>` -> `../../<child>/.agents/skills/<name>`. In a task
worktree a link resolves to that worktree's child, so the skill is the branch's.

- **A symlinked skill belongs to the child it points into.** Edit it in the child and commit it there. Home
  commits only the link.
- **A skill home has as a real directory gets no link.** Home's copy is the one that loads, whatever the child
  has under that name.
- **`scripts/skill-links.sh` writes the links** from `children.txt` and each child's skills. Run it and commit
  the result when a child adds, renames or removes a skill, or when a skill moves to home.
  `pnpm lint:skill-links` fails when the links and the children's skills disagree. It compares against the
  child branch that is checked out, so it is run by hand and in CI, never from a session hook.
