#!/bin/bash
# Launch the CadFlow dev container with Claude Code in autonomous mode.
#
# Prerequisites:
#   - ANTHROPIC_API_KEY set in environment (Claude Code billing)
#   - CADFLOW_ANTHROPIC_API_KEY set in environment (CadFlow API server)
#   - Docker installed
#   - Image built: docker build -f Dockerfile.dev -t cadflow-dev .
#
# Usage:
#   .devcontainer/run.sh              # Interactive shell
#   .devcontainer/run.sh claude       # Start Claude Code autonomously
#   .devcontainer/run.sh claude "task" # Start Claude with a specific task

set -euo pipefail

if [ -z "${GH_TOKEN:-}" ]; then
    echo "Error: GH_TOKEN not set (GitHub PAT for git push/pull)"
    echo "Create one at https://github.com/settings/tokens (scope: repo)"
    exit 1
fi

# Check for Claude auth (either API key or OAuth credentials from host)
if [ -z "${ANTHROPIC_API_KEY:-}" ] && [ ! -d "$HOME/.claude" ]; then
    echo "Warning: No ANTHROPIC_API_KEY set and no ~/.claude/ credentials found."
    echo "Run 'claude' on your host first to log in with your subscription,"
    echo "then your ~/.claude/ will be mounted into the container."
fi

if [ -z "${CADFLOW_ANTHROPIC_API_KEY:-}" ]; then
    echo "Warning: CADFLOW_ANTHROPIC_API_KEY not set."
    echo "The CadFlow API server needs this to call Claude. Set it on your host:"
    echo "  export CADFLOW_ANTHROPIC_API_KEY=sk-ant-..."
fi

IMAGE_NAME="cadflow-dev"
CONTAINER_NAME="cadflow-dev-1"
WORKSPACE_VOL="cadflow-workspace"
HISTORY_VOL="cadflow-commandhistory"

# Build if image doesn't exist
if ! docker image inspect "$IMAGE_NAME" &>/dev/null; then
    echo "Building $IMAGE_NAME..."
    docker build -f Dockerfile.dev -t "$IMAGE_NAME" .
fi

# Common docker args
DOCKER_ARGS=(
    --rm -it
    --name "$CONTAINER_NAME"
    --gpus all
    --device /dev/dri
    --cap-add=NET_ADMIN
    --cap-add=NET_RAW
    ${ANTHROPIC_API_KEY:+-e "ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY"}
    ${CADFLOW_ANTHROPIC_API_KEY:+-e "CADFLOW_ANTHROPIC_API_KEY=$CADFLOW_ANTHROPIC_API_KEY"}
    -e "GH_TOKEN=$GH_TOKEN"
    # Mount host Claude credentials (OAuth login from subscription)
    -v "$HOME/.claude:/home/node/.claude"
    -v "$HOME/.claude.json:/home/node/.claude.json"
    -e "GIT_AUTHOR_NAME=${GIT_AUTHOR_NAME:-CadFlow Dev}"
    -e "GIT_AUTHOR_EMAIL=${GIT_AUTHOR_EMAIL:-dev@cadflow.io}"
    -v "$WORKSPACE_VOL:/workspace"
    -v "$HISTORY_VOL:/commandhistory"
    -p 3000:3000
    -p 8000:8000
)

# Entrypoint handles: git credentials from GH_TOKEN, firewall init.
# We just pass the right command.

case "${1:-shell}" in
    claude)
        shift
        TASK="${1:-}"
        if [ -n "$TASK" ]; then
            echo "Starting Claude Code with task: $TASK"
            docker run "${DOCKER_ARGS[@]}" "$IMAGE_NAME" \
                -- claude --dangerously-skip-permissions -p "$TASK"
        else
            echo "Starting Claude Code (interactive, permissions bypassed)"
            docker run "${DOCKER_ARGS[@]}" "$IMAGE_NAME" \
                -- claude --dangerously-skip-permissions
        fi
        ;;
    implement)
        shift
        PLAN="${1:-}"
        if [ -z "$PLAN" ]; then
            echo "Usage: $0 implement <plan-file>  (relative to CadFlow root)"
            exit 1
        fi
        echo "Running implementation plan: $PLAN"
        docker run "${DOCKER_ARGS[@]}" "$IMAGE_NAME" \
            -- bash /workspace/scripts/run-plan.sh "/workspace/$PLAN"
        ;;
    debug-loop)
        echo "Starting debug loop"
        docker run "${DOCKER_ARGS[@]}" "$IMAGE_NAME" \
            -- bash -c 'claude -p "$(cat /workspace/ia-workflows/debug-loop.md)"'
        ;;
    full-review)
        shift
        PLAN="${1:-}"
        BRANCH="${2:-}"
        if [ -z "$PLAN" ]; then
            echo "Usage: $0 full-review <plan-file> [branch-name]  (plan relative to CadFlow root)"
            exit 1
        fi
        echo "Running full review: $PLAN"
        docker run "${DOCKER_ARGS[@]}" "$IMAGE_NAME" \
            -- bash /workspace/scripts/run-review-followups.sh "/workspace/$PLAN" ${BRANCH:+"$BRANCH"}
        ;;
    shell)
        echo "Starting interactive shell"
        docker run "${DOCKER_ARGS[@]}" "$IMAGE_NAME"
        ;;
    *)
        echo "Usage: $0 [shell|claude|implement|debug-loop|full-review] [args]"
        exit 1
        ;;
esac
