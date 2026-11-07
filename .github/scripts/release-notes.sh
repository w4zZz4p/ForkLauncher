#!/usr/bin/env bash
# Prints release notes for TAG, built from the conventional commit subjects
# since the previous tag. The app shows this text as "What's new".
#
# Usage: release-notes.sh TAG [PREVIOUS_TAG]
set -euo pipefail

tag="$1"
prev="${2:-$(git describe --tags --abbrev=0 "${tag}^" 2>/dev/null || true)}"

echo "ForkLauncher v${tag}"

# First release: there is no earlier tag to compare against.
[ -n "$prev" ] || exit 0

subjects=$(git log --no-merges --format='%s' "${prev}..${tag}")

# Prints "### title" and the matching subjects as a list, without the type prefix.
section() {
  local title="$1" pattern="$2" lines
  lines=$(printf '%s\n' "$subjects" | grep -E "$pattern" \
    | sed -E 's/^[a-z]+(\([^)]*\))?!?:[[:space:]]*//; s/^(.)/- \U\1/' || true)
  [ -n "$lines" ] && printf '\n### %s\n%s\n' "$title" "$lines"
  return 0
}

type_re='^%s(\([^)]*\))?!?:'
section "Features" "$(printf "$type_re" 'feat')"
section "Fixes" "$(printf "$type_re" '(fix|perf)')"
# Everything else a user might notice; CI, tests and formatting are left out.
section "Other changes" "$(printf "$type_re" '(improvement|refactor|docs|chore|build|revert)')"
