#!/bin/sh

# Runs the doc-link checker on home with every child passed as `--child`: a shared skill or rule names a
# child's file by its path from the child's root, so the check needs the children cloned.

set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
children=$("$root/scripts/children.sh")

set --
for name in $(printf '%s\n' "$children" | cut -d ' ' -f 1); do
  set -- "$@" --child "$name"
done

# Compiled on every run, so the check is the working tree's source and not the build left by the last install.
"$root/node_modules/.bin/tsc" -p "$root/tools/doc-links/tsconfig.json"
exec node "$root/tools/doc-links/dist/index.js" "$@"
