#!/bin/bash
set -e

CONTAINER_NAME="${CONTAINER_NAME:-dev}"
IMAGE="${IMAGE:-base-developer-image:latest}"
SSH_PORT="${SSH_PORT:-2222}"

prompt_secret() {
    local var_name="$1"
    local description="$2"
    local value
    read -rsp "  Enter ${description} (or press Enter to skip): " value
    echo
    echo "$value"
}

# Gather credentials from local environment/CLIs
GH_TOKEN="${GH_TOKEN:-$(gh auth token 2>/dev/null || true)}"
if [ -z "$GH_TOKEN" ]; then
    echo "GH_TOKEN: not found via 'gh auth token'"
    GH_TOKEN="$(prompt_secret GH_TOKEN "GitHub token")"
fi

CLAUDE_CODE_OAUTH_TOKEN="${CLAUDE_CODE_OAUTH_TOKEN:-$(
    security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('claudeAiOauth',{}).get('accessToken',''))" 2>/dev/null \
    || true
)}"
if [ -z "$CLAUDE_CODE_OAUTH_TOKEN" ] && [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "Claude credentials: not found in keychain"
    ANTHROPIC_API_KEY="$(prompt_secret ANTHROPIC_API_KEY "Anthropic API key (or set CLAUDE_CODE_OAUTH_TOKEN)")"
fi

INFISICAL_TOKEN="${INFISICAL_TOKEN:-$(infisical user get token --silent 2>/dev/null | grep '^Token:' | awk '{print $2}' || true)}"
if [ -z "$INFISICAL_TOKEN" ] && [ -z "$INFISICAL_CLIENT_ID" ]; then
    echo "Infisical credentials: not found via 'infisical user get token'"
    INFISICAL_CLIENT_ID="$(prompt_secret INFISICAL_CLIENT_ID "Infisical client ID")"
    if [ -n "$INFISICAL_CLIENT_ID" ]; then
        INFISICAL_CLIENT_SECRET="$(prompt_secret INFISICAL_CLIENT_SECRET "Infisical client secret")"
    fi
fi

# SSH auth — prefer authorized key, fall back to password
SSH_AUTHORIZED_KEY="${SSH_AUTHORIZED_KEY:-$(cat ~/.ssh/id_ed25519.pub 2>/dev/null || cat ~/.ssh/id_rsa.pub 2>/dev/null || true)}"
if [ -z "$SSH_AUTHORIZED_KEY" ] && [ -z "$SSH_PASSWORD" ]; then
    echo "SSH key: no public key found in ~/.ssh/"
    SSH_PASSWORD="$(prompt_secret SSH_PASSWORD "SSH password for the dev user")"
fi

# Remove existing container if stopped
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "Container '${CONTAINER_NAME}' is already running."
        echo "SSH: ssh dev@localhost -p ${SSH_PORT}"
        exit 0
    fi
    echo "Removing stopped container '${CONTAINER_NAME}'..."
    docker rm "${CONTAINER_NAME}"
fi

echo "Starting ${IMAGE} as '${CONTAINER_NAME}'..."

docker run -d \
    --name "${CONTAINER_NAME}" \
    --privileged \
    -p "${SSH_PORT}:22" \
    ${GH_TOKEN:+-e GH_TOKEN="${GH_TOKEN}"} \
    ${CLAUDE_CODE_OAUTH_TOKEN:+-e CLAUDE_CODE_OAUTH_TOKEN="${CLAUDE_CODE_OAUTH_TOKEN}"} \
    ${ANTHROPIC_API_KEY:+-e ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY}"} \
    ${INFISICAL_TOKEN:+-e INFISICAL_TOKEN="${INFISICAL_TOKEN}"} \
    ${INFISICAL_CLIENT_ID:+-e INFISICAL_CLIENT_ID="${INFISICAL_CLIENT_ID}"} \
    ${INFISICAL_CLIENT_SECRET:+-e INFISICAL_CLIENT_SECRET="${INFISICAL_CLIENT_SECRET}"} \
    ${SSH_AUTHORIZED_KEY:+-e SSH_AUTHORIZED_KEY="${SSH_AUTHORIZED_KEY}"} \
    ${SSH_PASSWORD:+-e SSH_PASSWORD="${SSH_PASSWORD}"} \
    "${IMAGE}"

echo "Started. Waiting for sshd..."
sleep 2

ssh-keygen -R "[localhost]:${SSH_PORT}" 2>/dev/null || true

echo "SSH: ssh dev@localhost -p ${SSH_PORT}"
