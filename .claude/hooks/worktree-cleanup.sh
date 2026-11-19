#!/bin/sh

# Retires a task worktree once its work has landed: the child worktrees inside it, their branches, the
# home worktree and the home worktree's branch. One decision, two hooks:
#
#   prune    SessionStart. Every task worktree that is proven and idle is removed, the rest are reported.
#            `prune --report` lists what would go and removes nothing.
#   remove   WorktreeRemove. The one worktree in `worktree_path` is removed when it is proven. Otherwise
#            it stays, the reason goes to stderr and the exit status is 1, which keeps the directory.
#
# A worktree is proven when nothing in it exists only there:
#
#   - no uncommitted change in the home worktree or in any child inside it;
#   - the home worktree's commit is on another home branch, so its own branch holds nothing, or a merged
#     home pull request has exactly that commit as its head. An open pull request on the branch keeps it;
#   - every child branch has landed, by the proof `frontend`'s own worktree-prune.sh uses: its tip is an
#     ancestor of the child's main branch, or a merged pull request has exactly that tip as its head.
#     Pull requests are squash-merged, so the second is the one that fires. An open pull request on the
#     branch keeps it.
#
# One proof is home's own. A mirrored worktree is cut from its parent's HEAD, which is rarely on main,
# and a subagent's mirror never gets a pull request. Such a child branch is proven when GitHub knows no
# open pull request for it and its tip is on another branch of the child: deleting it loses a name.
#
# Anything unproven is reported and left whole, and every GitHub failure (no gh, offline, rate limit)
# resolves to keep. A worktree with several children goes only when every one of them is proven.
#
# `remove` applies the proof because Claude Code can run the hook unprompted: it looks for changes in
# the home worktree only, so at the exit of an unnamed session a child's unpushed work is invisible to
# it. The hook is the last check.
#
# `prune` adds an idle window, because another session may be working in a clean worktree right now.
# It runs from the main home clone only: a worktree's copy of this script is as old as the worktree.
#
# Env:
#   CLAUDE_WORKTREE_IDLE_DAYS  how long a worktree must be untouched before `prune` takes it (default 3)
#   CLAUDE_WORKTREE_NO_GH      set to 1 to skip the pull request lookups (offline)

set -u

# The whole script is inside one function, so the shell has read all of it before `remove` deletes the
# worktree this copy may live in.
main() {
  mode=${1:-}
  report_only=false
  [ "${2:-}" = --report ] && report_only=true
  case $mode in
    prune | remove) ;;
    *)
      echo 'usage: worktree-cleanup.sh prune [--report] | remove' >&2
      exit 1
      ;;
  esac

  # A hook can inherit git's own variables, and they would aim every `git -C` below at one repository.
  # shellcheck disable=SC2046
  unset $(git rev-parse --local-env-vars)

  input=$(cat 2>/dev/null || true)
  idle_days=${CLAUDE_WORKTREE_IDLE_DAYS:-3}
  idle_cutoff=$(($(date +%s) - idle_days * 86400))

  # The checkout this script is in may be a worktree. The main home clone owns the worktrees.
  here=$(cd "$(dirname "$0")/../.." && pwd -P)
  home_common=$(common_dir "$here") || quit "not in a git checkout: $here"
  home=$(dirname "$home_common")
  # On its own, not in a pipeline: a list that does not parse must stop the run, not read as no children,
  # which would hide the child worktrees from the proof.
  listed=$("$here/scripts/children.sh" 2>/dev/null) || quit 'children.txt does not parse (scripts/children.sh)'
  children=$(printf '%s\n' "$listed" | cut -d ' ' -f 1)

  tmp=$(mktemp -d) || quit 'no temporary directory'
  trap 'rm -rf "$tmp"' EXIT

  # Not the worktree that may be about to go.
  cd "$home" || quit "cannot enter $home"

  gh_ready=''
  gh_calls=0
  gh_budget=10

  "$mode"
}

# Nothing to do, or nothing safe to do. For `remove` that is a refusal, and the worktree stays.
quit() {
  [ "$mode" = remove ] || exit 0
  echo "worktree-cleanup: $*" >&2
  exit 1
}

common_dir() {
  git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null
}

admin_dir() {
  git -C "$1" rev-parse --absolute-git-dir 2>/dev/null
}

has_ref() {
  git -C "$1" show-ref --verify --quiet "$2"
}

# GNU first: BSD stat fails on -c with no output, while GNU stat reads -f as "file system" and prints.
mtime() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null
}

changes_in() {
  # Without the optional locks `status` does not rewrite the index, whose age is the idle clock.
  git --no-optional-locks -C "$1" status --porcelain 2>/dev/null | wc -l | tr -d ' '
}

