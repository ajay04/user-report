#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./get_github_owner_repos.sh <owner> [token]

Description:
  Prints repositories owned by a GitHub user account.

Arguments:
  owner       GitHub username/owner (required)
  token       Optional GitHub personal access token.
              You can also use GITHUB_TOKEN.

Examples:
  ./get_github_owner_repos.sh octocat
  ./get_github_owner_repos.sh my-user ghp_xxxxxxxxxxxx
  GITHUB_TOKEN=ghp_xxxxxxxxxxxx ./get_github_owner_repos.sh my-user

Notes:
  - Without a token, only public repositories are returned.
  - With a token, private repos are returned only if token owner is the same user.
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

owner="$1"
cli_token="${2:-}"
token="${cli_token:-${GITHUB_TOKEN:-}}"

if [[ -z "$owner" ]]; then
  echo "Error: owner is required" >&2
  exit 1
fi

per_page=100
page=1

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

get_auth_login() {
  local raw body status
  raw="$(curl -sS -L "${headers[@]}" -w $'\n%{http_code}' "https://api.github.com/user")"
  status="${raw##*$'\n'}"
  body="${raw%$'\n'*}"

  if [[ "$status" -lt 200 || "$status" -ge 300 ]]; then
    return 1
  fi

  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$body" | jq -r '.login // empty'
  else
    printf '%s' "$body" | grep -oE '"login"[[:space:]]*:[[:space:]]*"[^"]+"' | head -n 1 | sed -E 's/.*"([^"]+)"$/\1/'
  fi
}

fetch_page() {
  local url="$1"
  local raw body status

  raw="$(curl -sS -L "${headers[@]}" -w $'\n%{http_code}' "$url")"
  status="${raw##*$'\n'}"
  body="${raw%$'\n'*}"

  if [[ "$status" == "404" ]]; then
    echo "Error: owner '${owner}' not found or no access." >&2
    exit 1
  fi

  if [[ "$status" == "401" || "$status" == "403" ]]; then
    echo "Error: GitHub API returned HTTP ${status}." >&2
    echo "Hint: verify token validity and permissions." >&2
    exit 1
  fi

  if [[ "$status" -lt 200 || "$status" -ge 300 ]]; then
    echo "Error: unexpected HTTP status ${status} from GitHub API." >&2
    exit 1
  fi

  printf '%s' "$body"
}

# Default endpoint returns public repos for any user.
base_url="https://api.github.com/users/${owner}/repos"
query_prefix="type=owner"

if [[ -n "$token" ]]; then
  auth_login="$(get_auth_login || true)"
  if [[ -n "$auth_login" && "$auth_login" == "$owner" ]]; then
    # If token belongs to the same owner, include private repos too.
    base_url="https://api.github.com/user/repos"
    query_prefix="affiliation=owner&visibility=all"
  fi
fi

while :; do
  url="${base_url}?${query_prefix}&per_page=${per_page}&page=${page}"
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
