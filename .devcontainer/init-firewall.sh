#!/bin/bash
# Firewall for Claude Code container.
# Restricts outbound network to approved domains only.
# Uses DNS resolution to get current IPs for each domain.
#
# Usage: sudo /usr/local/bin/init-firewall.sh

set -euo pipefail

# Flush existing rules
iptables -F OUTPUT
iptables -F INPUT

# Allow loopback
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT

# Allow established connections
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow DNS
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

# --- Helper: allow all IPs for a domain ---
allow_domain() {
    local domain="$1"
    local port="${2:-443}"
    # Resolve all IPs (IPv4) for the domain
    for ip in $(dig +short A "$domain" 2>/dev/null | grep -E '^[0-9]+\.' || true); do
        iptables -A OUTPUT -d "$ip" -p tcp --dport "$port" -j ACCEPT
    done
}

# --- Approved domains ---

# Anthropic API (Claude)
allow_domain api.anthropic.com
allow_domain anthropic.com

# Claude OAuth (subscription login)
allow_domain console.anthropic.com
allow_domain auth.anthropic.com
allow_domain statsigapi.net

# GitHub (git push/pull, API, auth, LFS)
allow_domain github.com
allow_domain github.com 22
allow_domain api.github.com
allow_domain github.githubassets.com
allow_domain objects.githubusercontent.com
allow_domain raw.githubusercontent.com

# npm registry
allow_domain registry.npmjs.org
allow_domain registry.yarnpkg.com

# PyPI
allow_domain pypi.org
allow_domain files.pythonhosted.org

# --- Block everything else ---
iptables -A OUTPUT -p tcp --dport 80 -j DROP
iptables -A OUTPUT -p tcp --dport 443 -j DROP
iptables -A OUTPUT -p tcp --dport 22 -j DROP

echo "Firewall initialized. Outbound restricted to approved domains."
