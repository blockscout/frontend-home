# The review axes

One brief per axis, dispatched by [`SKILL.md`](SKILL.md) step 2. You are one axis: read **your** section
and ignore the others. The orchestrator has already given you the child, the scope, the base ref, the
touched files (untracked included), the child's local files and documents, and the check results — those
are established fact, so do not re-run them. The change is in the child: run `git` in its directory and
read every root-relative path below from its root. Any other child present in home is another repository:
leave its files out of the review, and do not cite them as precedent.

A **local file** is what the child adds to one file of this skill: `<file>-local.md` in the child's
`.agents/skills/review-changes/`. Whenever you read a file of this skill, read its local file too when
the orchestrator's list has it. With none listed, the child adds nothing.

## What every axis returns

Findings in this shape, and nothing else. No preamble, no summary.

```
severity: blocker | major | nit
needs-human: yes | no
location: <path>:<line>
claim: <what is wrong — quote the code>
fix: <one or two lines>
```

Report every in-bounds finding you have, ranked most severe first; the count is uncapped. Each finding is
capped at **120 words** of prose — quoted code does not count. Severity here is your own read; the
orchestrator recalibrates across axes.

## Spec axis

Read the spec (path given) and the diff. Its **Functional Requirements** are the contract: take each one in
turn and report whether the diff actually satisfies it, quoting the requirement behind each finding. Then
report what the requirements don't cover: behaviour in the diff the spec never asked for, and requirements
that look implemented but are implemented wrongly. Anything the spec's **Out of scope** section names is
not a finding.

## Standards axis

Read the rules matching the touched file types, the child's `.agents/rules/*.md` and home's in
[`../../rules/`](../../rules/), every `CONTEXT.md` for directories the diff touches, the child's documents
the orchestrator gave you, and **one** smell baseline with its local file, picked by what the diff touches:

| The diff touches | Baseline |
| --- | --- |
| code | [`smells.md`](smells.md) |
| the instruction surface — `.agents/**`, `AGENTS.md`, any `CONTEXT.md`, `.cursor/**`, `.github/*instructions*` | [`prose-smells.md`](prose-smells.md) |
| both | both, each applied only to the files it governs |

Task specs under `.agents/tasks/**` are not the instruction surface — the Spec axis reads those as the
source of truth rather than reviewing them as instructions.

Report: places the diff breaks a documented rule — **cite the rule file and the rule** — and smells from the
baseline, each named and quoted. A documented rule can be a hard breach; a smell is always a judgement call.
Skip anything the checks already cover.

## Correctness axis

Read the touched files **in full**, plus the files the change depends on — a hunk-only read produces exactly
the shallow findings that make developers stop trusting review. Report: 
- logic errors; 
- mishandled loading / empty / error / pagination paths; 
- places where the types claim something the runtime does not; 
- tests that assert the framework or the mock rather than real behaviour (per the "What a good test is"
section of home's [`../../rules/tests-unit.md`](../../rules/tests-unit.md)).

## Out of bounds

The **Out of bounds** list in [`SKILL.md`](SKILL.md) binds every axis, and so does `## Not a finding` in
the child's `SKILL-local.md` when the orchestrator's list has that file. Read the list before you report,
and that section when the file is listed: a finding either names is dropped whichever axis raised it. With
no `SKILL-local.md` listed there is nothing more to read, and the child adds no entry.
