#!/bin/sh

# Runs worktree-create.sh against the scratch repositories of fixture.sh.

set -eu

. "$(dirname "$0")/fixture.sh"

# run <name> <cwd>: the hook's stdout lands in $out and its exit status in $status.
run() {
  status=0
  out=$(printf '{"hook_event_name":"WorktreeCreate","name":"%s","cwd":"%s"}' "$1" "$2" |
    "$home/.claude/hooks/worktree-create.sh" 2>"$scratch/stderr") || status=$?
}

setup 'a child prefix makes that child only, on a new branch from its remote main' kid kid-extra
run kid-task "$home"
assert_eq "$status" 0 'exit status'
assert_eq "$out" "$wts/kid-task" 'stdout is the worktree path and nothing else'
assert_eq "$(branch_of "$wts/kid-task")" kid-task 'home branch'
assert_eq "$(head_of "$wts/kid-task")" "$(head_of "$home")" 'home worktree starts at the session HEAD'
assert_eq "$(branch_of "$wts/kid-task/kid")" task 'child branch'
assert_eq "$(head_of "$wts/kid-task/kid")" "$(git -C "$home/kid" rev-parse origin/main)" 'child branch starts at remote main'
assert_eq "$(git -C "$home/kid" rev-parse --abbrev-ref 'task@{upstream}' 2>/dev/null || echo none)" none 'new branch has no upstream'
assert_absent "$wts/kid-task/kid-extra"

for order in 'kid kid-extra' 'kid-extra kid'; do
  # shellcheck disable=SC2086
  setup "the longest child prefix wins (children listed as: $order)" $order
  run kid-extra-task "$home"
  assert_eq "$status" 0 'exit status'
  assert_eq "$(branch_of "$wts/kid-extra-task/kid-extra")" task 'child branch'
  assert_absent "$wts/kid-extra-task/kid"
done

setup 'any other name mirrors every child present, each from that copy HEAD' kid kid-extra not-cloned
run scratchpad "$home"
assert_eq "$status" 0 'exit status'
assert_eq "$out" "$wts/scratchpad" 'stdout'
for child in kid kid-extra; do
  assert_eq "$(branch_of "$wts/scratchpad/$child")" scratchpad "$child branch"
  assert_eq "$(head_of "$wts/scratchpad/$child")" "$(head_of "$home/$child")" "$child starts at the clone HEAD"
done
assert_absent "$wts/scratchpad/not-cloned"

setup 'a mirror made inside a task worktree gets that worktree children and commits' kid kid-extra
run kid-task "$home"
echo home-work > "$wts/kid-task/home-work.txt"
commit "$wts/kid-task" 'Home work in the task worktree'
echo child-work > "$wts/kid-task/kid/child-work.txt"
commit "$wts/kid-task/kid" 'Child work in the task worktree'
run agent-1 "$wts/kid-task"
assert_eq "$status" 0 'exit status'
assert_eq "$out" "$wts/agent-1" 'the worktree sits beside its parent, not inside it'
assert_eq "$(head_of "$wts/agent-1")" "$(head_of "$wts/kid-task")" 'home starts at the task worktree HEAD'
assert_eq "$(head_of "$wts/agent-1/kid")" "$(head_of "$wts/kid-task/kid")" 'child starts at the task worktree child HEAD'
assert_absent "$wts/agent-1/kid-extra"
run agent-2 "$wts/kid-task/kid"
assert_eq "$status" 0 'exit status with the session directory inside the child'
assert_eq "$(head_of "$wts/agent-2/kid")" "$(head_of "$wts/kid-task/kid")" 'child, from inside the child'
assert_absent "$wts/agent-2/kid-extra"

setup 'an existing task worktree is reopened as it is' kid kid-extra
run kid-task "$home"
echo work > "$wts/kid-task/kid/work.txt"
commit "$wts/kid-task/kid" 'Work'
echo dirty > "$wts/kid-task/kid/dirty.txt"
before=$(head_of "$wts/kid-task/kid")
run kid-task "$home"
assert_eq "$status" 0 'exit status'
assert_eq "$out" "$wts/kid-task" 'stdout'
assert_eq "$(head_of "$wts/kid-task/kid")" "$before" 'child HEAD is untouched'
assert_exists "$wts/kid-task/kid/dirty.txt"
run scratchpad "$home"
run scratchpad "$home"
assert_eq "$status" 0 'exit status, mirrored worktree'

