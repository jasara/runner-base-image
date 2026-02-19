#!/bin/bash

# Export select env vars to /etc/environment so SSH sessions inherit them
for var in CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY GH_TOKEN INFISICAL_TOKEN \
           INFISICAL_CLIENT_ID INFISICAL_CLIENT_SECRET; do
    if [ -n "${!var}" ]; then
        echo "${var}=${!var}" >> /etc/environment
    fi
done

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
