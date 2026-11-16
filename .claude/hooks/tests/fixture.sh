# Sourced by the hook tests. Scratch repositories to run a hook against: a home clone with the hooks and
# a children list committed, and children cloned inside it from bare remotes. Every case builds its own
# fixture with `setup`.

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

# finish <suite name>: the last line of a test file.
finish() {
  if [ "$failures" -gt 0 ]; then
    printf '\n%s failed\n' "$failures"
    exit 1
  fi
  echo "$1: all cases pass"
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

# setup <case name> <children.txt names, in order>: `kid` and `kid-extra` are cloned, any other name is
# only listed.
setup() {
  current=$1
  shift
  rm -rf "$scratch/remotes" "$scratch/home"
  home="$scratch/home"
  mkdir -p "$scratch/remotes" "$home/.claude/hooks" "$home/scripts"
  git init --quiet -b main "$home"
  cp "$hooks"/*.sh "$home/.claude/hooks/"
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
