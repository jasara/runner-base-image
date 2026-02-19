#!/bin/bash
set -e

CONTAINER_NAME="${CONTAINER_NAME:-dev}"
IMAGE="${IMAGE:-base-developer-image:latest}"
SSH_PORT="${SSH_PORT:-2222}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v ngrok &>/dev/null; then
    echo "ngrok is not installed. Install it with:"
    echo "  brew install ngrok/ngrok/ngrok"
    echo "Then authenticate: ngrok config add-authtoken <your-token>"
    exit 1
fi

NGROK_ADDR="3.tcp.ngrok.io:20785"

start_tunnel() {
    local tunnel_log
    tunnel_log=$(mktemp)
    ngrok tcp --url "tcp://${NGROK_ADDR}" "${SSH_PORT}" > "${tunnel_log}" 2>&1 &

    echo "Starting ngrok tunnel..."
    local ready=false
    for _ in $(seq 1 30); do
        if curl -s http://localhost:4040/api/tunnels 2>/dev/null | grep -q "public_url"; then
            ready=true
            break
        fi
        sleep 1
    done

    if [ "$ready" = false ]; then
        echo "Warning: ngrok tunnel failed to start."
        echo "ngrok output:"
        cat "${tunnel_log}"
        rm -f "${tunnel_log}"
        return
    fi
    rm -f "${tunnel_log}"

    echo ""
    echo "ngrok tunnel: tcp://${NGROK_ADDR}"
    echo ""
    echo "Termius connection:"
    echo "  Host: ${NGROK_ADDR%%:*}"
    echo "  Port: ${NGROK_ADDR##*:}"
    echo "  User: dev"
    echo ""
    echo "Or plain SSH:"
    echo "  ssh dev@${NGROK_ADDR%%:*} -p ${NGROK_ADDR##*:}"
}

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
if [ -f "${SCRIPT_DIR}/.ssh_keys" ]; then
    SSH_AUTHORIZED_KEY="${SSH_AUTHORIZED_KEY:+${SSH_AUTHORIZED_KEY}$'\n'}$(cat "${SCRIPT_DIR}/.ssh_keys")"
fi
if [ -z "$SSH_AUTHORIZED_KEY" ] && [ -z "$SSH_PASSWORD" ]; then
    echo "SSH key: no public key found in ~/.ssh/"
    SSH_PASSWORD="$(prompt_secret SSH_PASSWORD "SSH password for the dev user")"
fi

# Remove existing container (stop first if running)
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "Stopping running container '${CONTAINER_NAME}'..."
        docker stop "${CONTAINER_NAME}"
    fi
    echo "Removing container '${CONTAINER_NAME}'..."
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

docker cp "${SCRIPT_DIR}/overlay/usr/local/bin/work.sh" "${CONTAINER_NAME}:/usr/local/bin/work.sh"
docker exec "${CONTAINER_NAME}" chmod +x /usr/local/bin/work.sh

ssh-keygen -R "[localhost]:${SSH_PORT}" 2>/dev/null || true

echo "SSH: ssh dev@localhost -p ${SSH_PORT}"
start_tunnel