# The ref a repository's work lands on.
main_ref() {
  if ref=$(git -C "$1" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null); then
    printf '%s\n' "$ref"
    return
  fi
  for ref in refs/remotes/origin/main refs/remotes/origin/master refs/heads/main refs/heads/master; do
    if has_ref "$1" "$ref"; then
      printf '%s\n' "$ref"
      return
    fi
  done
  return 1
}

# other_ref <repository> <branch> <commit>: a branch that holds the commit, other than the given one
# and its remote copies. A pushed branch is not proven by its own push.
other_ref() {
  git -C "$1" for-each-ref --contains "$3" --format='%(refname)' refs/heads refs/remotes 2>/dev/null |
    awk -v branch="$2" '
      $0 == "refs/heads/" branch { next }
      /^refs\/remotes\/[^\/]+\/HEAD$/ { next }
      /^refs\/remotes\// {
        name = $0
        sub(/^refs\/remotes\/[^\/]+\//, "", name)
        if (name == branch) next
      }
      { print; exit }
    '
}

# Resolved on first use: `gh auth status` reaches for the keyring and the network, and most runs have
# nothing to ask.
gh_available() {
  if [ -z "$gh_ready" ]; then
    if [ "${CLAUDE_WORKTREE_NO_GH:-}" != 1 ] && command -v gh > /dev/null 2>&1 && gh auth status > /dev/null 2>&1; then
      gh_ready=true
    else
      gh_ready=false
    fi
  fi
  [ "$gh_ready" = true ]
}

# One pair of queries per child covers every worktree, so the cost is flat. Sets pr_cache, and fails
# when GitHub did not answer.
pr_prefetch() {
  pr_cache="$tmp/pr-$(printf '%s' "$1" | cksum | cut -d ' ' -f 1)"
  if [ ! -d "$pr_cache" ]; then
    mkdir -p "$pr_cache"
    # Each answer lands in a file first: in a pipeline a failed gh would read as an empty list.
    (cd "$1" && gh pr list --state open --limit 100 --json headRefName) > "$pr_cache/open.json" 2> /dev/null &&
      (cd "$1" && gh pr list --state merged --limit 100 --json headRefName,headRefOid,url) > "$pr_cache/merged.json" 2> /dev/null &&
      jq -r 'if type == "array" then .[].headRefName else error end' "$pr_cache/open.json" > "$pr_cache/open" 2> /dev/null &&
      jq -r 'if type == "array" then .[] | "\(.headRefOid) \(.headRefName) \(.url)" else error end' \
        "$pr_cache/merged.json" > "$pr_cache/merged" 2> /dev/null &&
      : > "$pr_cache/ok"
  fi
  [ -e "$pr_cache/ok" ]
}

# pr_check <repository> <branch> <tip> <is the tip on another branch: true|false>
# Sets pr_state to open, merged (with pr_url), none or unknown. Results are globals because a command
# substitution would lose the prefetch and the call budget. `unknown` is every case where GitHub was
# not asked or did not answer.
pr_check() {
  pr_state=unknown
  pr_url=''
  gh_available || return 0
  pr_prefetch "$1" || return 0

  if grep -Fqx -e "$2" "$pr_cache/open"; then
    pr_state=open
    return 0
  fi
  pr_url=$(awk -v tip="$3" -v branch="$2" '$1 == tip && $2 == branch { print $3; exit }' "$pr_cache/merged")
  if [ -n "$pr_url" ]; then
    pr_state=merged
    return 0
  fi
  # A list short of its limit is every open pull request, and with the tip on another branch an older
  # merged one would change nothing.
  if [ "$4" = true ] && [ "$(wc -l < "$pr_cache/open")" -lt 100 ]; then
    pr_state=none
    return 0
  fi

  # Older than the prefetch window: ask about this branch. Budgeted, because a long tail of dead
  # branches would otherwise stall the session start.
  [ "$gh_calls" -lt "$gh_budget" ] || return 0
  gh_calls=$((gh_calls + 1))
  prs=$(cd "$1" && gh pr list --head "$2" --state all --limit 10 --json state,headRefOid,url 2> /dev/null) || return 0
  printf '%s' "$prs" | jq -e 'type == "array"' > /dev/null 2>&1 || return 0
  if printf '%s' "$prs" | jq -e 'any(.[]; .state == "OPEN")' > /dev/null 2>&1; then
    pr_state=open
    return 0
  fi
  pr_url=$(printf '%s' "$prs" | jq -r --arg tip "$3" \
    'map(select(.state == "MERGED" and .headRefOid == $tip)) | first | .url // empty' 2> /dev/null)
  if [ -n "$pr_url" ]; then
    pr_state=merged
  else
    pr_state=none
  fi
}

