#!/bin/sh

# Runs worktree-create.sh against scratch repositories: a home clone with the hook and a children list
# committed, and children cloned inside it from bare remotes. Every case builds its own fixture.

set -eu

hooks=$(cd "$(dirname "$0")/.." && pwd -P)
repo=$(cd "$hooks/../.." && pwd -P)
scratch=$(mktemp -d)
scratch=$(cd "$scratch" && pwd -P)
trap 'rm -rf "$scratch"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

failures=0
current=''

fail() {
  failures=$((failures + 1))
  printf 'FAIL  %s: %s\n' "$current" "$1"
}

assert_eq() {
  [ "$1" = "$2" ] || fail "$3: expected '$2', got '$1'"
}

assert_exists() {
  [ -e "$1" ] || fail "missing: $1"
}

assert_absent() {
  [ ! -e "$1" ] || fail "should not exist: $1"
}

commit() {
  git -C "$1" add -A
  git -C "$1" commit --quiet -m "$2"
}

head_of() {
  git -C "$1" rev-parse HEAD
}

branch_of() {
  git -C "$1" branch --show-current
}

# A child: a bare remote with one commit on main, and a clone in home that is one commit ahead on a
# local branch, so "remote main" and "that copy's HEAD" are different commits.
make_child() {
  name=$1
  git init --quiet --bare -b main "$scratch/remotes/$name.git"
  git clone --quiet "$scratch/remotes/$name.git" "$home/$name" 2>/dev/null
  printf '.env.local\n.cache/\nsecret.txt\n' > "$home/$name/.gitignore"
  printf '.env.local\n.cache/\ntracked.txt\nloose.txt\n' > "$home/$name/.worktreeinclude"
  echo tracked > "$home/$name/tracked.txt"
  commit "$home/$name" 'On main'
  git -C "$home/$name" push --quiet origin main
  git -C "$home/$name" remote set-head origin main
  git -C "$home/$name" switch --quiet -c local-work
  echo more > "$home/$name/more.txt"
  commit "$home/$name" 'Ahead of main'
}

# setup <children.txt names, in order>: `kid` and `kid-extra` are cloned, any other name is only listed.
setup() {
  current=$1
  shift
  rm -rf "$scratch/remotes" "$scratch/home"
  home="$scratch/home"
  mkdir -p "$scratch/remotes" "$home/.claude/hooks" "$home/scripts"
  git init --quiet -b main "$home"
  cp "$hooks/worktree-create.sh" "$home/.claude/hooks/"
  cp "$repo/scripts/children.sh" "$home/scripts/"
  for name in "$@"; do
    echo "$name git@example.com:org/$name.git"
  done > "$home/children.txt"
  printf '/kid/\n/kid-extra/\n.claude/worktrees/\n' > "$home/.gitignore"
  commit "$home" 'Home'
  make_child kid
  make_child kid-extra
  wts="$home/.claude/worktrees"
}

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
git -C "$home/kid" remote remove origin
run kid-task "$home"
assert_eq "$status" 1 'exit status for a child with no remote main'
assert_absent "$wts/kid-task"
run 'a/b' "$home"
assert_eq "$status" 1 'exit status for a name with a slash'

if [ "$failures" -gt 0 ]; then
  printf '\n%s failed\n' "$failures"
  exit 1
fi
echo 'worktree-create: all cases pass'
