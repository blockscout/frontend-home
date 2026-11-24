# The home pin and its bump — context

A consumer installs home as a pnpm git dependency pinned by commit. `home-bump` moves that pin. The
consumer has `"home:bump": "home-bump"` among its scripts, runs `pnpm home:bump [<commit-or-ref>]` and
commits the three files that change.

## What a consumer must keep true

- **The pin is written twice, and `home-bump` moves both entries.** pnpm refuses a git
  dependency's `prepare` script unless `allowBuilds` in `pnpm-workspace.yaml` names the package with its
  exact commit. So the commit is in `package.json` and in that key. Edit one by hand and the install stops
  with `ERR_PNPM_GIT_DEP_PREPARE_NOT_ALLOWED`.
- **Pin a commit on home's main branch.** A commit of a branch that is later squashed or deleted becomes
  unreachable, and then every install of the consumer fails, in CI too.
- **The first pin is written by hand**, both entries with the same commit. The command arrives with the
  dependency, so it is not there before the first install.
- **The command that runs is the one of the current pin.** A fix to the script reaches a consumer one bump
  later. When the installed command cannot do the bump, write the same commit in both entries by hand and
  run `pnpm install`.

## What an editor here must keep true

- **The script works on the directory it is run from**, the consumer's package root. Its own location is
  inside the consumer's `node_modules`.
- **The script ships as it is.** `files` in home's `package.json` lists it and nothing builds it, so it
  needs nothing but bash, git, node and pnpm.
- **`pnpm test:bump` covers every exit of the script**, with `pnpm` and `git` as stubs. A new exit gets a
  case there.
