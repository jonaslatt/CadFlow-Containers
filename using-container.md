# CadFlow Development Container

A Docker-based development environment for CadFlow that runs Claude Code in autonomous mode with all dependencies pre-installed (CadQuery, OCCT, Node.js, pnpm, Python, meshing tools).

## Prerequisites

- Docker installed
- A GitHub Personal Access Token (`GH_TOKEN`) with `repo` scope — [create one here](https://github.com/settings/tokens)
- Claude authentication: either `ANTHROPIC_API_KEY` (API billing) or host `~/.claude/` credentials (subscription)

## Quick Start

```bash
# Set required env vars
export GH_TOKEN=ghp_...

# Build the image (first time only)
docker build -f Dockerfile.dev -t cadflow-dev .

# Interactive shell
.devcontainer/run.sh shell

# Claude Code (interactive, with --dangerously-skip-permissions)
.devcontainer/run.sh claude

# Claude Code with a specific task
.devcontainer/run.sh claude "implement the meshing endpoint"
```

## Authentication

The run script mounts your host `~/.claude/` directory into the container for OAuth credentials (subscription login). If you use API billing instead, set `ANTHROPIC_API_KEY` before running.

## What's in the Container

| Component | Details |
|-----------|---------|
| **Python** | CadQuery, ocp-tessellate, gmsh, FastAPI, uvicorn, pytest |
| **Node.js** | pnpm, Turborepo, Claude Code CLI |
| **System** | Git, iptables (optional firewall), Podman (for sandbox testing) |
| **Ports** | 3000 (frontend), 8000 (backend API) |

## File Layout

```
.devcontainer/
  devcontainer.json   # VS Code Dev Container config
  run.sh              # Container launch script
  entrypoint.sh       # Git credentials + firewall setup
  init-firewall.sh    # Optional outbound network restrictions
Dockerfile.dev        # Container image definition
```

## Network Firewall (Optional)

The container includes an iptables-based firewall (`init-firewall.sh`) that restricts outbound traffic to approved domains only (Anthropic API, GitHub, npm, PyPI). It is disabled by default in the entrypoint — uncomment the line in `entrypoint.sh` to enable it.

## Remote Server Access

See [client-server.md](client-server.md) for instructions on running the container on a remote server and accessing it via SSH tunnel.
