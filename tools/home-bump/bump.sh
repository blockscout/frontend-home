#!/bin/bash

# Moves a consumer's pin of the home repo (blockscout/frontend-home) to another commit and reinstalls.
# Run it from the consumer's package root, which is where pnpm runs a package script. The pin is written
# twice there, in package.json and in the build allowlist of pnpm-workspace.yaml (CONTEXT.md, beside this
# script), and the two must name the same commit.
#
# Usage: home-bump [<commit-or-ref>]
#   <commit-or-ref>   a full commit sha, or a branch or tag of the home repo; default: main

set -euo pipefail

REPO="blockscout/frontend-home"
TARGET="${1:-main}"

for file in package.json pnpm-workspace.yaml; do
  if [ ! -f "$file" ]; then
    echo "bump: no $file in $PWD; run this from the package root" >&2
    exit 1
  fi
done

if [[ "$TARGET" =~ ^[0-9a-f]{40}$ ]]; then
  NEXT="$TARGET"
else
  # pnpm wants the exact commit in the allowlist, so a ref is resolved here and never written.
  NEXT="$(git ls-remote "https://github.com/$REPO.git" "$TARGET" | head -n 1 | cut -f 1)"
  if [ -z "$NEXT" ]; then
    echo "bump: '$TARGET' is neither a full commit sha nor a branch or tag of $REPO" >&2
    exit 1
  fi
fi

CURRENT="$(sed -n "s|.*\"github:$REPO#\([0-9a-f]\{40\}\)\".*|\1|p" package.json)"
if [ -z "$CURRENT" ]; then
  echo "bump: no github:$REPO#<sha> dependency in package.json" >&2
  exit 1
fi

if [ "$CURRENT" = "$NEXT" ]; then
  echo "bump: already pinned at $NEXT"
  exit 0
fi

if ! grep -q "$REPO/tar.gz/$CURRENT" pnpm-workspace.yaml; then
  echo "bump: pnpm-workspace.yaml does not allow the build of $CURRENT; the two pins have drifted" >&2
  exit 1
fi

CURRENT="$CURRENT" NEXT="$NEXT" REPO="$REPO" node -e '
  const fs = require("node:fs");
  const { CURRENT, NEXT, REPO } = process.env;
  const edits = {
    "package.json": `github:${ REPO }#`,
    "pnpm-workspace.yaml": `${ REPO }/tar.gz/`,
  };
  for (const [ file, prefix ] of Object.entries(edits)) {
    fs.writeFileSync(file, fs.readFileSync(file, "utf8").replace(prefix + CURRENT, prefix + NEXT));
  }
'

echo "bump: $CURRENT -> $NEXT"
pnpm install
