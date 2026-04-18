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

# ----------------------------------------------------------------------
# Enable Claude Code plugins for the /workspace project.
#
# ~/.claude is bind-mounted from the host, so the plugin cache and
# marketplace registry already exist. But the host's installed_plugins.json
# scopes the plugins to the host project path (/home/jonas/git/cad-ui),
# and the host's project-level settings.json isn't visible in /workspace.
# This block makes the plugins active for Claude running in /workspace.
# ----------------------------------------------------------------------
PLUGINS=(
    "pyright-lsp@claude-plugins-official"
    "typescript-lsp@claude-plugins-official"
)

WORKSPACE_SETTINGS="/workspace/.claude/settings.json"
mkdir -p "$(dirname "$WORKSPACE_SETTINGS")"
[ -f "$WORKSPACE_SETTINGS" ] || echo '{}' > "$WORKSPACE_SETTINGS"

JQ_FILTER='.enabledPlugins = ((.enabledPlugins // {}) + $p)'
PLUGIN_OBJ=$(printf '"%s":true,' "${PLUGINS[@]}")
PLUGIN_OBJ="{${PLUGIN_OBJ%,}}"
TMP=$(mktemp)
jq --argjson p "$PLUGIN_OBJ" "$JQ_FILTER" "$WORKSPACE_SETTINGS" > "$TMP" \
    && mv "$TMP" "$WORKSPACE_SETTINGS"

INSTALLED="$HOME/.claude/plugins/installed_plugins.json"
if [ -f "$INSTALLED" ]; then
    for plugin in "${PLUGINS[@]}"; do
        TMP=$(mktemp)
        jq --arg name "$plugin" --arg path "/workspace" '
          .plugins[$name] //= [] |
          if (.plugins[$name] | map(.projectPath) | index($path)) == null
             and (.plugins[$name] | length) > 0
          then
            .plugins[$name] += [ .plugins[$name][0] * {projectPath: $path} ]
          else . end
        ' "$INSTALLED" > "$TMP" && mv "$TMP" "$INSTALLED"
    done
fi

# Run whatever command was passed (claude, zsh, etc.)
exec "$@"
