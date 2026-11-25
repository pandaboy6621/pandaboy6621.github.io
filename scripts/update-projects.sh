#!/usr/bin/env bash
# Refresh data/projects.json from GitHub: public, non-fork repos, newest first.
# Runs in CI before every build; can also be run locally (needs gh + jq).
set -euo pipefail
USER_NAME="${1:-pandaboy6621}"
EXCLUDE="${USER_NAME}.github.io"
OUT="$(cd "$(dirname "$0")/.." && pwd)/data/projects.json"
TMP="$(mktemp)"
gh api "users/${USER_NAME}/repos?per_page=100&type=owner&sort=pushed" --jq "
  [ .[] | select(.fork | not) | select(.archived | not) | select(.private | not)
        | select(.name != \"${EXCLUDE}\")
        | { name, description, url: .html_url, homepage, language,
            stars: .stargazers_count, forks: .forks_count, topics, pushed: .pushed_at } ]
" > "$TMP"
jq -e 'type == "array"' "$TMP" >/dev/null
mv "$TMP" "$OUT"
echo "Wrote $(jq length "$OUT") projects"
