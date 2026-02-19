#!/bin/bash
set -e

REPO="$1"   # e.g. jasara/conveyr
TASK="$2"   # e.g. "Debug Sentry issue XYZ"

if [ -z "$REPO" ] || [ -z "$TASK" ]; then
    echo "Usage: work.sh <org/repo> <task description>"
    exit 1
fi

REPO_NAME="${REPO##*/}"
CLONE_DIR="${HOME}/Repositories/${REPO_NAME}"
WORKTREES_BASE="${HOME}/worktrees/${REPO_NAME}"

# 1. Clone repo if not already there
if [ ! -d "${CLONE_DIR}/.git" ]; then
    echo "Cloning ${REPO}..."
    mkdir -p "${HOME}/Repositories"
    gh repo clone "${REPO}" "${CLONE_DIR}"
fi

# 2. Generate short identifier using Claude haiku
echo "Generating branch identifier..."
IDENTIFIER=$(claude -p "Output only a short kebab-case git branch identifier (2-4 words, lowercase, no punctuation other than hyphens) for this task: ${TASK}" \
    --model claude-haiku-4-5-20251001 \
    | head -1 \
    | tr '[:upper:]' '[:lower:]' \
    | tr -cs '[:alnum:]-' '-' \
    | sed 's/^-*//;s/-*$//' \
    | cut -c1-50)

if [ -z "$IDENTIFIER" ]; then
    echo "Error: failed to generate branch identifier"
    echo "Test claude directly with: claude -p 'hello' --model claude-haiku-4-5-20251001"
    exit 1
fi

# Make identifier unique by suffixing -2, -3, etc. if already in use
BASE_IDENTIFIER="${IDENTIFIER}"
COUNTER=1
mkdir -p "${WORKTREES_BASE}"
while [ -d "${WORKTREES_BASE}/${IDENTIFIER}" ] \
    || git -C "${CLONE_DIR}" rev-parse --verify "${IDENTIFIER}" &>/dev/null; do
    IDENTIFIER="${BASE_IDENTIFIER}-${COUNTER}"
    COUNTER=$((COUNTER + 1))
done

echo "Identifier: ${IDENTIFIER}"

# 3. Create worktree if it doesn't exist
WORKTREE_PATH="${WORKTREES_BASE}/${IDENTIFIER}"

if [ ! -d "${WORKTREE_PATH}" ]; then
    gh auth setup-git
    git -C "${CLONE_DIR}" fetch origin
    DEFAULT_BRANCH=$(git -C "${CLONE_DIR}" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
        | sed 's|refs/remotes/origin/||' || echo "main")
    git -C "${CLONE_DIR}" worktree add "${WORKTREE_PATH}" -b "${IDENTIFIER}" "origin/${DEFAULT_BRANCH}"
fi

# 4 & 5. Create tmux session in worktree and run claude with initial message
SESSION="${IDENTIFIER}"

# Escape task for safe use in a double-quoted shell string
ESCAPED_TASK=$(printf '%s' "$TASK" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\$/\\$/g; s/`/\\`/g')

tmux_attach() {
    if [ -n "$TMUX" ]; then
        tmux switch-client -t "${SESSION}"
    else
        tmux attach-session -t "${SESSION}"
    fi
}

if tmux has-session -t "${SESSION}" 2>/dev/null; then
    echo "Attaching to existing session '${SESSION}'..."
    tmux_attach
else
    tmux new-session -d -s "${SESSION}" -c "${WORKTREE_PATH}"
    tmux send-keys -t "${SESSION}" "claude --dangerously-skip-permissions \"${ESCAPED_TASK}\"" Enter
    tmux_attach
fi
