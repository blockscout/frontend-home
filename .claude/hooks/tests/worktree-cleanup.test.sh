#!/bin/sh

# Runs worktree-cleanup.sh against the scratch repositories of fixture.sh. The task worktrees are made
# by worktree-create.sh, and GitHub is a stub `gh` that answers from a file per child.

set -eu

. "$(dirname "$0")/fixture.sh"

mkdir -p "$scratch/bin"
cat > "$scratch/bin/gh" << 'STUB'
#!/bin/sh
# `gh auth status` and `gh pr list`, answered from $GH_STUB/<directory it runs in>.json.
[ ! -e "$GH_STUB/down" ] || exit 1
echo "$*" >> "$GH_STUB/calls"
case "$1 $2" in
  'auth status') exit 0 ;;
  'pr list') ;;
  *) exit 1 ;;
esac
state=all
head=''
while [ $# -gt 0 ]; do
  case $1 in
    --state) state=$2 ;;
    --head) head=$2 ;;
  esac
  shift
done
file="$GH_STUB/$(basename "$PWD").json"
[ -f "$file" ] || echo '[]' > "$file"
# A merged pull request that has dropped out of the list of the latest ones.
[ "$state" != merged ] || [ ! -e "$GH_STUB/merged-long-ago" ] || file=/dev/null
jq --arg state "$state" --arg head "$head" 'map(select(
  ($state == "all" or (.state | ascii_downcase) == $state) and ($head == "" or .headRefName == $head)
))' "$file" | jq -s '.[0] // []'
STUB
chmod +x "$scratch/bin/gh"
PATH="$scratch/bin:$PATH"
export GH_STUB="$scratch/gh"

# Every worktree counts as idle unless a case says otherwise.
export CLAUDE_WORKTREE_IDLE_DAYS=0

fresh() {
  setup "$@"
  rm -rf "$GH_STUB"
  mkdir -p "$GH_STUB"
}

# create <name> [cwd]
create() {
  printf '{"hook_event_name":"WorktreeCreate","name":"%s","cwd":"%s"}' "$1" "${2:-$home}" |
    "$home/.claude/hooks/worktree-create.sh" > /dev/null 2>&1
}

# work <checkout>: one more commit in it.
work() {
  echo "$(date) $$" >> "$1/work.txt"
  commit "$1" 'Work'
}

# pr <child> <OPEN|MERGED|CLOSED> <branch> <head commit>
pr() {
  file="$GH_STUB/$1.json"
  [ -f "$file" ] || echo '[]' > "$file"
  jq --arg state "$2" --arg branch "$3" --arg oid "$4" \
    '. + [{ state: $state, headRefName: $branch, headRefOid: $oid, url: ("https://example.com/pr/" + $branch) }]' \
    "$file" > "$file.next"
  mv "$file.next" "$file"
}

# prune [extra arguments]: the report lands in $report, the exit status in $status. Takes $script and
# $cwd when a case sets them.
prune() {
  status=0
  out=$(printf '{"hook_event_name":"SessionStart","cwd":"%s"}' "${cwd:-$home}" |
    "${script:-$home/.claude/hooks/worktree-cleanup.sh}" prune "$@" 2> "$scratch/stderr") || status=$?
  report=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext // empty')
}

# remove <worktree path>: stderr lands in $report, the exit status in $status.
remove() {
  status=0
  printf '{"hook_event_name":"WorktreeRemove","cwd":"%s","worktree_path":"%s"}' "$1" "$1" |
    "${script:-$home/.claude/hooks/worktree-cleanup.sh}" remove > "$scratch/stdout" 2> "$scratch/stderr" || status=$?
  report=$(cat "$scratch/stderr")
}

assert_reports() {
  case $report in
    *"$1"*) ;;
    *) fail "the report should say '$1', got '$report'" ;;
  esac
}

worktrees_at() {
  git -C "$1" worktree list --porcelain | grep -c "^worktree $2\$" || true
}

