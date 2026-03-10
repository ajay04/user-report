#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./get_github_owner_repos_with_users.sh <owner> [token]

Description:
  Fetch all repositories for a GitHub owner/user account and print contributor users per repo.

Output:
  <repo_full_name>\t<username>

Arguments:
  owner       GitHub username/owner (required)
  token       Optional GitHub personal access token.
              You can also use GITHUB_TOKEN.

Examples:
  ./get_github_owner_repos_with_users.sh octocat
  ./get_github_owner_repos_with_users.sh my-user ghp_xxxxxxxxxxxx
  GITHUB_TOKEN=ghp_xxxxxxxxxxxx ./get_github_owner_repos_with_users.sh my-user

Notes:
  - Without a token, only public owner repositories are returned.
  - Private repositories are included only when token belongs to the same owner.
  - Contributors endpoint is used per repository.
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

public_headers=(-H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")
auth_headers=("${public_headers[@]}")
if [[ -n "$token" ]]; then
  auth_headers+=( -H "Authorization: Bearer ${token}" )
fi

token_warning_shown=0
LAST_STATUS=""
LAST_BODY=""

json_to_repos() {
  if command -v jq >/dev/null 2>&1; then
    jq -r '.[] | select(.full_name != null) | .full_name'
  else
    grep -oE '"full_name"[[:space:]]*:[[:space:]]*"[^"]+"' | sed -E 's/.*"([^"]+)"$/\1/'
  fi
}

json_to_users() {
  if command -v jq >/dev/null 2>&1; then
    jq -r '.[] | select(.login != null) | .login'
  else
    grep -oE '"login"[[:space:]]*:[[:space:]]*"[^"]+"' | sed -E 's/.*"([^"]+)"$/\1/'
  fi
}

warn_invalid_token_once() {
  [[ "$token_warning_shown" -eq 1 ]] && return 0
  token_warning_shown=1

  echo "Warning: provided token was rejected (HTTP 401). Falling back to public API access." >&2
  if [[ "$token" == ghp_github_pat_* ]]; then
    echo "Hint: token format looks wrong. Use the token exactly as copied (often starts with 'github_pat_')." >&2
  fi
}

request_api() {
  local url="$1"
  local mode="$2"
  local raw

  if [[ "$mode" == "auth" ]]; then
    raw="$(curl -sS -L "${auth_headers[@]}" -w $'\n%{http_code}' "$url")"
  else
    raw="$(curl -sS -L "${public_headers[@]}" -w $'\n%{http_code}' "$url")"
  fi

  LAST_STATUS="${raw##*$'\n'}"
  LAST_BODY="${raw%$'\n'*}"
}

api_get() {
  local url="$1"
  local allow_public_fallback="${2:-true}"

  if [[ -n "$token" ]]; then
    request_api "$url" "auth"

    if [[ "$LAST_STATUS" == "401" && "$allow_public_fallback" == "true" ]]; then
      warn_invalid_token_once
      request_api "$url" "public"
    fi
  else
    request_api "$url" "public"
  fi

  if [[ "$LAST_STATUS" == "401" || "$LAST_STATUS" == "403" ]]; then
    if [[ "$allow_public_fallback" == "false" ]]; then
      return 1
    fi
    echo "Error: GitHub API returned HTTP ${LAST_STATUS}. Check token and permissions." >&2
    exit 1
  fi

  if [[ "$LAST_STATUS" == "404" ]]; then
    echo "Error: resource not found: $url" >&2
    exit 1
  fi

  if [[ "$LAST_STATUS" -lt 200 || "$LAST_STATUS" -ge 300 ]]; then
    echo "Error: unexpected HTTP status ${LAST_STATUS} for $url" >&2
    exit 1
  fi

  printf '%s' "$LAST_BODY"
}

get_auth_login() {
  [[ -z "$token" ]] && return 1

  local body
  body="$(api_get "https://api.github.com/user" false)" || return 1

  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$body" | jq -r '.login // empty'
  else
    printf '%s' "$body" | grep -oE '"login"[[:space:]]*:[[:space:]]*"[^"]+"' | head -n 1 | sed -E 's/.*"([^"]+)"$/\1/'
  fi
}

list_owner_repos() {
  local page=1
  local base_url query auth_login response repos

  base_url="https://api.github.com/users/${owner}/repos"
  query="type=owner"

  if [[ -n "$token" ]]; then
    auth_login="$(get_auth_login || true)"
    if [[ -n "$auth_login" && "$auth_login" == "$owner" ]]; then
      base_url="https://api.github.com/user/repos"
      query="affiliation=owner&visibility=all"
    fi
  fi

  while :; do
    response="$(api_get "${base_url}?${query}&per_page=${per_page}&page=${page}")"
    [[ "$response" == "[]" ]] && break

    repos="$(printf '%s' "$response" | json_to_repos)"
    [[ -z "$repos" ]] && break

    printf '%s\n' "$repos"
    ((page++))
  done | awk '!seen[$0]++'
}

list_repo_users() {
  local repo="$1"
  local page=1
  local response users

  while :; do
    response="$(api_get "https://api.github.com/repos/${repo}/contributors?per_page=${per_page}&page=${page}")"
    [[ "$response" == "[]" ]] && break

    users="$(printf '%s' "$response" | json_to_users)"
    [[ -z "$users" ]] && break

    while IFS= read -r user; do
      [[ -n "$user" ]] && printf '%s\t%s\n' "$repo" "$user"
    done <<< "$users"

    ((page++))
  done
}

repos="$(list_owner_repos)"
if [[ -z "$repos" ]]; then
  echo "No repositories found for owner '${owner}'." >&2
  exit 0
fi

while IFS= read -r repo; do
  [[ -n "$repo" ]] && list_repo_users "$repo"
done <<< "$repos" | awk '!seen[$0]++'