# child_verdict <child worktree>: sets proof when the child's commit has landed, else reason.
child_verdict() {
  proof=''
  reason=''
  c_repo=$(dirname "$(common_dir "$1")")
  c_branch=$(git -C "$1" symbolic-ref --short -q HEAD 2> /dev/null || true)
  c_tip=$(git -C "$1" rev-parse --verify -q HEAD 2> /dev/null) || {
    reason='no commit checked out'
    return
  }
  c_base=$(main_ref "$c_repo") || {
    reason='no main branch to compare with'
    return
  }
  if git -C "$c_repo" merge-base --is-ancestor "$c_tip" "$c_base" 2> /dev/null; then
    proof="in ${c_base#refs/}"
    return
  fi

  c_ahead=$(git -C "$c_repo" rev-list --count "$c_base..$c_tip" 2> /dev/null || echo '?')
  c_other=$(other_ref "$c_repo" "$c_branch" "$c_tip")
  if [ -z "$c_branch" ]; then
    if [ -n "$c_other" ]; then
      proof="in ${c_other#refs/}"
    else
      reason="$c_ahead commit(s) not landed (detached)"
    fi
    return
  fi

  pr_check "$c_repo" "$c_branch" "$c_tip" "$([ -n "$c_other" ] && echo true || echo false)"
  case $pr_state in
    merged) proof=$pr_url ;;
    open) reason="open PR on $c_branch" ;;
    none)
      if [ -n "$c_other" ]; then
        proof="nothing of its own, in ${c_other#refs/}"
      else
        reason="$c_ahead commit(s) not landed (branch $c_branch)"
      fi
      ;;
    *) reason="$c_ahead commit(s) not landed (branch $c_branch), GitHub not asked" ;;
  esac
}

# verdict <home worktree>: sets keep to the reason the worktree stays, or leaves it empty and sets
# landed. Also sets inside (the children in it), h_branch and newest (its last use).
verdict() {
  keep=''
  landed=''
  inside=''
  for child in $children; do
    [ ! -e "$1/$child/.git" ] || inside="$inside $child"
  done

  admin=$(admin_dir "$1") || {
    keep='not a git worktree'
    return
  }
  if [ -e "$admin/locked" ]; then
    keep='locked by a live session'
    return
  fi
  # The private index is rewritten by work in the worktree: the closest thing to "somebody was here".
  newest=$(mtime "$admin/index" || mtime "$1" || echo 0)
  changed=$(changes_in "$1")
  if [ "$changed" != 0 ]; then
    keep="$changed uncommitted change(s) in home"
    return
  fi

  for child in $inside; do
    admin=$(admin_dir "$1/$child") || {
      keep="$child is not a git worktree"
      return
    }
    if [ -e "$admin/locked" ]; then
      keep="$child locked by a live session"
      return
    fi
    used=$(mtime "$admin/index" || mtime "$1/$child" || echo 0)
    [ "$used" -le "$newest" ] || newest=$used
    changed=$(changes_in "$1/$child")
    if [ "$changed" != 0 ]; then
      keep="$changed uncommitted change(s) in $child"
      return
    fi
  done

  h_branch=$(git -C "$1" symbolic-ref --short -q HEAD 2> /dev/null || true)
  h_tip=$(git -C "$1" rev-parse --verify -q HEAD 2> /dev/null) || {
    keep='no home commit checked out'
    return
  }
  h_proof=''
  if [ -z "$(other_ref "$home" "$h_branch" "$h_tip")" ]; then
    # Home's pull requests are squash-merged too, so the merged one with this tip as its head proves it.
    pr_state=unknown
    [ -z "$h_branch" ] || pr_check "$home" "$h_branch" "$h_tip" false
    case $pr_state in
      merged) h_proof=$pr_url ;;
      open)
        keep="open PR on home branch $h_branch"
        return
        ;;
      none)
        keep="home commits that are on no other branch${h_branch:+ (branch $h_branch)}"
        return
        ;;
      *)
        keep="home commits that are on no other branch${h_branch:+ (branch $h_branch)}, GitHub not asked"
        return
        ;;
    esac
  fi

  for child in $inside; do
    child_verdict "$1/$child"
    if [ -z "$proof" ]; then
      keep="$child: $reason"
      return
    fi
    landed="${landed:+$landed, }$child $proof"
  done
  [ -n "$landed" ] || landed='no child inside'
  [ -z "$h_proof" ] || landed="$landed, home $h_proof"

  if [ "$mode" = prune ] && [ "$newest" -gt "$idle_cutoff" ]; then
    keep="landed but active within ${idle_days}d"
  fi
}

