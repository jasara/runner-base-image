# base-developer-image

A general-purpose Ubuntu 24.04 developer container with SSH access, pre-installed tools (PHP, PostgreSQL, Docker, kubectl, AWS CLI, GitHub CLI, Claude Code, and more), and scripts for quickly spinning up coding sessions.

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

## Starting the container

```bash
./start.sh
```

This will:
- Pull credentials from your local environment (GitHub CLI, Anthropic keychain, Infisical)
- Load any SSH public keys from `.ssh_keys` in this directory
- Stop and remove any existing container with the same name
- Start the container and expose SSH on port 2222 (configurable via `SSH_PORT`)
- Copy `work.sh` into the container
- Start an ngrok TCP tunnel and print the host/port for remote access

### Prerequisites

- [ngrok](https://ngrok.com) installed and authenticated: `brew install ngrok/ngrok/ngrok && ngrok config add-authtoken <your-token>`

### SSH access

**Locally:**
```bash
ssh dev@localhost -p 2222
```

**Remotely (e.g. Termius on Android):**

After `start.sh` runs, it prints the ngrok tunnel address:
```
Termius connection:
  Host: 0.tcp.ngrok.io
  Port: <port>
  User: dev
```

After connecting, run the setup script to authenticate developer tools:

```bash
dev-setup
```

### SSH key setup

Add public keys to `.ssh_keys` (one per line) to authorize them in the container. This file is gitignored. Your local `~/.ssh/id_ed25519.pub` or `~/.ssh/id_rsa.pub` is also loaded automatically.

## Starting a coding session (`work.sh`)

Once inside the container, use `work.sh` to spin up a Claude coding session for a GitHub repo:

```bash
work.sh <org/repo> "<task description>"
```

**Example:**
```bash
work.sh jasara/conveyr "Debug Sentry issue XYZ"
```

This will:
1. Clone the repo into `~/Repositories/<repo>` if not already there
2. Generate a short kebab-case branch identifier from the task description using Claude (haiku model)
3. Create a git worktree at `~/worktrees/<repo>/<identifier>` branched from the remote default branch
4. Open a tmux session named after the identifier
5. Start `claude` in the worktree directory with the task description as the initial message

If the tmux session already exists, it re-attaches to it.

## Environment variables

| Variable | Description |
|---|---|
| `CONTAINER_NAME` | Container name (default: `dev`) |
| `IMAGE` | Docker image to use (default: `base-developer-image:latest`) |
| `SSH_PORT` | Host port to map SSH to (default: `2222`) |
| `GH_TOKEN` | GitHub token (auto-detected from `gh` CLI) |
| `ANTHROPIC_API_KEY` | Anthropic API key (alternative to OAuth token) |
| `CLAUDE_CODE_OAUTH_TOKEN` | Claude Code OAuth token (auto-detected from keychain) |
| `INFISICAL_TOKEN` | Infisical user token (auto-detected from `infisical` CLI) |
| `INFISICAL_CLIENT_ID` / `INFISICAL_CLIENT_SECRET` | Infisical machine identity credentials |
| `SSH_AUTHORIZED_KEY` | SSH public key to authorize (auto-detected from `~/.ssh/`) |
| `SSH_PASSWORD` | Password for the `dev` user (fallback if no SSH key found) |
