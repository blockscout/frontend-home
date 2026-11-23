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

TARGET_SHA="$(tr 'A-F' 'a-f' <<< "$TARGET")"
if [[ "$TARGET_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  NEXT="$TARGET_SHA"
else
  # pnpm wants the exact commit in the allowlist, so a ref is resolved here and never written. The full ref
  # names are asked for because a bare name gives the tag object of an annotated tag, not its commit, and
  # also matches every ref that ends in that name.
  REFS="$(git ls-remote "https://github.com/$REPO.git" "refs/heads/$TARGET" "refs/tags/$TARGET" "refs/tags/$TARGET^{}")"
  BRANCH=''
  TAG=''
  TAGGED_COMMIT=''
  while IFS=$'\t' read -r oid ref; do
    case "$ref" in
      "refs/heads/$TARGET") BRANCH="$oid" ;;
      "refs/tags/$TARGET") TAG="$oid" ;;
      "refs/tags/$TARGET^{}") TAGGED_COMMIT="$oid" ;;
    esac
  done <<< "$REFS"
  TAG="${TAGGED_COMMIT:-$TAG}"
  if [ -n "$BRANCH" ] && [ -n "$TAG" ]; then
    echo "bump: '$TARGET' is both a branch and a tag of $REPO; pass the commit sha instead" >&2
    exit 1
  fi
  NEXT="${BRANCH:-$TAG}"
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

if ! grep -q "$REPO/tar.gz/$CURRENT" pnpm-workspace.yaml; then
  echo "bump: pnpm-workspace.yaml does not allow the build of $CURRENT; the two pins have drifted" >&2
  exit 1
fi

if [ "$CURRENT" = "$NEXT" ]; then
  echo "bump: already pinned at $NEXT"
  exit 0
fi

SNAPSHOT="$(mktemp -d)"
trap 'rm -rf "$SNAPSHOT"' EXIT
for file in package.json pnpm-workspace.yaml pnpm-lock.yaml; do
  if [ -f "$file" ]; then
    cp "$file" "$SNAPSHOT/"
  fi
done

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
# Pins left moved by a failed install would make the next run answer "already pinned" and install nothing.
if ! pnpm install; then
  cp "$SNAPSHOT"/* .
  echo "bump: pnpm install failed; the pin and the lockfile are back at $CURRENT" >&2
  exit 1
fi
