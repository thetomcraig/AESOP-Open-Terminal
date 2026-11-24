I removed the Docker Compose configuration excerpts and other deployment details that should already be documented in the source files. The guide now focuses on the GitHub setup, authentication flow, Git identity, configuration behavior, and verification steps.

# Open Terminal: GitHub App Integration

This guide documents how to configure GitHub App authentication for Open Terminal and attribute Git commits to the GitHub App bot account.

It is intended as a reference when recreating the integration on another machine.

## 1. Create a GitHub App

In GitHub:

1. Navigate to **Settings → Developer settings → GitHub Apps**.
2. Create a new GitHub App.
3. Configure repository permissions:
   - **Contents:** Read and write
   - **Metadata:** Read-only
4. Restrict installation access to the repositories the terminal needs.
5. Create the app.
6. Generate and download a private key.
7. Install the app on the GitHub account or organization and grant it access to the target repositories.

Record these values:

| Setting         | Description                                      |
| --------------- | ------------------------------------------------ |
| App ID          | Identifies the GitHub App                        |
| App slug        | URL-friendly identifier for the app              |
| Installation ID | Identifies the app installation                  |
| Private key     | PEM private key used to sign authentication JWTs |

## 2. Configure secrets and environment variables

Configure the GitHub App credentials and Open Terminal API key through the deployment's existing secret-management mechanism.

The integration requires:

- GitHub App ID
- GitHub App installation ID
- GitHub App private key
- Open Terminal API key

The private key should be accessible inside the container without being included in the repository or exposed in logs.

## 3. Configure GitHub App authentication

The Git push script (`deployment/git-push-with-app.sh`) handles authentication.

Its workflow is:

1. Read the GitHub App private key.
2. Generate a signed JWT using the App ID.
3. Exchange the JWT for an installation access token through the GitHub API:

   `POST /app/installations/INSTALLATION_ID/access_tokens`
4. Extract the `token` field from the JSON response.
5. Use the installation token to authenticate the Git push.

The push uses the following authentication format:

```
https://x-access-token:TOKEN@github.com/OWNER/REPOSITORY.git
```

The installation token is temporary, so generate a fresh one for each push.

**Important:** The script must output only the token when returning it to the calling shell. Do not print the JWT, private key, or installation token in logs.

## 4. Configure Git commit identity

GitHub distinguishes between the identity used to authenticate a push and the identity recorded on a commit.

- The GitHub App installation token authenticates the push.
- Git's `user.name` and `user.email` determine the commit author and committer.

For GitHub to associate commits with the GitHub App bot account, use this email format:

```
BOT_USER_ID+APP_SLUG[bot]@users.noreply.github.com
```

The numeric prefix must be the **bot user account ID**, not the GitHub App ID.

### Find the bot account ID

Query GitHub's API using the bot login:

```
curl -fsSL 'https://api.github.com/users/APP_SLUG%5Bbot%5D' \
  | python3 -c 'import json,sys; u=json.load(sys.stdin); print(f"Login: {u[\"login\"]}\nID: {u[\"id\"]}\nType: {u[\"type\"]}")'
```

For the current AESOP integration:

| Field       | Value                      |
| ----------- | -------------------------- |
| Login       | `aesop-open-terminal[bot]` |
| Bot user ID | `360448379`                |
| Type        | `Bot`                      |

When recreating this setup, query the API again rather than assuming the ID.

### Configure the Git identity

The global Git configuration should contain:

```
[user]
    name = aesop-open-terminal[bot]
    email = 360448379+aesop-open-terminal[bot]@users.noreply.github.com

[safe]
    directory = /workspace/movie-search
```

Adjust the safe directory to match the repository path inside the container.

The `safe.directory` setting prevents Git's ownership safety checks from blocking operations when the repository is owned by a different user.

## 5. Configure the global Git config location

Open Terminal's setup script may run in an environment where `$HOME` resolves to `/root`, even though the interactive terminal user has a different home directory.

Avoid relying on `$HOME` for this configuration.

Instead:

1. Keep the host-managed Git configuration in the mounted workspace.
2. Copy it into `/workspace/.open-terminal/gitconfig` during Open Terminal startup.
3. Set `GIT_CONFIG_GLOBAL` to `/workspace/.open-terminal/gitconfig`.

This approach avoids requiring an additional volume mount or relying on the container user's home directory.

The startup script should perform the copy before Git operations are needed.

## 6. Remove conflicting repository-level Git identity

Git repository-local configuration takes precedence over global configuration.

If the repository already has a local identity configured, remove it from inside the repository:

```
git config --local --unset user.name
git config --local --unset user.email
```

This allows the global configuration specified by `GIT_CONFIG_GLOBAL` to take effect.

## 7. Verify the configuration

Inside Open Terminal, run:

```
git config --show-origin --get user.name
git config --show-origin --get user.email
```

Expected values:

```
aesop-open-terminal[bot]
360448379+aesop-open-terminal[bot]@users.noreply.github.com
```

Both settings should originate from:

```
/workspace/.open-terminal/gitconfig
```

You can also inspect the actual commit identity:

```
git log -1 --format='%an <%ae>%n%cn <%ce>'
```

Both author and committer should use the GitHub App bot identity.

## 8. Test a push

Create an empty commit to test the configuration without changing project files:

```
git commit --allow-empty -m "Test GitHub App attribution"
```

Push using the GitHub App authentication script:

```
./deployment/git-push-with-app.sh
```

Verify the commit on GitHub.

The commit should be associated with the GitHub App bot account, including its bot avatar.

## 9. Important distinctions

| Component          | Purpose                                         |
| ------------------ | ----------------------------------------------- |
| GitHub App ID      | Identifies the GitHub App                       |
| Installation ID    | Identifies the app installation                 |
| Private key        | Signs the JWT used to authenticate as the app   |
| Installation token | Authenticates Git operations                    |
| Bot user ID        | Used in the commit author email                 |
| `user.name`        | Commit author/committer display name            |
| `user.email`       | Allows GitHub to associate commits with the bot |

**Do not confuse the App ID with the bot user ID.** The App ID is used for authentication; the bot user ID is used in the Git commit email address.

Changing Git's `user.name` to a different friendly name does not necessarily change the name GitHub displays for an account it recognizes as a bot. The bot login remains `aesop-open-terminal[bot]`.

## 10. Security considerations

- Never commit the private key or generated installation tokens.
- Restrict GitHub App repository access to only the repositories it needs.
- Keep the container's capability restrictions and resource limits.
- Use short-lived installation tokens rather than storing permanent GitHub credentials.
- Avoid printing tokens or JWTs in setup logs.

END OF LINE (c5)
