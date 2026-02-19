#!/bin/bash

# Export select env vars to /etc/environment so SSH sessions inherit them
for var in CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY GH_TOKEN INFISICAL_TOKEN \
           INFISICAL_CLIENT_ID INFISICAL_CLIENT_SECRET; do
    if [ -n "${!var}" ]; then
        echo "${var}=${!var}" >> /etc/environment
    fi
done

# Pre-configure Claude Code so it doesn't show the setup wizard
mkdir -p /home/dev/.claude
printf '{"theme":"dark","skipDangerousModePermissionPrompt":true}' > /home/dev/.claude/settings.json
if [ -n "${CLAUDE_CODE_OAUTH_TOKEN}" ]; then
    printf '{"claudeAiOauth":{"accessToken":"%s","expiresAt":9999999999999,"refreshToken":""}}' \
        "${CLAUDE_CODE_OAUTH_TOKEN}" > /home/dev/.claude/.credentials.json
    printf '{"hasCompletedOnboarding":true,"lastOnboardingVersion":"1.0.17"}' \
        > /home/dev/.claude.json
elif [ -n "${ANTHROPIC_API_KEY}" ]; then
    printf '{"primaryApiKey":"%s","hasCompletedOnboarding":true,"lastOnboardingVersion":"1.0.17"}' \
        "${ANTHROPIC_API_KEY}" > /home/dev/.claude.json
fi
chown -R dev:dev /home/dev/.claude
chown dev:dev /home/dev/.claude.json 2>/dev/null || true

# Generate SSH host keys if missing and start sshd
ssh-keygen -A
mkdir -p /run/sshd

if [ -n "${SSH_AUTHORIZED_KEY}" ]; then
    mkdir -p /home/dev/.ssh
    echo "${SSH_AUTHORIZED_KEY}" >> /home/dev/.ssh/authorized_keys
    chmod 700 /home/dev/.ssh
    chmod 600 /home/dev/.ssh/authorized_keys
    chown -R dev:dev /home/dev/.ssh
fi

if [ -n "${SSH_PASSWORD}" ]; then
    echo "dev:${SSH_PASSWORD}" | chpasswd
fi

/usr/sbin/sshd

exec "$@"
