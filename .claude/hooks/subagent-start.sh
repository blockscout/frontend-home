#!/bin/sh

# SubagentStart hook. A worktree-isolated subagent starts with home's instructions but never loads a
# child's always-loaded instructions, not even on reading a file in the child. This names the file for
# it to read.
#
# The input does not say whether a subagent is isolated. An isolated one runs in a worktree that
# Claude Code names `agent-<agent_id>`; any other subagent shares its session's directory, where the
# child's instructions load on the first read, so it gets nothing.

set -eu

# A hook can inherit git's own variables, and they would aim every `git -C` below at one repository.
# shellcheck disable=SC2046
unset $(git rev-parse --local-env-vars)

input=$(cat)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
agent_id=$(printf '%s' "$input" | jq -r '.agent_id // empty')

[ -n "$agent_id" ] && [ -d "$cwd" ] || exit 0
wt=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ "$(basename "$wt")" = "agent-$agent_id" ] || exit 0

root=$(cd "$(dirname "$0")/../.." && pwd -P)

files=''
for child in $("$root/scripts/children.sh" | cut -d ' ' -f 1); do
  [ -e "$wt/$child/.git" ] || continue
  for file in .claude/CLAUDE.md CLAUDE.md AGENTS.md; do
    [ -f "$wt/$child/$file" ] || continue
    files="$files
- \`$child\`: $wt/$child/$file"
    break
  done
done
[ -n "$files" ] || exit 0

jq -n --arg wt "$wt" --arg files "$files" '{
  hookSpecificOutput: {
    hookEventName: "SubagentStart",
    additionalContext: (
      "You run in your own task worktree, " + $wt + ". The always-loaded instructions of the children inside it do not load for you by themselves. Before working in a child, read its instructions file in full and follow it as project instructions:" + $files
    )
  }
}'
