#!/bin/sh

# WorktreeCreate hook. Makes a task worktree: a home worktree at .claude/worktrees/<name> with child
# worktrees inside it, so the worktree mirrors the home layout and every relative path keeps working.
#
#   <child>-<rest>   that child only, on branch <rest>: the local branch when the child has one, else a
#                    new one tracking origin/<rest> when the remote has it, else a new one cut from the
#                    child's remote main branch. The longest child name that prefixes the name wins.
#   any other name   every child present in the home checkout the session runs in, each on a branch
#                    <name> cut from that copy's HEAD. A subagent's generated name lands here, which
#                    gives it the children of its parent session.
#
# The home worktree is on a branch <name>, cut from the session's home HEAD. An existing worktree is
# reopened: whatever is already there is left alone and only the missing parts are made.
#
# Claude Code serves `--worktree`, EnterWorktree and `isolation: worktree` through this one hook, and
# reads the last line of stdout as the worktree path. Everything else goes to stderr.

set -eu

exec 3>&1 1>&2

die() {
  echo "worktree-create: $*"
  exit 1
}

# A hook can inherit git's own variables, and they would aim every `git -C` below at one repository.
# shellcheck disable=SC2046
unset $(git rev-parse --local-env-vars)

input=$(cat)
name=$(printf '%s' "$input" | jq -r '.name // empty')
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
[ -n "$name" ] || die 'no worktree name in the hook input'
[ -d "$cwd" ] || die "the session directory does not exist: $cwd"
case $name in
  */*) die "a worktree name cannot contain a slash: $name" ;;
esac
git check-ref-format "refs/heads/$name" || die "not usable as a branch name: $name"

common_dir() {
  git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null
}

# The checkout this script is in may be a worktree. The main home clone owns the worktrees.
here=$(cd "$(dirname "$0")/../.." && pwd -P)
home_common=$(common_dir "$here") || die "not in a git checkout: $here"
home=$(dirname "$home_common")
wt="$home/.claude/worktrees/$name"

# The home checkout the session runs in, the main clone or a task worktree. `cwd` can be anywhere
# inside it, a child included, so climb out of every repository that is not home.
session_root() {
  dir=$1
  while top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null); do
    if [ "$(common_dir "$top")" = "$home_common" ]; then
      printf '%s\n' "$top"
      return
    fi
    dir=$(dirname "$top")
  done
  printf '%s\n' "$home"
}

has_ref() {
  git -C "$1" show-ref --verify --quiet "$2"
}

remote_main() {
  if ref=$(git -C "$1" symbolic-ref --quiet refs/remotes/origin/HEAD); then
    printf '%s\n' "$ref"
    return
  fi
  for branch in main master; do
    if has_ref "$1" "refs/remotes/origin/$branch"; then
      printf '%s\n' "refs/remotes/origin/$branch"
      return
    fi
  done
  return 1
}

# Claude Code skips .worktreeinclude when a hook creates the worktree. Same contract here: a file is
# copied when it matches a pattern and is gitignored, so a tracked file is never duplicated.
copy_includes() {
  src=$1 dest=$2
  [ -f "$src/.worktreeinclude" ] || return 0
  git -C "$src" -c core.quotePath=false ls-files --others --ignored --exclude-from="$src/.worktreeinclude" |
    git -C "$src" -c core.quotePath=false check-ignore --stdin |
    while IFS= read -r file; do
      [ -f "$src/$file" ] && [ ! -L "$src/$file" ] && [ ! -e "$dest/$file" ] || continue
      mkdir -p "$(dirname "$dest/$file")"
      cp -p "$src/$file" "$dest/$file"
    done
}

# add_child <source checkout> <child> <branch> <start point for a new branch>
add_child() {
  src=$1 child=$2 branch=$3 base=$4
  dest="$wt/$child"
  [ ! -e "$dest/.git" ] || return 0
  if has_ref "$src" "refs/heads/$branch"; then
    git -C "$src" worktree add --quiet "$dest" "$branch"
  elif [ "$base" != HEAD ] && has_ref "$src" "refs/remotes/origin/$branch"; then
    git -C "$src" worktree add --quiet --track -b "$branch" "$dest" "origin/$branch"
  else
    git -C "$src" worktree add --quiet --no-track -b "$branch" "$dest" "$base"
  fi
  copy_includes "$src" "$dest"
}

from=$(session_root "$cwd")
children=$("$here/scripts/children.sh" | cut -d ' ' -f 1)

picked=''
for child in $children; do
  case $name in
    "$child"-?*) [ "${#child}" -le "${#picked}" ] || picked=$child ;;
  esac
done

# Everything that can be refused is refused before the first worktree is made.
if [ -n "$picked" ]; then
  rest=${name#"$picked"-}
  [ -e "$home/$picked/.git" ] || die "the child $picked is not cloned in $home (scripts/bootstrap.sh)"
  git check-ref-format "refs/heads/$rest" || die "not usable as a branch name in $picked: $rest"
  base=$(remote_main "$home/$picked") || die "$picked has no remote main branch (origin/HEAD, origin/main, origin/master)"
fi

if [ ! -e "$wt/.git" ]; then
  if has_ref "$home" "refs/heads/$name"; then
    git -C "$home" worktree add --quiet "$wt" "$name"
  else
    git -C "$from" worktree add --quiet --no-track -b "$name" "$wt" HEAD
  fi
fi

if [ -n "$picked" ]; then
  add_child "$home/$picked" "$picked" "$rest" "$base"
else
  for child in $children; do
    [ -e "$from/$child/.git" ] || continue
    add_child "$from/$child" "$child" "$name" HEAD
  done
fi

printf '%s\n' "$wt" >&3
