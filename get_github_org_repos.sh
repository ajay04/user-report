#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./get_github_org_repos.sh <org> [token]

Description:
  Prints all repository names for a GitHub organization.

Arguments:
  org         GitHub organization name (required)
  token       Optional GitHub personal access token.
              You can also use GITHUB_TOKEN.

Examples:
  ./get_github_org_repos.sh github
  ./get_github_org_repos.sh my-org ghp_xxxxxxxxxxxx
  GITHUB_TOKEN=ghp_xxxxxxxxxxxx ./get_github_org_repos.sh my-org

Notes:
  - Without a token, only public repositories are returned.
  - With a token and proper access, private org repositories can also be returned.
  - Automatically fetches all pages (100 repos per page).
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit 1
fi

org="$1"
cli_token="${2:-}"
token="${cli_token:-${GITHUB_TOKEN:-}}"

if [[ -z "$org" ]]; then
  echo "Error: org is required" >&2
  exit 1
fi

per_page=100
page=1
base_url="https://api.github.com/orgs/${org}/repos"

headers=(-H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")
if [[ -n "$token" ]]; then
  headers+=( -H "Authorization: Bearer ${token}" )
fi

extract_repo_names() {
  if command -v jq >/dev/null 2>&1; then
    jq -r '.[] | select(.full_name != null) | .full_name'
  else
    # Fallback parser when jq is unavailable.
    grep -oE '"full_name"[[:space:]]*:[[:space:]]*"[^"]+"' | sed -E 's/.*"([^"]+)"$/\1/'
  fi
}

fetch_page() {
  local url="$1"
  local raw body status

  raw="$(curl -sS -L "${headers[@]}" -w $'\n%{http_code}' "$url")"
  status="${raw##*$'\n'}"
  body="${raw%$'\n'*}"

  if [[ "$status" == "404" ]]; then
    echo "Error: organization '${org}' not found or no access." >&2
    exit 1
  fi

  if [[ "$status" == "401" || "$status" == "403" ]]; then
    echo "Error: GitHub API returned HTTP ${status}." >&2
    echo "Hint: verify token validity, scopes, and org permissions." >&2
    exit 1
  fi

  if [[ "$status" -lt 200 || "$status" -ge 300 ]]; then
    echo "Error: unexpected HTTP status ${status} from GitHub API." >&2
    exit 1
  fi

  printf '%s' "$body"
}

while :; do
  # type=all includes public and private repos visible to the token.
  url="${base_url}?type=all&per_page=${per_page}&page=${page}"
  response="$(fetch_page "$url")"

  if [[ "$response" == "[]" ]]; then
    break
  fi

  repos="$(printf '%s' "$response" | extract_repo_names)"
  if [[ -z "$repos" ]]; then
    break
  fi

  printf '%s\n' "$repos"
  ((page++))
done | awk '!seen[$0]++'
