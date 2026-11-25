#!/bin/bash
# deployment/git-push-with-app.sh
# Usage: ./git-push-with-app.sh <branch_name> <repo_name>
# Example: ./git-push-with-app.sh main aesop-bot/my-repo

set -e

# Configuration (Update these values or export them as environment variables)
APP_ID="5895344"

# Inside the AESOP container, secrets are mounted at /run/secrets/
PRIVATE_KEY_PATH="/run/secrets/github_app_private_key"

# Validate arguments
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <branch_name> <repo_name>" >&2
    exit 1
fi

BRANCH_NAME="$1"
REPO_NAME="$2"

# Generate JWT using Python (PyJWT)
# Note: We do not echo the JWT or Token to stdout for security compliance [1]
TOKEN=$(python3 - <<EOF
import jwt, time, pathlib, subprocess, json, sys

private_key = pathlib.Path("$PRIVATE_KEY_PATH").read_text()
now = int(time.time())

payload = {
    "iat": now - 60,
    "exp": now + (10 * 60),
    "iss": "$APP_ID"
}

jwt_token = jwt.encode(payload, private_key, algorithm="RS256")

result = subprocess.run(
    [
        "curl", "-sS", "-X", "POST",
        "-H", f"Authorization: Bearer {jwt_token}",
        "-H", "Accept: application/vnd.github+json",
        "-H", "X-GitHub-Api-Version: 2022-11-28",
        "https://api.github.com/app/installations/185182264/access_tokens"
    ],
    capture_output=True,
    text=True
)

if result.returncode != 0:
    print(f"Curl failed: {result.stderr}", file=sys.stderr)
    sys.exit(1)

try:
    response = json.loads(result.stdout)
    installation_token = response["token"]
except (json.JSONDecodeError, KeyError):
    print(f"GitHub API error: {result.stdout}", file=sys.stderr)
    sys.exit(1)

print(installation_token)
EOF
)

# Execute git push with token embedded in URL
# This avoids exposing the token in shell history or logs [2]
git push https://x-access-token:${TOKEN}@github.com/${REPO_NAME}.git ${BRANCH_NAME}
