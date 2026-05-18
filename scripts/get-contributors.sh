#!/usr/bin/env bash
# get-contributors.sh — Fetch merged PR authors from kilo-software/kilo-code
# and filter out internal team members.
# Usage: ./get-contributors.sh --days N

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="kilo-software/kilo-code"
TEAM_FILE="${SCRIPT_DIR}/../data/team-members.json"
DAYS=7

while [[ $# -gt 0 ]]; do
  case "$1" in
    --days)
      DAYS="$2"
      shift 2
      ;;
    --repo)
      REPO="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# Load team members to exclude
TEAM_MEMBERS=()
if [[ -f "$TEAM_FILE" ]]; then
  while IFS= read -r member; do
    TEAM_MEMBERS+=("$member")
  done < <(python3 -c "
import json, sys
with open('$TEAM_FILE') as f:
    data = json.load(f)
for m in data.get('team', []):
    print(m)
" 2>/dev/null || true)
fi

echo "Fetching merged PRs from ${REPO} (last ${DAYS} days)..." >&2

# Fetch merged PRs with authors
PR_DATA=$(gh pr list \
  --repo "$REPO" \
  --state merged \
  --limit 500 \
  --json author,mergedAt,url,title \
  --search "merged:>${DAYS} days ago")

if [[ -z "$PR_DATA" || "$PR_DATA" == "[]" ]]; then
  echo "No merged PRs found in the last ${DAYS} days." >&2
  echo "[]"
  exit 0
fi

# Filter out team members and deduplicate
python3 -c "
import json, sys

pr_data = json.loads('''$PR_DATA''')
team = set($(printf '"%s" ' "${TEAM_MEMBERS[@]+"${TEAM_MEMBERS[@]}"}"))

contributors = {}
for pr in pr_data:
    author = pr.get('author', {})
    login = author.get('login', '')
    if not login or login.lower() in {t.lower() for t in team}:
        continue
    if login not in contributors:
        contributors[login] = {
            'username': login,
            'link': f'https://github.com/{login}',
            'pr_count': 0,
            'prs': []
        }
    contributors[login]['pr_count'] += 1
    contributors[login]['prs'].append({
        'title': pr.get('title', ''),
        'url': pr.get('url', ''),
        'mergedAt': pr.get('mergedAt', '')
    })

# Sort by PR count (descending)
result = sorted(contributors.values(), key=lambda x: x['pr_count'], reverse=True)
print(json.dumps(result, indent=2))
"
