# Code complexity — running it

`pnpm test:code-complexity --help` is the flag reference. This document is what the flag list does not
tell you: what the consumer's config file holds, how a selection turns into a vitest run, and how to read
what comes back.

## The config file

`code-complexity.config.json` sits at the consumer's package root, the directory the command runs in. The
command stops when the file is missing, has a key it does not know, or lacks `roots` or a cap.

```json
{
  "roots": [ "src/" ],
  "maxCognitiveJsx": 25,
  "maxCognitiveBehavior": 20,
  "maxCrap": 80,
  "coverage": { "vitestConfig": "vitest.coverage.config.ts" }
}
```

| Key | Holds | Default |
| --- | --- | --- |
| `roots`, `extensions`, `specPatterns`, `generatedPatterns` | the scope: `./MODEL.md` | none for `roots`; `../config.ts` for the rest |
| `maxCognitiveJsx`, `maxCognitiveBehavior` | the cognitive cap of each function class | none |
| `maxCrap` | the CRAP cap | none; may be left out with `"coverage": false` |
| `baseRef` | the ref `--changed` diffs against | `origin/main` |
| `coverage` | `false`, or an object | an object: vitest runs with its own config |
| `coverage.vitestConfig` | the vitest config of the coverage run, a path from the package root | vitest's own lookup |

- **`"coverage": false` is for a consumer without vitest.** The cognitive gate alone becomes the default
  run, as if every run had `--no-coverage`. `--coverage-file` still feeds the CRAP half, and then needs a
  cap from `maxCrap` or `--max-crap`.
- **The numbers are the consumer's calibration.** The example above is a shape, not a recommendation.
- **A pattern is a regular expression in a JSON string**, so each backslash is written twice: `"\\.spec\\."`.

## Two independent axes

The interface mirrors vitest — **selection** (which functions) and **coverage source** (how the CRAP
half is fed). Any selection combines with any source.

| Selection | Scores |
| --- | --- |
| *(no arguments)* | every in-scope function, repo-wide |
| `<path...>` | every function in the given files, ignoring the diff |
| `--changed[=<ref>]` | only functions a changed line falls within |

Everything is relative to the working directory: the config file, the scope roots, the paths on the
command line, the diff `--changed` scores and the `node_modules` vitest is started from. Run the command
from the package root, which a package script does.

| Coverage source | How the CRAP half is fed |
| --- | --- |
| *(default)* | the tool runs the consumer's vitest itself, scoped to the selection, into a throwaway temp dir |
| `--coverage-file <path>` | consume a prebuilt report and skip vitest |
| `--no-coverage`, or `"coverage": false` in the config | cognitive gate only, which is always enforced either way |

`--verbose` streams vitest's output live and adds the cyclomatic (`CX`) column; otherwise vitest is
silent so the score table is what you see.

## Which files trigger a vitest run (generation scope)

Separately from per-function scoring, a *file* needs vitest coverage generated for it when it is a
**JSX-less logic file** *or* a **JSX file with a co-located vitest spec** (`Component.spec.tsx` or `Component.isolated.spec.tsx` next
to `Component.tsx`; a browser test such as `Component.pw.tsx` does not count). This only decides whether
`vitest related`/`--changed` pulls the file in. A `behavior` function in a JSX file outside that set
triggers no run, and scores from whatever the report holds: 0% when the file is absent from it.

Five consequences:

- **Vitest is skipped when nothing in the selection needs coverage.** Only files in the generation
  scope cause a run, so a focused run on a spec-less JSX component returns instantly and scores its
  `behavior` functions 0%. Skipping the run is not `--no-coverage`: generation scope never decides
  which functions are scored. A diff with nothing in scope prints "No functions to check." and runs
  nothing.
- **The skip is an approximation, and the score of a `behavior` function in a spec-less JSX file
  depends on its selection.** A spec that is not co-located may still execute the file. Its hits
  count whenever a report holds them: when another file of the selection triggers the run, in a
  full run, and with `--coverage-file`. Alone in its selection the same function scores 0%. Tracked
  in blockscout/frontend-home#29.
- **All three generated scopes select through the module graph** (`vitest related <paths>`,
  `vitest run --changed <merge-base>`, or the whole suite), so the coverage of a file in the
  generation scope is the same however it was reached. A selection with no matching specs passes; a
  failing suite warns and still reports whatever coverage landed.
- **A spec that costs much and covers little is excluded in the consumer's coverage vitest config**, the
  one `coverage.vitestConfig` names. A module-graph selection otherwise pulls it in for almost any file.
- **A function absent from the coverage report usually scores 0%, not `—`.** The one exception is a
  user-supplied `--coverage-file` in focused mode.

## The report

The default table shows `KIND`, `COG`, `COV`, `CRAP` and `BROKE`, sorted by CRAP descending; 
`jsx` and no-coverage rows sort to the bottom, tie-broken by `COG`. The two gates are independent: 
the cognitive cap trips on any in-scope function over its class's cap, the CRAP cap only on `behavior` 
functions with coverage data.

Under `$GITHUB_ACTIONS` the tool also emits `::error file=,line=::` annotations for offenders and
writes the table to `$GITHUB_STEP_SUMMARY`.
