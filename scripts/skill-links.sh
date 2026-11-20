#!/bin/sh

# Links every child's skills into home's skills directory, so a session started in home lists them from
# its first turn: .agents/skills/<skill> -> ../../<child>/.agents/skills/<skill>. The links are committed.
# A skill home has as a real directory gets no link, and home's copy is the one that loads.
#
#   scripts/skill-links.sh           writes the links: adds the missing, repoints the wrong, removes the stale
#   scripts/skill-links.sh --check   changes nothing, and fails naming each entry that is wrong
#
# Both compare against the child checkouts that are present, so they need every child cloned.

set -eu

case "${1:-}" in
  '') check=0 ;;
  --check) check=1 ;;
  *) echo "usage: $0 [--check]" >&2; exit 2 ;;
esac

root=$(cd "$(dirname "$0")/.." && pwd)
skills="$root/.agents/skills"
children=$("$root/scripts/children.sh")
status=0
changed=0

fail() {
  echo "$1" >&2
  status=1
}

# The links there should be, as `<skill> <target>` lines.
expected=''
for child in $(printf '%s\n' "$children" | cut -d ' ' -f 1); do
  if [ ! -e "$root/$child/.git" ]; then
    echo "$child: not cloned here, so its skills cannot be read; run scripts/bootstrap.sh" >&2
    exit 1
  fi
  for file in "$root/$child/.agents/skills"/*/SKILL.md; do
    [ -f "$file" ] || continue
    skill=$(basename "$(dirname "$file")")
    # Home owns the name.
    [ -d "$skills/$skill" ] && [ ! -L "$skills/$skill" ] && continue
    target="../../$child/.agents/skills/$skill"
    other=$(printf '%s' "$expected" | awk -v skill="$skill" '$1 == skill { print $2 }')
    if [ -n "$other" ]; then
      fail "$skill: two children have this skill ($other and $target), and one name links to one of them"
      continue
    fi
    expected="$expected$skill $target
"
  done
done

# Every expected link is there and points at its child's skill.
while read -r skill target; do
  [ -n "$skill" ] || continue
  link="$skills/$skill"
  if [ -L "$link" ]; then
    actual=$(readlink "$link")
    [ "$actual" = "$target" ] && continue
    problem="$skill: the link points to $actual, expected $target"
  elif [ -e "$link" ]; then
    fail "$skill: .agents/skills/$skill is in the way of the link to $target"
    continue
  else
    problem="$skill: no link for the child skill, expected .agents/skills/$skill -> $target"
  fi
  if [ "$check" -eq 1 ]; then
    fail "$problem"
  else
    rm -f "$link"
    ln -s "$target" "$link"
    echo "$skill: linked to $target"
    changed=1
  fi
done <<EOF_EXPECTED
$expected
EOF_EXPECTED

# No other link is there.
for link in "$skills"/*; do
  [ -L "$link" ] || continue
  skill=$(basename "$link")
  printf '%s' "$expected" | awk -v skill="$skill" '$1 == skill { found = 1 } END { exit !found }' && continue
  actual=$(readlink "$link")
  if [ ! -e "$link" ]; then
    problem="$skill: the link has no target ($actual)"
  else
    problem="$skill: the link points to $actual, which is not a child's skill"
  fi
  if [ "$check" -eq 1 ]; then
    fail "$problem"
  else
    rm "$link"
    echo "$skill: link removed ($actual)"
    changed=1
  fi
done

[ "$status" -eq 0 ] || exit "$status"
if [ "$check" -eq 1 ]; then
  echo "skill links: .agents/skills matches the children's skills"
elif [ "$changed" -eq 0 ]; then
  echo "skill links: nothing to change"
fi
