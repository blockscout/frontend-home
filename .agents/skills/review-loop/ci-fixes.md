# CI fixes

The brief for the agent that fixes a red Checks run inside a `review-loop` round: the round's resolver,
resumed, or a fresh subagent after `cleared`. It is given the child with its absolute path, the run url and
the PR url. Everything below happens in that child: the commands run in its directory, the commit is made
there, and a path written from the root is from the child's root. Its job is to make that run's failures
pass on the next push without changing what the PR builds, and to hand back anything it cannot settle that
way as `needs-human`. What makes this different from fixing CI by hand is that nobody is watching: the rules
below are the judgement a developer would apply at the keyboard.

## 1. Read the run

Read the failed jobs and their logs; the failing job's name says which gate it is, and the gate's own doc
(`.agents/rules/*.md`, `tools/*/CONTEXT.md`) says how to read its output and what the valid fixes are.
Read it before touching code. Reproduce each failure locally with the command that doc gives before
fixing it: a fix for a failure you cannot reproduce is a guess.

A job that failed on infrastructure (a runner lost, an install timeout, a download that never arrived) is
**not a finding**: rerun it with `gh run rerun <run id> --failed` and report that instead of a commit.

**Done when**: every failing job is listed with its gate, the failure reproduced, and a proposed fix — or
a `needs-human` reason.

## 2. The escape

A CI fix stays inside the finding. Two kinds of fix are **`needs-human`**, whatever the gate:

- a fix that **changes behaviour** — the component renders something else, a branch is removed, a value
  changes — rather than a test, an assertion, a suppression with its reason, or a decomposition that keeps
  the same output;
- a fix that **restructures beyond the finding** — moving a hook, splitting a component, reshaping a
  signature, touching a file the failure does not name.

The gates' own docs name the same line for their domain: the mutation-testing doc's "a survivor is not a
reason to restructure working code", the complexity doc's "raising the cap is not the fix". When the only
fix you can see crosses it, the question goes to the developer.

## 3. The child's own gates

A gate only one child has gets its procedure from that child: its
`.agents/skills/review-loop/ci-fixes-local.md`, the local part of this file. Look for it once, before fixing. When a failing job is of a gate it names, follow its
procedure for that job. The escape above binds it. A child with no such file adds nothing, and every
failure is a plain fix under the escape.

## 4. Commit

One commit for the CI fix, **separate from the review fixes**, so the history shows which change came from
which source. A plain descriptive subject naming the gate (`Kill surviving mutants in useFoo`, `Flatten
classify() under the COG cap`), the repo's `Co-Authored-By` trailer, no `#issue` reference. Run the gate's
local command once more on the fixed files before committing. **No push**: the loop pushes once per round.

**Done when**: the CI fix is committed, the tree is clean, and the gate's local command passes on the
touched files.

## Returning

Two shapes, and the loop reads both:

- **Fixed.** The commit sha, and per failing job: the gate, the failure in one line, what changed. A rerun
  of an infrastructure failure is reported as such, with no commit.
- **`needs-human`.** Return it **before any edit**, as `resolve-review` does
  ([`../resolve-review/SKILL.md`](../resolve-review/SKILL.md) → "Returning on `needs-human`"): one table
  with every failing job — gate, failure, verdict (`fix` or `needs-human`), proposed action — and one
  question per `needs-human` row stating what the code and the spec could not settle. Then stop. The loop
  presents the block, collects the answers and resumes this same run; on resumption, re-adjudicate each
  `needs-human` row against its answer, add the ones ruled `fix` to the fix set, and continue at step 4.
  A row the developer answers "leave it" stays red: say so in the return, so the loop's report names it.
