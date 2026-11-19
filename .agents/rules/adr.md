---
description: ADR rules
paths:
  - "**/adr/*.md"
globs: "**/adr/*.md"
alwaysApply: false
---
# Architecture decision records

An ADR answers "why is it like this?" without a git archaeology session. It records a decision and the
trade-off behind it, so read the relevant one before changing what it decided.

## Template

```md
# {Short title of the decision}

| | |
| --- | --- |
| Status | Accepted \/ Superseded by <NNNN> |

## Decision

{1-3 sentences: what's the context, what did we decide, and why.}
```

Most records are exactly that: a status and one paragraph. The value is in recording *that* a decision was
made and *why*, not in filling out sections.

The Decision stands alone: a reader who stops after it knows what was decided and why. Its sentences are of
ordinary length. A sentence stretched to carry the evidence is a section that has not been written yet.

## Optional sections

Add a section only when the Decision, kept to its limit, would lose evidence a future reader needs to judge
the decision again. There are two, in this order:

| Section | Holds |
| --- | --- |
| `## Alternatives` | The options turned down, and what each would have cost |
| `## Consequences` | The costs accepted with the decision |

Measurements, tables and reproductions go under the section they support. A section does not restate the
Decision, and a record has no other sections.

## Plans and conditions

A plan for later work goes in a tracking issue, which the record may link. A condition that would end or
reverse the decision ("until X ships") is part of the decision and stays in the Decision.

## Where a record goes

| Scope | Folder | Listed in |
| --- | --- | --- |
| Affects the project as a whole | `.agents/adr/` | a line in `.agents/AGENTS.md` |
| Relevant only to one area or module | `<module-root>/adr/` | that module's `CONTEXT.md` |

Numbering is sequential and **scoped to its folder**; the filename is `<0000>-<slug>.md`.

## When to offer one

All three must be true:

1. Hard to reverse: the cost of changing your mind later is meaningful.
2. Surprising without context: a future reader will look at the code and wonder "why on earth did
   they do it this way?"
3. The result of a real trade-off: there were genuine alternatives and you picked one for specific
   reasons.

If a decision is easy to reverse, skip it: you'll just reverse it. If it's not surprising, nobody will
wonder why. If there was no real alternative, there's nothing to record beyond "we did the obvious thing."

Offer the ADR; do not write one unasked.

## Superseding

Supersede rather than rewrite. Change the old record's `Status` to `superseded by <NNNN>` and leave its
reasoning intact.
