# GitHub Repository Users Scripts

This folder contains two Bash scripts to list contributor usernames from GitHub repositories.

## Files

- `get_github_repo_users.sh`: Get users from a public repository.
- `get_github_private_repo_users.sh`: Get users from a private repository.

## Prerequisites

- Bash shell (Git Bash, WSL, or Linux/macOS terminal)
- `curl`
- Optional: `jq` (for better JSON parsing)

## Make Scripts Executable

```bash
chmod +x get_github_repo_users.sh
chmod +x get_github_private_repo_users.sh
```

## 1) Public Repository Script

### Usage

```bash
./get_github_repo_users.sh <owner/repo> [token]
```

### Examples

```bash
./get_github_repo_users.sh torvalds/linux
./get_github_repo_users.sh microsoft/vscode ghp_xxxxxxxxxxxxxxxxxxxx
```

Notes:
- Token is optional for public repos.
- Providing a token increases API rate limits.

## 2) Private Repository Script

### Usage

```bash
./get_github_private_repo_users.sh <owner/repo> [token]
```

### Examples

```bash
./get_github_private_repo_users.sh my-org/my-private-repo ghp_xxxxxxxxxxxx
GITHUB_TOKEN=ghp_xxxxxxxxxxxx ./get_github_private_repo_users.sh my-org/my-private-repo
```

Notes:
- Token is required for private repos.
- Script accepts token from argument 2 or `GITHUB_TOKEN` environment variable.

## How To Generate A GitHub Token

Use a Personal Access Token (PAT).

1. Sign in to GitHub.
2. Open token settings:
   - `https://github.com/settings/tokens`
3. Choose token type:
   - Fine-grained token (recommended)
   - Classic token
4. Click `Generate new token`.
5. Set token name and expiration.
6. Set repository access:
   - Choose only the repositories you need.
7. Set permissions:
   - For private repo read access, grant read permissions for repository contents/metadata.
   - For classic token, `repo` scope is typically required.
8. Generate token and copy it immediately (GitHub shows it once).

## Safer Token Usage

Instead of passing the token directly on the command line, use an environment variable:

```bash
export GITHUB_TOKEN='your_token_here'
./get_github_private_repo_users.sh owner/repo "$GITHUB_TOKEN"
```

## Troubleshooting

- `401/403/404` from private repo script:
  - Token is invalid, expired, missing scope, or has no access to that repo.
- Empty output:
  - Repo has no contributors exposed by the API, or access is insufficient.
- `bash: /bin/bash not found` on Windows PowerShell:
  - Run scripts in Git Bash or WSL instead of plain PowerShell.
