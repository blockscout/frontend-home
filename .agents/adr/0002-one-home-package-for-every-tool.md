# One home package for every tool and library export

| | |
| --- | --- |
| Status | Accepted |

## Decision

Everything home delivers to a consumer ships in the one `frontend-home` package: each command is a `bin`
entry, and each library is a path under `exports`. A package per tool would cost every consumer one pin and
one `allowBuilds` entry per tool, each moved by its own bump. The price is that a consumer builds every
tool at install, the ones it does not use too. This holds while the build that a consumer's install runs
stays within the budget under Consequences.

## Alternatives

**A package per tool**, each its own git dependency or a workspace package published from home. A consumer
would install only what it uses and build only that. It was turned down for the pin: pnpm allows a git
dependency's `prepare` only when `allowBuilds` names the package with its exact commit, so every tool would
be a second pair of entries to keep in step in every consumer.

**A release tarball**, built once in home and installed by every consumer without a build. It removes the
build from the consumer's install and adds a release step to every change in home. It is the way out when
the budget below is exceeded, and not needed before.

## Consequences

- **A package a tool needs at run time is a peer dependency, supplied by the consumer.** The first is
  `typescript`, `>=5.7`, for `code-complexity`. The children are on different versions, and the parser
  has to read the syntax its consumer writes. Home compiles its tools with its own `typescript`, a
  development dependency.
- **`exports` closes the package.** A path a consumer imports resolves only when it has a line there. The
  cspell base config has one for that reason.
- **The build budget.** A consumer's install runs `prepare`, in CI and in the Docker image build. Adding
  `code-complexity` took a cold `prepare` from about 0.4 to about 0.9 seconds. Up to about 5 seconds
  added by one tool is accepted. More than that is an issue for the release tarball.
- **A library export is a second contract.** A command breaks a consumer only through its flags and its
  config file. A library entry also breaks it through every signature it exports, at the next pin bump.
