# Code complexity — context

A code-quality gate that flags code which is either hard to read *or* both complex and
under-tested. Two independent gates run:

- **Cognitive Complexity (CC)** — the readability gate. "Should a human decompose this?" Capped per
  function class.
- **Change Risk Anti-Patterns (CRAP)** — the under-testedness gate. "Complex and untested?" functions, fed by
  *cyclomatic* complexity joined with coverage.

A consumer installs home as a pinned git dependency and gets the engine two ways: the `code-complexity`
command, wired to a package script (`pnpm test:code-complexity`), and the `frontend-home/code-complexity`
library entry for its own tools. The scope and the caps are the consumer's, in `code-complexity.config.json`
at its root.

## Where to look

| Question | Answer lives in |
| --- | --- |
| The gate failed. What do I change? | the next section |
| Why is this function's score *that* number? | `./docs/MODEL.md` |
| Which files and functions get gated at all? | `./docs/MODEL.md` |
| How do I run it? What feeds the coverage half? | `pnpm test:code-complexity --help`, then `./docs/RUNNING.md` |
| What goes in the config file? | `./docs/RUNNING.md` |
| Can I move a cap? How do I set them for a new consumer? | short answer to the first: no. `./docs/CALIBRATION.md` |
| Why is the counting model like this? | `./adr/` |
| Why one home package for every tool? | `.agents/adr/0002-one-home-package-for-every-tool.md` |
| Which file implements what? | the file map at the bottom |

## The gate failed — what now

Reproduce it on just your file:

```bash
pnpm test:code-complexity path/to/your/file.ts
```

The `BROKE` column names which cap you crossed. In CI you also get an inline annotation on the diff:

```
classify: cognitive 21 > 20 [top: if +10 (L11), switch +5 (L6), if +2 (L4);
                             deepest nesting 3 at L11, flattening saves ~5]
```

**`COG` — decompose it.** The annotation is built to be actionable: it names the increment sites that
cost the most, the deepest nesting pocket, and what flattening that pocket by one level would save.
Above, a single `if` at depth 3 accounts for 10 of the 21 — extract it, invert it into an early
return, or lift the `switch` out from around it. Nesting is charged quadratically, so the deepest
level is where the points are and pulling it out is almost always the cheapest win.

**`CRAP` — add a test.** CRAP joins cyclomatic complexity with coverage, and coverage is the only
lever. Simplifying the function lowers its *cognitive* score, not its CRAP. A `behavior` function
that no spec executes reads 0%. When a missing report entry reads `—` instead, and where the score
of a function in a spec-less JSX file depends on the selection: `./docs/RUNNING.md`.

**Raising the cap is not the fix.** The caps are coupled to each other and to the counting model, so a
consumer moves one only by recalibrating all of them.

## What an editor here must keep true

- **Nothing calibrated on one consumer sits in the engine.** The roots and the caps have no default. A
  default added for them would gate a second consumer on the first one's numbers.
- **`typescript` is a peer dependency, and the only package the engine needs at run time.** The parser is
  the consumer's, so it reads the syntax the consumer writes. A second runtime package has to be decided as
  this one was: `.agents/adr/0002-one-home-package-for-every-tool.md`.
- **The coverage run is the consumer's vitest.** The engine starts `node_modules/.bin/vitest` in the working
  directory, with the config the consumer names in `coverage.vitestConfig`. Home ships no vitest config.
- **`./lib.ts` is a contract with the consumers' own tools.** Their gates select files through it, so a
  changed signature there breaks a consumer at its next pin bump. What it exports and why is in its header.
- **The scope rule is built from the config, in the command and in the library alike.** A constant rule
  beside it would give two tools of one consumer two scopes.
- **`../cli/flags.ts` is a copy of the flag parser `frontend` keeps for its other tools.** One source for
  both is tracked in blockscout/frontend-home#27.
- **Every consumer install runs the build**, the Docker image's too. A measurable addition to `prepare`
  is checked against the budget in `.agents/adr/0002-one-home-package-for-every-tool.md`.

## File map

Four directories, one per pipeline stage, and files at the root that tie them together. Specs
sit next to what they test.

Measuring and judging are separate jobs. `select/`, `measure/` and `coverage/` compute the numbers
and never see a cap; the caps enter once, at `./analyze.ts`, which stamps a verdict onto each row.
The table, the exit code and the GitHub annotations all read that verdict rather than re-deriving
it.

**Root** — the entries, the config, and the join.

- `./index.ts` — the `bin` entry of the command
- `./cli.ts` — parse the flags over the config, pick the selection, orchestrate, set the exit code
  (`./docs/RUNNING.md`)
- `./lib.ts` — the library entry
- `./config.ts` — reads and validates the consumer's config file; the defaults
- `./analyze.ts` — complexity × coverage → one row per function, each stamped with its verdict
- `./tsconfig.json` — the build into `dist`, which is git-ignored

**`select/`** — which files, and which lines inside them.

- `./select/scope.ts` — the in-scope rule, built from the config (`./docs/MODEL.md`)
- `./select/eligibility.ts` — whether a file has a co-located vitest spec
- `./select/diff.ts` — git plumbing: changed files, changed line ranges, merge-base
  (`./docs/RUNNING.md`)

**`measure/`** — one AST walk, no caps in sight.

- `./measure/complexity.ts` — cognitive, cyclomatic, the function class and the contributions
  (`./docs/MODEL.md`)
- `./measure/jsx.ts` — file-level JSX detection, which decides who needs coverage generated
  (`./docs/RUNNING.md`)
- `./measure/crap.ts` — the CRAP formula (`./docs/MODEL.md`)

**`coverage/`** — the CRAP half's input.

- `./coverage/generate.ts` — run vitest scoped to the selection, into a throwaway dir
  (`./docs/RUNNING.md`)
- `./coverage/read.ts` — parse `coverage-final.json`, derive per-function line coverage
  (`./docs/MODEL.md`)

**`render/`** — rows out.

- `./render/report.ts` — the score table, the sort order, the offender test (`./docs/RUNNING.md`)
- `./render/github.ts` — `::error` annotations and the step summary (`./docs/RUNNING.md`)