# assert_gone <worktree name> [<child> <child branch>]...: all four are removed.
assert_gone() {
  gone_name=$1
  shift
  assert_absent "$wts/$gone_name"
  assert_eq "$(worktrees_at "$home" "$wts/$gone_name")" 0 "home worktree $gone_name"
  assert_eq "$(git -C "$home" branch --list "$gone_name")" '' "home branch $gone_name"
  while [ $# -gt 0 ]; do
    assert_eq "$(worktrees_at "$home/$1" "$wts/$gone_name/$1")" 0 "$1 worktree in $gone_name"
    assert_eq "$(git -C "$home/$1" branch --list "$2")" '' "$1 branch $2"
    shift 2
  done
}

# assert_intact <worktree name> [<child> <child branch>]...: all four are still there.
assert_intact() {
  intact_name=$1
  shift
  assert_eq "$(worktrees_at "$home" "$wts/$intact_name")" 1 "home worktree $intact_name"
  assert_eq "$(branch_of "$wts/$intact_name" 2> /dev/null)" "$intact_name" "home branch of $intact_name"
  while [ $# -gt 0 ]; do
    assert_eq "$(worktrees_at "$home/$1" "$wts/$intact_name/$1")" 1 "$1 worktree in $intact_name"
    assert_eq "$(branch_of "$wts/$intact_name/$1" 2> /dev/null)" "$2" "$1 branch in $intact_name"
    shift 2
  done
}

fresh 'prune: a branch that is an ancestor of the remote main is proven, and all four go' kid kid-extra
create kid-task
prune
assert_eq "$status" 0 'exit status'
assert_gone kid-task kid task
assert_reports 'removed kid-task (kid branch task, home branch kid-task)'
assert_eq "$(printf '%s' "$out" | jq -r '.systemMessage')" "$report" 'a removal is shown to the user'
assert_eq "$(cat "$GH_STUB/calls" 2> /dev/null)" '' 'GitHub is not asked when git proves it'
assert_eq "$(branch_of "$home/kid")" local-work 'the child clone is untouched'
prune
assert_eq "$out" '' 'nothing to report when there is no task worktree'

fresh 'prune: a merged pull request whose head is the branch tip is the proof' kid kid-extra
create kid-task
work "$wts/kid-task/kid"
pr kid MERGED task "$(head_of "$wts/kid-task/kid")"
prune
assert_gone kid-task kid task
assert_reports 'removed kid-task'

fresh 'prune: a commit after the merge moves the tip, and the worktree is kept and reported' kid kid-extra
create kid-task
work "$wts/kid-task/kid"
pr kid MERGED task "$(head_of "$wts/kid-task/kid")"
work "$wts/kid-task/kid"
prune
assert_intact kid-task kid task
assert_reports 'kept: kid-task: kid: 2 commit(s) not landed (branch task)'
assert_eq "$(printf '%s' "$out" | jq -r '.systemMessage // empty')" '' 'no message to the user when nothing is removed'

fresh 'prune: a merged pull request older than the prefetch is found by asking for the branch' kid kid-extra
create kid-task
work "$wts/kid-task/kid"
pr kid MERGED task "$(head_of "$wts/kid-task/kid")"
: > "$GH_STUB/merged-long-ago"
prune
assert_gone kid-task kid task
assert_eq "$(grep -c -e '--head task' "$GH_STUB/calls")" 1 'queries for the branch'

fresh 'prune: an open pull request keeps the branch, merged before or not' kid kid-extra
create kid-task
work "$wts/kid-task/kid"
pr kid MERGED task "$(head_of "$wts/kid-task/kid")"
pr kid OPEN task "$(head_of "$wts/kid-task/kid")"
prune
assert_intact kid-task kid task
assert_reports 'kid-task: kid: open PR on task'

fresh 'prune: with no pull request the commits are unproven' kid kid-extra
create kid-task
work "$wts/kid-task/kid"
git -C "$wts/kid-task/kid" push --quiet origin task
prune
assert_intact kid-task kid task
assert_reports 'kid-task: kid: 1 commit(s) not landed (branch task)'

fresh 'prune: any GitHub failure resolves to keep' kid kid-extra
create kid-task
work "$wts/kid-task/kid"
pr kid MERGED task "$(head_of "$wts/kid-task/kid")"
create scratchpad
: > "$GH_STUB/down"
prune
assert_intact kid-task kid task
assert_intact scratchpad kid scratchpad kid-extra scratchpad
assert_reports 'kid-task: kid: 1 commit(s) not landed (branch task), GitHub not asked'
rm "$GH_STUB/down"
export CLAUDE_WORKTREE_NO_GH=1
prune
unset CLAUDE_WORKTREE_NO_GH
assert_intact kid-task kid task
assert_intact scratchpad kid scratchpad kid-extra scratchpad
assert_eq "$(cat "$GH_STUB/calls" 2> /dev/null)" '' 'GitHub is not asked when it is switched off'
printf '#!/bin/sh\n[ "$1" = auth ] && exit 0\necho "rate limited"\nexit 0\n' > "$scratch/bin/gh.broken"
chmod +x "$scratch/bin/gh.broken"
mv "$scratch/bin/gh" "$scratch/bin/gh.works" && mv "$scratch/bin/gh.broken" "$scratch/bin/gh"
prune
mv "$scratch/bin/gh.works" "$scratch/bin/gh"
assert_intact kid-task kid task
assert_intact scratchpad kid scratchpad kid-extra scratchpad

fresh 'prune: an uncommitted change keeps the worktree, in a child or in home' kid kid-extra
create kid-task
echo untracked > "$wts/kid-task/kid/untracked.txt"
create kid-other
echo changed >> "$wts/kid-other/children.txt"
prune
assert_intact kid-task kid task
assert_intact kid-other kid other
assert_reports 'kid-task: 1 uncommitted change(s) in kid'
assert_reports 'kid-other: 1 uncommitted change(s) in home'
assert_exists "$wts/kid-task/kid/untracked.txt"

fresh 'prune: the idle window applies to the home worktree and to every child in it' kid kid-extra
create kid-task
unset CLAUDE_WORKTREE_IDLE_DAYS
prune
assert_intact kid-task kid task
assert_reports 'kid-task: landed but active within 3d'
touch -t 202001010000 "$(git -C "$wts/kid-task" rev-parse --absolute-git-dir)/index"
prune
assert_intact kid-task kid task
touch -t 202001010000 "$(git -C "$wts/kid-task/kid" rev-parse --absolute-git-dir)/index"
prune --report
assert_intact kid-task kid task
assert_reports 'kid-task: prunable, clean, idle and landed (kid in remotes/origin/main)'
prune
assert_gone kid-task kid task
export CLAUDE_WORKTREE_IDLE_DAYS=0

fresh 'prune: a mirrored worktree goes only when every child is proven' kid kid-extra
git -C "$home/kid" switch --quiet --detach origin/main
git -C "$home/kid-extra" switch --quiet --detach origin/main
create scratchpad
work "$wts/scratchpad/kid-extra"
prune
assert_intact scratchpad kid scratchpad kid-extra scratchpad
assert_reports 'scratchpad: kid-extra: 1 commit(s) not landed (branch scratchpad)'
pr kid-extra MERGED scratchpad "$(head_of "$wts/scratchpad/kid-extra")"
prune
assert_gone scratchpad kid scratchpad kid-extra scratchpad
assert_reports 'removed scratchpad (kid branch scratchpad, kid-extra branch scratchpad, home branch scratchpad)'

fresh 'prune: a mirror of unlanded work is proven while its branches hold nothing of their own' kid kid-extra
create agent-1
create agent-2
work "$wts/agent-2/kid"
create agent-3
pr kid OPEN agent-3 "$(head_of "$wts/agent-3/kid")"
prune
assert_gone agent-1 kid agent-1 kid-extra agent-1
assert_intact agent-2 kid agent-2 kid-extra agent-2
assert_intact agent-3 kid agent-3 kid-extra agent-3
assert_reports 'agent-2: kid: 2 commit(s) not landed (branch agent-2)'
assert_reports 'agent-3: kid: open PR on agent-3'
assert_eq "$(git -C "$home/kid" rev-parse local-work)" "$(head_of "$home/kid")" 'the mirrored branch is untouched'

fresh 'prune: a pushed branch is not proven by its own remote copy' kid kid-extra
create kid-task
work "$wts/kid-task/kid"
git -C "$wts/kid-task/kid" push --quiet origin task
git -C "$home/kid" fetch --quiet origin
prune
assert_intact kid-task kid task

fresh 'prune: home commits that are on no other branch keep the worktree' kid kid-extra
create kid-task
work "$wts/kid-task"
prune
assert_intact kid-task kid task
assert_reports 'kid-task: home commits that are on no other branch (branch kid-task)'
git -C "$home" merge --quiet kid-task
prune
assert_gone kid-task kid task

fresh 'prune: a locked worktree is kept' kid kid-extra
create kid-task
git -C "$home/kid" worktree lock "$wts/kid-task/kid"
prune
assert_intact kid-task kid task
assert_reports 'kid-task: kid locked by a live session'

fresh 'prune: the worktree the session is in is kept' kid kid-extra
create kid-task
cwd="$wts/kid-task/kid"
prune
unset cwd
assert_intact kid-task kid task
assert_reports 'kid-task: this session is in it'

fresh 'prune: a worktree copy of the hook prunes nothing' kid kid-extra
create kid-task
create kid-other
script="$wts/kid-other/.claude/hooks/worktree-cleanup.sh"
prune
unset script
assert_eq "$status" 0 'exit status'
assert_eq "$out" '' 'no report'
assert_intact kid-task kid task

fresh 'prune: the main branch of a child is never deleted' kid kid-extra
create kid-main
prune
assert_absent "$wts/kid-main"
assert_eq "$(git -C "$home/kid" branch --list main | tr -d ' ')" main 'kid branch main'

fresh 'prune: inherited git variables do not redirect the hook' kid kid-extra
create kid-task
create kid-kept
work "$wts/kid-kept/kid"
export GIT_DIR="$home/kid/.git" GIT_WORK_TREE="$home/kid" GIT_INDEX_FILE="$home/kid/.git/index"
prune
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
assert_gone kid-task kid task
assert_intact kid-kept kid kept
assert_eq "$(git -C "$home/kid" status --porcelain)" '' 'the child clone is untouched'

fresh 'remove: a proven worktree loses all four, with no idle window' kid kid-extra
unset CLAUDE_WORKTREE_IDLE_DAYS
create kid-task
remove "$wts/kid-task"
assert_eq "$status" 0 'exit status'
assert_gone kid-task kid task
assert_eq "$(cat "$scratch/stdout")" '' 'nothing on stdout'
remove "$wts/kid-task"
assert_eq "$status" 0 'exit status when the worktree is already gone'
export CLAUDE_WORKTREE_IDLE_DAYS=0

fresh 'remove: run from the copy inside the worktree, as a session in it does' kid kid-extra
create scratchpad
status=0
(
  cd "$wts/scratchpad/kid"
  printf '{"hook_event_name":"WorktreeRemove","worktree_path":"%s"}' "$wts/scratchpad" |
    "$wts/scratchpad/.claude/hooks/worktree-cleanup.sh" remove 2> "$scratch/stderr"
) || status=$?
assert_eq "$status" 0 'exit status'
assert_gone scratchpad kid scratchpad kid-extra scratchpad

fresh 'remove: an unproven worktree is kept, with the reason and a failing status' kid kid-extra
create kid-task
work "$wts/kid-task/kid"
remove "$wts/kid-task"
assert_eq "$status" 1 'exit status for unlanded commits'
assert_intact kid-task kid task
assert_reports "kept $wts/kid-task: kid: 1 commit(s) not landed (branch task)"
create kid-dirty
echo untracked > "$wts/kid-dirty/kid/untracked.txt"
remove "$wts/kid-dirty"
assert_eq "$status" 1 'exit status for an uncommitted change'
assert_intact kid-dirty kid dirty
assert_exists "$wts/kid-dirty/kid/untracked.txt"
pr kid MERGED task "$(head_of "$wts/kid-task/kid")"
remove "$wts/kid-task"
assert_eq "$status" 0 'exit status once the pull request is merged'
assert_gone kid-task kid task

fresh 'remove: a path that is not a task worktree of this home is refused' kid kid-extra
create kid-task
for path in "$home" "$home/kid" "$wts/kid-task/kid" "$wts" "$scratch"; do
  remove "$path"
  assert_eq "$status" 1 "exit status for $path"
done
remove ''
assert_eq "$status" 1 'exit status for no path'
assert_intact kid-task kid task
assert_exists "$home/kid/.git"
assert_eq "$(branch_of "$home/kid")" local-work 'the child clone is untouched'

fresh 'remove: inherited git variables do not redirect the hook' kid kid-extra
create kid-task
export GIT_DIR="$home/kid/.git" GIT_WORK_TREE="$home/kid" GIT_INDEX_FILE="$home/kid/.git/index"
remove "$wts/kid-task"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
assert_eq "$status" 0 'exit status'
assert_gone kid-task kid task
assert_eq "$(git -C "$home/kid" status --porcelain)" '' 'the child clone is untouched'

finish worktree-cleanup
