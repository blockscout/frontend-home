#!/bin/sh

# SessionStart hook. Fetches every child present in the home checkout the session starts in, so a task
# worktree cut later starts from a current remote main. A fetch that fails is not worth a word: the
# session works on the refs it has.

set -u

# A hook can inherit git's own variables, and they would aim every `git -C` below at one repository.
# shellcheck disable=SC2046
unset $(git rev-parse --local-env-vars)

root=$(cd "$(dirname "$0")/../.." && pwd -P)

for child in $("$root/scripts/children.sh" | cut -d ' ' -f 1); do
  [ -e "$root/$child/.git" ] || continue
  git -C "$root/$child" fetch --quiet origin 2>/dev/null &
done
wait

exit 0
