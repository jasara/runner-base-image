# base-developer-image

A general-purpose Ubuntu 24.04 developer container with SSH access and pre-installed tools.

## Included tools

- **Claude Code** — AI coding assistant
- **GitHub CLI** (`gh`) — GitHub from the command line
- **Infisical** — Secrets management
- **jasara-cli** — Jasara CLI
- **PHP 8.5** with Composer and gRPC extension
- **Docker** (Docker-in-Docker capable with `--privileged`)
- **kubectl**, **AWS CLI**
- **tmux**, **git**, **vim**

## Building

Requires a GitHub token with access to the `jasara/jasara-cli` private repo.

```bash
GITHUB_TOKEN=$(gh auth token) docker buildx build \
    --secret id=github_token,env=GITHUB_TOKEN \
    -t base-developer-image:latest \
    .
```

### Build arguments

| ARG | Default | Description |
|-----|---------|-------------|
| `KUBECTL_VERSION` | `1.32.2` | kubectl version |
| `AWSCLI_VERSION` | `2.24.6` | AWS CLI version |
| `GH_VERSION` | `2.87.0` | GitHub CLI version |
| `CLAUDE_VERSION` | `2.1.47` | Claude Code version |

## Running

Use the provided `start.sh` script, which auto-detects credentials from your local environment:

```bash
./start.sh
```

It will:
- Pull `GH_TOKEN` from `gh auth token`
- Pull `CLAUDE_CODE_OAUTH_TOKEN` from the macOS keychain
- Pull `INFISICAL_TOKEN` from `infisical user get token`
- Use `~/.ssh/id_ed25519.pub` (or `id_rsa.pub`) for SSH key auth
- Prompt for any credentials it cannot find

### Manual docker run

```bash
docker run -d \
    --name dev \
    --privileged \
    -p 2222:22 \
    -e SSH_AUTHORIZED_KEY="$(cat ~/.ssh/id_ed25519.pub)" \
    -e GH_TOKEN="$(gh auth token)" \
    -e CLAUDE_CODE_OAUTH_TOKEN="<token>" \
    -e INFISICAL_TOKEN="<token>" \
    base-developer-image:latest
```

### Environment variables

| Variable | Description |
|----------|-------------|
| `SSH_AUTHORIZED_KEY` | Public key added to `~/.ssh/authorized_keys` for the `dev` user |
| `SSH_PASSWORD` | Password for the `dev` user (alternative to key auth) |
| `GH_TOKEN` | GitHub personal access token |
| `CLAUDE_CODE_OAUTH_TOKEN` | Claude Code OAuth token |
| `ANTHROPIC_API_KEY` | Anthropic API key (alternative to OAuth token) |
| `INFISICAL_TOKEN` | Infisical user token |
| `INFISICAL_CLIENT_ID` | Infisical machine identity client ID |
| `INFISICAL_CLIENT_SECRET` | Infisical machine identity client secret |

## Connecting

```bash
ssh dev@localhost -p 2222
```

After connecting, run the setup script to authenticate developer tools:

```bash
dev-setup
```
