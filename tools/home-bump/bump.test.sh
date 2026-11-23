#!/bin/sh

# Runs bump.sh against a scratch consumer package. `pnpm` and `git` are stubs on PATH, so no case installs
# anything or reaches the network.

set -eu

script=$(cd "$(dirname "$0")" && pwd -P)/bump.sh
scratch=$(mktemp -d)
scratch=$(cd "$scratch" && pwd -P)
trap 'rm -rf "$scratch"' EXIT

OLD=1111111111111111111111111111111111111111
NEW=2222222222222222222222222222222222222222
MAIN=3333333333333333333333333333333333333333

mkdir "$scratch/bin"
cat > "$scratch/bin/pnpm" <<'STUB'
#!/bin/sh
echo "$*" >> "$PNPM_CALLS"
STUB
cat > "$scratch/bin/git" <<'STUB'
#!/bin/sh
[ "$1 $2" = 'ls-remote https://github.com/blockscout/frontend-home.git' ] || exit 1
[ "$3" = main ] && printf '%s\trefs/heads/main\n' "$MAIN_SHA"
exit 0
STUB
chmod +x "$scratch/bin/pnpm" "$scratch/bin/git"
export PATH="$scratch/bin:$PATH" PNPM_CALLS="$scratch/pnpm-calls" MAIN_SHA=$MAIN

failures=0
current=''

fail() {
  failures=$((failures + 1))
  printf 'FAIL  %s: %s\n' "$current" "$1"
}

assert_eq() {
  [ "$1" = "$2" ] || fail "$3: expected '$2', got '$1'"
}

assert_contains() {
  case $1 in
    *"$2"*) ;;
    *) fail "$3: expected '$2' in '$1'" ;;
  esac
}

# setup <case name> <commit in package.json> <commit in pnpm-workspace.yaml>
setup() {
  current=$1
  package="$scratch/package"
  rm -rf "$package" "$PNPM_CALLS"
  mkdir "$package"
  cat > "$package/package.json" <<JSON
{
  "devDependencies": {
    "cspell": "9.8.0",
    "frontend-home": "github:blockscout/frontend-home#$2"
  }
}
JSON
  cat > "$package/pnpm-workspace.yaml" <<YAML
allowBuilds:
  esbuild: false
  'frontend-home@https://codeload.github.com/blockscout/frontend-home/tar.gz/$3': true
YAML
}

# run [<commit-or-ref>]: the output lands in $out and the exit status in $status.
run() {
  status=0
  out=$(cd "$package" && "$script" "$@" 2>&1) || status=$?
}

pin_in_package() {
  sed -n 's|.*"github:blockscout/frontend-home#\([0-9a-f]*\)".*|\1|p' "$package/package.json"
}

pin_in_workspace() {
  sed -n 's|.*frontend-home/tar.gz/\([0-9a-f]*\).*|\1|p' "$package/pnpm-workspace.yaml"
}

pnpm_calls() {
  cat "$PNPM_CALLS" 2>/dev/null || true
}

setup 'a full sha moves both pins and reinstalls' $OLD $OLD
run $NEW
assert_eq "$status" 0 'exit status'
assert_eq "$(pin_in_package)" $NEW 'package.json'
assert_eq "$(pin_in_workspace)" $NEW 'pnpm-workspace.yaml'
assert_eq "$(pnpm_calls)" install 'pnpm calls'
assert_contains "$(cat "$package/package.json")" '"cspell": "9.8.0"' 'the rest of package.json is kept'
assert_contains "$(cat "$package/pnpm-workspace.yaml")" 'esbuild: false' 'the rest of pnpm-workspace.yaml is kept'

setup 'a ref is resolved to its commit, and the commit is what gets written' $OLD $OLD
run main
assert_eq "$status" 0 'exit status'
assert_eq "$(pin_in_package)" $MAIN 'package.json'
assert_eq "$(pin_in_workspace)" $MAIN 'pnpm-workspace.yaml'

setup 'no argument means the main branch' $OLD $OLD
run
assert_eq "$status" 0 'exit status'
assert_eq "$(pin_in_package)" $MAIN 'package.json'

setup 'an unknown ref stops before anything is written' $OLD $OLD
run no-such-branch
assert_eq "$status" 1 'exit status'
assert_contains "$out" 'neither a full commit sha nor a branch or tag' 'message'
assert_eq "$(pin_in_package)" $OLD 'package.json'
assert_eq "$(pnpm_calls)" '' 'pnpm calls'

setup 'the current commit is left alone, with no install' $OLD $OLD
run $OLD
assert_eq "$status" 0 'exit status'
assert_contains "$out" 'already pinned' 'message'
assert_eq "$(pnpm_calls)" '' 'pnpm calls'

setup 'pins that have drifted stop the run before anything is written' $OLD $MAIN
run $NEW
assert_eq "$status" 1 'exit status'
assert_contains "$out" 'the two pins have drifted' 'message'
assert_eq "$(pin_in_package)" $OLD 'package.json'
assert_eq "$(pin_in_workspace)" $MAIN 'pnpm-workspace.yaml'
assert_eq "$(pnpm_calls)" '' 'pnpm calls'

setup 'a package without the home dependency is refused' $OLD $OLD
printf '{ "devDependencies": {} }\n' > "$package/package.json"
run $NEW
assert_eq "$status" 1 'exit status'
assert_contains "$out" 'no github:blockscout/frontend-home#<sha> dependency' 'message'

setup 'a directory that is not a package root is refused' $OLD $OLD
rm "$package/pnpm-workspace.yaml"
run $NEW
assert_eq "$status" 1 'exit status'
assert_contains "$out" 'run this from the package root' 'message'
assert_eq "$(pin_in_package)" $OLD 'package.json'

if [ "$failures" -gt 0 ]; then
  printf '\n%s failed\n' "$failures"
  exit 1
fi
echo 'home-bump: all cases pass'
