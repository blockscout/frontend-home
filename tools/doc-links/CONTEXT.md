# Doc-link checker — context

`run.sh` resolves the cross-references in the agent instruction surface of the repository it is run in —
markdown links, heading anchors, and the file and directory paths written in backticks. A consumer wires it
to a package script (`pnpm lint:doc-links`) and a CI check.

## Files

| File | Role |
|---|---|
| `surface.ts` | Which files are checked: the walked config roots (symlinks followed), the exclusions, and every markdown file in and below a directory that carries a `CONTEXT.md`, taken from the tracked-file list. Widening the check surface happens here. |
| `config.ts` | Reads the consumer's `devkit.config.json`. |
| `strip.ts` | Blanks the regions of a line that are not references — fenced blocks, and the illustration marks. |
| `resolve.ts` | Turns a written reference into the file it names, and judges when a path that resolves nowhere is a break (shorthand, neighbour, top-level segment) rather than prose that looks like one. |
| `check.ts` | One file in, its findings out. The two reference forms — backtick path, markdown link — are checked here. |
| `report.ts` | Findings to output lines and an exit code. Free of `console` so a spec can assert both. |
| `index.ts` | CLI entry: repo root, tracked files, the loop, the printing. |
| `run.sh`, `tsconfig.json` | Compile-on-run wrapper; the compiled output is git-ignored. |

## What an editor here must keep true

- **`ILLUSTRATION_FORMS` is the only statement of the exemption marks**, and it is printed on failure.
  Teaching the checker a new mark without amending that string leaves authors reading a footer that
  contradicts the tool.
- **The repo root comes from git, asked from the working directory.** Asked from the entry file's own
  location, it answers with the tool's own checkout rather than the repository that runs it.
- **`tsconfig.json` extends nothing.** It is compiled by each consumer's compiler, across TypeScript
  versions, so it cannot lean on a root config that only one of them has.
- **Every path this directory's own docs write is checked by the tool they document.** A rename here that
  misses `CONTEXT.md` fails the run.

## Gotchas (these bit us; don't re-learn them)

- **An `e.g.` is not an exemption.** Prose introducing a real file as an example is the common case, and
  exempting it would leave exactly those references unprotected against a rename. An example naming no real
  file takes a `<placeholder>` segment instead.
- **A false positive is more expensive than a miss.** Noise trains everyone to stop reading the output, so a
  path that names a shape rather than a location (`types/api.ts`, `hooks/`) is deliberately not reported —
  the judgements in `resolve.ts` exist to keep it that way.
- **Home's run needs every child cloned.** Shared skills and rules name a child's file by its path from the
  child's root, so `scripts/doc-links.sh` passes each child as `--child`, and a root-relative path may
  resolve in any of them. CI clones the children before the step. A child missing from the checkout stops
  the run.
- **`.cursor/rules/*.mdc` and `.claude/CLAUDE.md` are symlinks onto files under `.agents`.** Both the
  de-duplication and the realpath-relative resolution depend on that; drop either and every finding in a
  symlinked file is reported twice, or its relative links resolve from the wrong directory.
