#!/bin/bash
# generate-token.sh

APP_ID="5895344"
PRIVATE_KEY_PATH="/home/open-terminal/deployment/private-key-gh.pem"
INSTALLATION_ID="185182264"

# Create JWT (requires ruby or python with PyJWT)
JWT=$(python3 - <<EOF
import jwt, time, pathlib

private_key = pathlib.Path("$PRIVATE_KEY_PATH").read_text()
now = int(time.time())
payload = {
    "iat": now - 60,
    "exp": now + (10 * 60),
    "iss": "$APP_ID"
}
print(jwt.encode(payload, private_key, algorithm="RS256"))
EOF
)

echo $JWT

# Exchange JWT for installation token
curl -s -X POST \
  -H "Authorization: Bearer $JWT" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/app/installations/$INSTALLATION_ID/access_tokens" \
  | jq -r .token
