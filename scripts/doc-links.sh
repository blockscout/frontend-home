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

exec "$root/tools/doc-links/run.sh" "$@"