# drop_branch <repository> <branch>: the proof stands in for the ancestor test `git branch -d` would
# apply, which squash merges never pass. The main branch is not a task branch, whatever checked it out.
drop_branch() {
  [ -n "$2" ] || return 1
  base=$(main_ref "$1") && [ "$2" = "${base##*/}" ] && return 1
  git -C "$1" branch -D "$2" > /dev/null 2>&1
}

# retire <home worktree>, after a verdict with nothing to keep: sets gone to what was removed, or
# fails with keep set.
retire() {
  gone=''
  for child in $inside; do
    c_repo=$(dirname "$(common_dir "$1/$child")")
    c_branch=$(git -C "$1/$child" symbolic-ref --short -q HEAD 2> /dev/null || true)
    if ! git -C "$c_repo" worktree remove --force "$1/$child" 2> /dev/null; then
      keep="git refused to remove the $child worktree"
      return 1
    fi
    if drop_branch "$c_repo" "$c_branch"; then
      gone="${gone:+$gone, }$child branch $c_branch"
    fi
  done
  if ! git -C "$home" worktree remove --force "$1" 2> /dev/null; then
    keep='git refused to remove the home worktree'
    return 1
  fi
  if drop_branch "$home" "$h_branch"; then
    gone="${gone:+$gone, }home branch $h_branch"
  fi
}

prune() {
  # A worktree must not delete its siblings from under the sessions that own them.
  [ "$(admin_dir "$here")" = "$home_common" ] || exit 0

  cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2> /dev/null)
  removed=''
  kept=''

  git -C "$home" worktree list --porcelain | sed -n 's/^worktree //p' > "$tmp/worktrees"
  # On its own descriptor: the commands in the loop must not read the list as their input.
  while IFS= read -r wt <&3; do
    [ -d "$wt" ] || continue
    [ "$(admin_dir "$wt")" != "$home_common" ] || continue
    # A worktree made by hand elsewhere is not a task worktree, and not this hook's to remove.
    [ "$(dirname "$wt")" = "$home/.claude/worktrees" ] || continue
    name=$(basename "$wt")

    case "$cwd/" in
      "$wt"/*)
        kept="${kept:+$kept; }$name: this session is in it"
        continue
        ;;
    esac

    verdict "$wt"
    if [ -z "$keep" ] && [ "$report_only" = true ]; then
      keep="prunable, clean, idle and landed ($landed)"
    fi
    if [ -z "$keep" ] && retire "$wt"; then
      removed="${removed:+$removed; }$name${gone:+ ($gone)}"
    else
      kept="${kept:+$kept; }$name: $keep"
    fi
  done 3< "$tmp/worktrees"

  git -C "$home" worktree prune 2> /dev/null
  for child in $children; do
    [ ! -e "$home/$child/.git" ] || git -C "$home/$child" worktree prune 2> /dev/null
  done

  [ -n "$removed$kept" ] || exit 0
  summary=''
  [ -z "$removed" ] || summary="removed $removed"
  [ -z "$kept" ] || summary="${summary:+$summary. }kept: $kept"

  jq -n --arg summary "$summary" --argjson notify "$([ -n "$removed" ] && echo true || echo false)" '
    {
      hookSpecificOutput: {
        hookEventName: "SessionStart",
        additionalContext: ("Task worktree cleanup: " + $summary)
      }
    } + (if $notify then { systemMessage: ("Task worktree cleanup: " + $summary) } else {} end)
  '
}

remove() {
  wt=$(printf '%s' "$input" | jq -r '.worktree_path // empty' 2> /dev/null)
  [ -n "$wt" ] || quit 'no worktree_path in the hook input'
  if [ ! -d "$wt" ]; then
    git -C "$home" worktree prune 2> /dev/null
    exit 0
  fi
  wt=$(cd "$wt" && pwd -P)

  # Only a task worktree of this home: a linked worktree in .claude/worktrees, named by its root.
  [ "$(dirname "$wt")" = "$home/.claude/worktrees" ] &&
    [ "$(git -C "$wt" rev-parse --show-toplevel 2> /dev/null)" = "$wt" ] &&
    [ "$(common_dir "$wt")" = "$home_common" ] &&
    [ "$(admin_dir "$wt")" != "$home_common" ] ||
    quit "not a task worktree of $home: $wt"

  verdict "$wt"
  [ -z "$keep" ] || quit "kept $wt: $keep"
  retire "$wt" || quit "kept $wt: $keep"
  echo "worktree-cleanup: removed $wt${gone:+ ($gone)}" >&2
}

main "$@"
