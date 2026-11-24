# `type-fest` instead of a types export from home

| | |
| --- | --- |
| Status | Accepted |

## Decision

The generic type utilities the children share (`SetOptional`, `DistributedOmit`, `NonEmptyTuple` and the
like) come from the public `type-fest` package and the TypeScript built-ins, and home exports no types.
Both children publish packages, and home is a private git dependency: a home type in a public signature
would leave an import in the published declarations that a consumer cannot resolve. A public package
resolves there, and a change to it costs no pin bump in each child.

## Alternatives

**A `frontend-home/types` export**, a hand-written declaration file under `exports`. It would keep the
names the children already used (`NonEmptyArray`, `PartialBy`) and cost no build step. It was turned down
for the published declarations above, and because every signature would be a contract broken at a pin bump
(`0002-one-home-package-for-every-tool.md`), for about ten one-line types of which four had a use.

## Consequences

- **The names and shapes are those of `type-fest`.** `NonEmptyTuple` is `readonly`, where the local
  `NonEmptyArray` was mutable. A type the package lacks, such as `Pairs`, is defined where it is used.
- **The package sets a TypeScript floor.** `type-fest` 6 requires TypeScript 6. A child on an older
  compiler takes an older major, and a published package that lists `type-fest` as a dependency passes the
  floor on to its consumers. The UI toolkit of `frontend` does not import it for that reason.