setup 'a reopened worktree that lost its child gets it back on the same branch' kid kid-extra
run kid-task "$home"
echo work > "$wts/kid-task/kid/work.txt"
commit "$wts/kid-task/kid" 'Work'
before=$(head_of "$wts/kid-task/kid")
git -C "$home/kid" worktree remove "$wts/kid-task/kid"
run kid-task "$home"
assert_eq "$status" 0 'exit status'
assert_eq "$(branch_of "$wts/kid-task/kid")" task 'child branch'
assert_eq "$(head_of "$wts/kid-task/kid")" "$before" 'child is back at the branch tip'

setup 'a branch the child already has is checked out, local or remote, not cut again' kid kid-extra
git -C "$home/kid" branch existing local-work
git -C "$home/kid" push --quiet origin local-work:pushed
run kid-existing "$home"
assert_eq "$(head_of "$wts/kid-existing/kid")" "$(head_of "$home/kid")" 'local branch tip'
run kid-pushed "$home"
assert_eq "$(head_of "$wts/kid-pushed/kid")" "$(git -C "$home/kid" rev-parse origin/pushed)" 'remote branch tip'
assert_eq "$(git -C "$home/kid" rev-parse --abbrev-ref 'pushed@{upstream}')" origin/pushed 'remote branch is tracked'

setup 'worktree-include files are copied when listed and gitignored' kid kid-extra
mkdir -p "$home/kid/.cache/deep"
echo env > "$home/kid/.env.local"
echo cached > "$home/kid/.cache/deep/file"
echo secret > "$home/kid/secret.txt"
echo loose > "$home/kid/loose.txt"
run kid-task "$home"
assert_eq "$(cat "$wts/kid-task/kid/.env.local" 2>/dev/null)" env 'listed and ignored file'
assert_eq "$(cat "$wts/kid-task/kid/.cache/deep/file" 2>/dev/null)" cached 'file in a listed and ignored directory'
assert_absent "$wts/kid-task/kid/secret.txt"
assert_absent "$wts/kid-task/kid/loose.txt"
assert_eq "$(git -C "$wts/kid-task/kid" status --porcelain)" '' 'the child worktree is clean'
run agent-1 "$wts/kid-task"
assert_eq "$(cat "$wts/agent-1/kid/.env.local" 2>/dev/null)" env 'a mirror copies from the worktree it mirrors'

setup 'inherited git variables do not redirect the hook' kid kid-extra
export GIT_DIR="$home/kid/.git" GIT_WORK_TREE="$home/kid" GIT_INDEX_FILE="$home/kid/.git/index"
run kid-task "$home"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
assert_eq "$status" 0 'exit status'
assert_eq "$(branch_of "$wts/kid-task")" kid-task 'home branch'
assert_eq "$(branch_of "$wts/kid-task/kid")" task 'child branch'
assert_eq "$(git -C "$home/kid" status --porcelain)" '' 'the child clone is untouched'

setup 'a refused name leaves nothing behind' kid kid-extra not-cloned
run not-cloned-task "$home"
assert_eq "$status" 1 'exit status for a child that is not cloned'
assert_eq "$out" '' 'no path on stdout'
assert_absent "$wts/not-cloned-task"
assert_eq "$(git -C "$home" branch --list not-cloned-task)" '' 'no home branch'
run kid-local-work "$home"
assert_eq "$status" 1 'exit status for a child branch that is checked out in the child clone'
assert_absent "$wts/kid-local-work"
assert_eq "$(git -C "$home" branch --list kid-local-work)" '' 'no home branch'
git -C "$home/kid-extra" switch --quiet -c scratchpad
run scratchpad "$home"
assert_eq "$status" 1 'exit status for a mirror whose branch is checked out in a child clone'
assert_absent "$wts/scratchpad"
assert_eq "$(git -C "$home/kid" branch --list scratchpad)" '' 'no branch in the other child'
git -C "$home/kid" remote remove origin
run kid-task "$home"
assert_eq "$status" 1 'exit status for a child with no remote main'
assert_absent "$wts/kid-task"
run 'a/b' "$home"
assert_eq "$status" 1 'exit status for a name with a slash'

finish worktree-create
