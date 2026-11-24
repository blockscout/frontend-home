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
TAG_OBJECT=4444444444444444444444444444444444444444
TAGGED=5555555555555555555555555555555555555555
LIGHT=6666666666666666666666666666666666666666

# The stub remote: an annotated tag is listed twice, as its tag object and as the commit under `^{}`.
printf '%s\t%s\n' \
  $MAIN refs/heads/main \
  $NEW refs/heads/release \
  $TAG_OBJECT refs/tags/annotated \
  $TAGGED 'refs/tags/annotated^{}' \
  $LIGHT refs/tags/light \
  $MAIN refs/tags/release > "$scratch/remote-refs"

mkdir "$scratch/bin"
cat > "$scratch/bin/pnpm" <<'STUB'
#!/bin/sh
echo "$*" >> "$PNPM_CALLS"
echo 'lockfile of the install' > pnpm-lock.yaml
exit "$PNPM_STATUS"
STUB
cat > "$scratch/bin/git" <<'STUB'
#!/bin/sh
[ "$1 $2" = 'ls-remote https://github.com/blockscout/frontend-home.git' ] || exit 1
shift 2
for ref in "$@"; do
  awk -F '\t' -v ref="$ref" '$2 == ref' "$REMOTE_REFS"
done
STUB
chmod +x "$scratch/bin/pnpm" "$scratch/bin/git"
export PATH="$scratch/bin:$PATH" PNPM_CALLS="$scratch/pnpm-calls" PNPM_STATUS=0 REMOTE_REFS="$scratch/remote-refs"

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
  PNPM_STATUS=0
  rm -rf "$package" "$PNPM_CALLS"
  mkdir "$package"
  echo 'lockfile of the current pin' > "$package/pnpm-lock.yaml"
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

setup 'an annotated tag is resolved to the commit it points at, not to the tag object' $OLD $OLD
run annotated
assert_eq "$status" 0 'exit status'
assert_eq "$(pin_in_package)" $TAGGED 'package.json'
assert_eq "$(pin_in_workspace)" $TAGGED 'pnpm-workspace.yaml'

setup 'a lightweight tag is resolved to its commit' $OLD $OLD
run light
assert_eq "$status" 0 'exit status'
assert_eq "$(pin_in_package)" $LIGHT 'package.json'

setup 'a name that is both a branch and a tag stops before anything is written' $OLD $OLD
run release
assert_eq "$status" 1 'exit status'
assert_contains "$out" 'both a branch and a tag' 'message'
assert_eq "$(pin_in_package)" $OLD 'package.json'
assert_eq "$(pnpm_calls)" '' 'pnpm calls'

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

setup 'pins that have drifted stop the run when package.json already names the target' $NEW $OLD
run $NEW
assert_eq "$status" 1 'exit status'
assert_contains "$out" 'the two pins have drifted' 'message'
assert_eq "$(pin_in_workspace)" $OLD 'pnpm-workspace.yaml'
assert_eq "$(pnpm_calls)" '' 'pnpm calls'

setup 'a failed install puts both pins and the lockfile back' $OLD $OLD
PNPM_STATUS=1
run $NEW
assert_eq "$status" 1 'exit status'
assert_contains "$out" 'pnpm install failed' 'message'
assert_eq "$(pin_in_package)" $OLD 'package.json'
assert_eq "$(pin_in_workspace)" $OLD 'pnpm-workspace.yaml'
assert_eq "$(cat "$package/pnpm-lock.yaml")" 'lockfile of the current pin' 'pnpm-lock.yaml'
assert_eq "$(pnpm_calls)" install 'pnpm calls'

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
