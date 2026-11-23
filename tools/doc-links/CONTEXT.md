# Doc-link checker — context

`doc-links` resolves the cross-references in the agent instruction surface of the repository it is run in —
markdown links, heading anchors, and the file and directory paths written in backticks. A consumer installs
home as a pnpm git dependency pinned by commit, and wires the command to a package script
(`pnpm lint:doc-links`) and a CI check.

## Files

| File | Role |
|---|---|
| `surface.ts` | Which files are checked: the walked config roots (symlinks followed), the exclusions, and every markdown file in and below a directory that carries a `CONTEXT.md`, taken from the tracked-file list. Widening the check surface happens here. |
| `config.ts` | Reads the consumer's optional `doc-links.config.json`, at its repository root. |
| `strip.ts` | Blanks the regions of a line that are not references — fenced blocks, and the illustration marks. |
| `resolve.ts` | Turns a written reference into the file it names, and judges when a path that resolves nowhere is a break (shorthand, neighbour, top-level segment) rather than prose that looks like one. |
| `check.ts` | One file in, its findings out. The two reference forms — backtick path, markdown link — are checked here. |
| `report.ts` | Findings to output lines and an exit code. Free of `console` so a spec can assert both. |
| `index.ts` | CLI entry: repo root, tracked files, the loop, the printing. |
| `tsconfig.json` | The build into `dist`, which is git-ignored. |

## What an editor here must keep true

- **`ILLUSTRATION_FORMS` is the only statement of the exemption marks**, and it is printed on failure.
  Teaching the checker a new mark without amending that string leaves authors reading a footer that
  contradicts the tool.
- **The repo root comes from git, asked from the working directory.** The entry file's own location is
  inside the consumer's `node_modules`, where git answers with nothing useful.
- **No runtime dependencies.** A consumer gets the built files and nothing else. This is a phase-1
  limit: delivering a tool that needs a package at run time is tracked in blockscout/frontend-home#6.
- **`files` in home's `package.json` is what ships `dist`.** Without it the pack step follows `.gitignore`
  and the consumer gets a command with no file behind it.
- **Home keeps `pnpm-lock.yaml` and no other lockfile.** pnpm builds a git dependency with the package
  manager its lockfile names, so a `package-lock.json` here makes the consumer's install run npm.
- **A consumer allows the build by exact commit**, so its pin is written twice: `tools/home-bump/CONTEXT.md`.
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
  child's root, so a child missing from the checkout stops the run.
- **`.cursor/rules/*.mdc` and `.claude/CLAUDE.md` are symlinks onto files under `.agents`.** Both the
  de-duplication and the realpath-relative resolution depend on that; drop either and every finding in a
  symlinked file is reported twice, or its relative links resolve from the wrong directory.
