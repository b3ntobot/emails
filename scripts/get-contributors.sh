#!/usr/bin/env bash
# get-contributors.sh — Fetch merged PR authors from Kilo-Org/kilocode
# and filter out internal team members.
# Usage: ./get-contributors.sh --days N

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="Kilo-Org/kilocode"
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

TEAM_JSON="[]"
if [[ -f "$TEAM_FILE" ]]; then
  TEAM_JSON=$(python3 - "$TEAM_FILE" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
print(json.dumps(data.get('team', [])))
PY
)
fi

SINCE_DATE=$(python3 - "$DAYS" <<'PY'
from datetime import datetime, timedelta, timezone
import sys
print((datetime.now(timezone.utc) - timedelta(days=int(sys.argv[1]))).date().isoformat())
PY
)

echo "Fetching merged PRs from ${REPO} since ${SINCE_DATE} (last ${DAYS} days)..." >&2

# GitHub search expects an absolute date here; "merged:>7 days ago"
# can return no results even when recent PRs exist.
PR_DATA=$(gh pr list \
  --repo "$REPO" \
  --state merged \
  --limit 500 \
  --json author,mergedAt,url,title \
  --search "merged:>${SINCE_DATE}")

if [[ -z "$PR_DATA" || "$PR_DATA" == "[]" ]]; then
  echo "No merged PRs found since ${SINCE_DATE}." >&2
  echo "[]"
  exit 0
fi

PR_DATA="$PR_DATA" TEAM_JSON="$TEAM_JSON" python3 - <<'PY'
import json
import os

pr_data = json.loads(os.environ.get('PR_DATA', '[]'))
team = {m.lower() for m in json.loads(os.environ.get('TEAM_JSON', '[]'))}

contributors = {}
for pr in pr_data:
    author = pr.get('author') or {}
    login = author.get('login', '')
    login_lower = login.lower()
    if not login or login_lower in team or login_lower.startswith('app/') or author.get('is_bot'):
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

result = sorted(contributors.values(), key=lambda x: (-x['pr_count'], x['username'].lower()))
print(json.dumps(result, indent=2))
PY
