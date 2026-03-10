#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./get_github_private_repo_users.sh <owner/repo> [token]

Description:
  Prints GitHub usernames who contributed to a PRIVATE repository.

Arguments:
  owner/repo   Repository in the form "owner/name" (required)
  token        GitHub personal access token (optional if GITHUB_TOKEN is set)

Examples:
  ./get_github_private_repo_users.sh my-org/my-private-repo ghp_xxxxxxxxxxxx
  GITHUB_TOKEN=ghp_xxxxxxxxxxxx ./get_github_private_repo_users.sh my-org/my-private-repo

Required token scopes:
  - Fine-grained token: Read access to "Contents" for the target repo
  - Classic token: repo

Notes:
  - Uses the GitHub contributors API for private repositories.
  - Automatically fetches all pages (100 users per page).
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

repo="$1"
cli_token="${2:-}"
token="${cli_token:-${GITHUB_TOKEN:-}}"

if [[ "$repo" != */* ]]; then
  echo "Error: repo must be in the format owner/repo" >&2
  exit 1
fi

if [[ -z "$token" ]]; then
  echo "Error: token is required for private repositories." >&2
  echo "Pass it as arg #2 or set GITHUB_TOKEN." >&2
  exit 1
fi

base_url="https://api.github.com/repos/${repo}/contributors"
per_page=100
page=1

headers=(
  -H "Accept: application/vnd.github+json"
  -H "Authorization: Bearer ${token}"
  -H "X-GitHub-Api-Version: 2022-11-28"
)

extract_logins() {
  if command -v jq >/dev/null 2>&1; then
    jq -r '.[] | select(.login != null) | .login'
  else
    # Fallback parser when jq is unavailable.
    grep -oE '"login"[[:space:]]*:[[:space:]]*"[^"]+"' | sed -E 's/.*"([^"]+)"$/\1/'
  fi
}

fetch_page() {
  local url="$1"
  local raw body status

  raw="$(curl -sS -L "${headers[@]}" -w $'\n%{http_code}' "$url")"
  status="${raw##*$'\n'}"
  body="${raw%$'\n'*}"

  if [[ "$status" == "401" || "$status" == "403" || "$status" == "404" ]]; then
    echo "Error: GitHub API returned HTTP ${status} for ${repo}" >&2
    echo "Hint: verify token permissions and repository access." >&2
    exit 1
  fi

  if [[ "$status" -lt 200 || "$status" -ge 300 ]]; then
    echo "Error: unexpected HTTP status ${status} from GitHub API." >&2
    exit 1
  fi

  printf '%s' "$body"
}

while :; do
  url="${base_url}?per_page=${per_page}&page=${page}"
  response="$(fetch_page "$url")"

  if [[ "$response" == "[]" ]]; then
    break
  fi

  users="$(printf '%s' "$response" | extract_logins)"
  if [[ -z "$users" ]]; then
    break
  fi

  printf '%s\n' "$users"
  ((page++))
done | awk '!seen[$0]++'
