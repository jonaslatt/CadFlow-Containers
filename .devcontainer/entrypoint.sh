#!/bin/bash
# Container entrypoint: configures git credentials, firewall, then runs the command.
# Auth: either ANTHROPIC_API_KEY (API billing) or mounted ~/.claude/ (subscription).
set -euo pipefail

# Configure git identity
git config --global user.name "${GIT_AUTHOR_NAME:-CadFlow Dev}"
git config --global user.email "${GIT_AUTHOR_EMAIL:-dev@cadflow.io}"

# Configure git to authenticate with GitHub using the PAT.
# This makes git push/pull/clone work for any github.com repo
# without SSH keys or interactive login.
if [ -n "${GH_TOKEN:-}" ]; then
    git config --global credential.helper store
    echo "https://x-access-token:${GH_TOKEN}@github.com" > ~/.git-credentials
    chmod 600 ~/.git-credentials
fi

# Firewall disabled for now — container isolation is sufficient for dev.
# Uncomment to restrict outbound network:
# sudo /usr/local/bin/init-firewall.sh

# Run whatever command was passed (claude, zsh, etc.)
exec "$@"
