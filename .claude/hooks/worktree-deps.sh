#!/usr/bin/env bash
# Install node_modules on demand inside a task worktree: in the home worktree and in every child
# worktree inside it. `frontend` has its own copy of this hook for sessions started inside it; this is
# that hook with one change, the set of checkouts it looks at.
#
# A worktree is a bare `git checkout`: gitignored paths like node_modules are never
# carried over, so anything that shells out to the local toolchain fails there. Copying
# node_modules is not an option — pnpm's layout is mostly symlinks into .pnpm, and Claude
# Code's .worktreeinclude copier skips symlinks, so the result would be a broken tree. A
# real `pnpm install` is cheap instead: the global store is content-addressed and linked
# into place (cloned on APFS), so a second worktree shares blocks rather than duplicating
# them.
#
# Installing is deferred to the first command that actually needs deps, so read-only
# sessions (review, explore, research) never pay for it. The command is not parsed for the
# checkout it aims at: a session sits at the task worktree's root and reaches a child with
# `cd`, `pnpm -C` or a path, so the first such command installs wherever deps are missing.
#
# Modes:
#   session-start  announce missing deps, install nothing
#   pre-bash       install before a command that needs deps, block if the install fails

set -uo pipefail

# A hook can inherit git's own variables, and they would aim every `git -C` below at one repository.
# shellcheck disable=SC2046
unset $(git rev-parse --local-env-vars)

mode="${1:-}"
payload="$(cat)"

field() { printf '%s' "$payload" | jq -r "$1" 2>/dev/null; }

dir="$(field '.cwd // empty')"
[ -n "$dir" ] && [ -d "$dir" ] || dir="$PWD"

here="$(cd "$(dirname "$0")/../.." && pwd -P)"
home_common="$(git -C "$here" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || exit 0

# Linked worktrees have their own gitdir under the shared common dir; the main checkout
# has the two paths identical. Detecting it this way rather than by matching
# .claude/worktrees/ also covers worktrees created by hand elsewhere.
needs_deps() {
  local root="$1" gitdir common
  gitdir="$(git -C "$root" rev-parse --absolute-git-dir 2>/dev/null)" || return 1
  common="$(git -C "$root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  [ "$gitdir" != "$common" ] || return 1
  [ -f "$root/pnpm-lock.yaml" ] || return 1
  # .modules.yaml rather than the directory, so a half-written install still gets repaired.
  [ ! -f "$root/node_modules/.modules.yaml" ]
}

# The home checkout the command runs in. The directory can be anywhere inside it, a child
# included, so climb out of every repository that is not home.
home_root=""
probe="$dir"
while top="$(git -C "$probe" rev-parse --show-toplevel 2>/dev/null)" && [ -n "$top" ]; do
  if [ "$(git -C "$top" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" = "$home_common" ]; then
    home_root="$top"
    break
  fi
  probe="$(dirname "$top")"
done
[ -n "$home_root" ] || exit 0

roots=()
needs_deps "$home_root" && roots+=("$home_root")
while read -r child _; do
  [ -n "$child" ] && [ -e "$home_root/$child/.git" ] || continue
  needs_deps "$home_root/$child" && roots+=("$home_root/$child")
done < <("$here/scripts/children.sh" 2>/dev/null)
[ "${#roots[@]}" -gt 0 ] || exit 0

if [ "$mode" = "session-start" ]; then
  jq -n --arg roots "$(printf '%s\n' "${roots[@]}")" '{
    hookSpecificOutput: {
      hookEventName: "SessionStart",
      additionalContext: ("These checkouts of this task worktree have no node_modules:\n" + $roots + "\nA PreToolUse hook runs `pnpm install --frozen-lockfile` in each of them automatically before the first Bash command that needs the local toolchain (pnpm/npx/eslint/tsc/vitest/playwright/next, or a `git commit`/`git push` that runs husky hooks), so do not install by hand. Expect that one command to take an extra minute.")
    }
  }'
  exit 0
fi

[ "$mode" = "pre-bash" ] || exit 0

cmd="$(field '.tool_input.command // empty')"
[ -n "$cmd" ] || exit 0

# `git commit`/`git push` are here because the husky pre-commit and pre-push hooks shell
# into node_modules (lint-staged, eslint, tsc); without deps they fail and tempt a
# --no-verify bypass. `[^;&|]*` lets global flags like `git -C dir commit` still match.
needs='(^|[;&|(]|&&|\|\|)[[:space:]]*(pnpm|npx|next|eslint|tsc|vitest|playwright)[[:space:]]|node_modules/\.bin/|(^|[;&|(]|&&|\|\|)[[:space:]]*git[[:space:]][^;&|]*(commit|push)([[:space:]]|$)'
# Dependency-management subcommands run fine without node_modules, and skipping them
# keeps the hook from recursing into the install it is about to perform.
selfmanaged='pnpm[[:space:]]+(install|i|add|remove|rm|up|update|dlx|store|why|licenses|approve-builds|rebuild)([[:space:]]|$)'

printf '%s' "$cmd" | grep -Eq "$needs" || exit 0
printf '%s' "$cmd" | grep -Eq "$selfmanaged" && exit 0

pnpm_bin="$(command -v pnpm 2>/dev/null)"
if [ -z "$pnpm_bin" ]; then
  # Hooks do not always inherit a login shell's PATH, so try the usual install roots.
  for candidate in "$HOME/Library/pnpm/pnpm" "$HOME/.local/share/pnpm/pnpm" \
                   $(ls -t "$HOME"/.nvm/versions/node/*/bin/pnpm 2>/dev/null); do
    [ -x "$candidate" ] && pnpm_bin="$candidate" && break
  done
fi
if [ -z "$pnpm_bin" ]; then
  echo "Cannot install worktree deps: pnpm is not on PATH for hooks. Install manually in: ${roots[*]}" >&2
  exit 2
fi

log="$(mktemp)"
for root in "${roots[@]}"; do
  if ! (cd "$root" && "$pnpm_bin" install --frozen-lockfile --prefer-offline >"$log" 2>&1); then
    tail -20 "$log" >&2
    rm -f "$log"
    echo "pnpm install --frozen-lockfile failed in $root, so this command would fail on missing deps. Fix the install first." >&2
    exit 2
  fi
done
rm -f "$log"

jq -n --arg roots "${roots[*]}" '{ systemMessage: ("Installed node_modules in " + $roots) }'
exit 0
