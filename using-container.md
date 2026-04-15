# CadFlow Development Container

A Docker-based development environment for CadFlow that runs Claude Code in autonomous mode with all dependencies pre-installed (CadQuery, OCCT, Node.js, pnpm, Python, meshing tools).

## Prerequisites

- Docker installed
- A GitHub Personal Access Token (`GH_TOKEN`) with the following permissions — [create one here](https://github.com/settings/tokens):
  - **Contents**: read & write
  - **Metadata**: read
  - **Issues**: read
  - **Pull requests**: read & write
- `ANTHROPIC_API_KEY` — required for the CadFlow server's Claude Agent SDK integration (and also used by the Claude Code CLI if present). Host `~/.claude/` credentials alone are enough for the CLI but **not** for the server.

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

### Claude Code CLI

The run script mounts your host `~/.claude/` directory into the container for OAuth credentials (subscription login). If you use API billing instead, set `ANTHROPIC_API_KEY` before running.

### CadFlow Server (Agent API Key)

The FastAPI backend uses the Claude Agent SDK to power the chat-driven CAD workflow. It calls the Anthropic API directly, so it **always** requires `ANTHROPIC_API_KEY` — mounted `~/.claude/` credentials are not sufficient for the server.

Set the key before starting the container:

```bash
export ANTHROPIC_API_KEY=sk-ant-...
```

The key is passed into the container by `run.sh` and used at runtime by the FastAPI process. Without it the server starts but all agent/chat requests will fail.

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

## NVIDIA GPU Access

The `run.sh` script already passes `--gpus all` and `--device /dev/dri` to Docker, so GPU devices are forwarded into the container automatically. To make this work you need the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) installed on the host.

Verify it works by running `nvidia-smi` inside the container:

If you do **not** have an NVIDIA GPU (or don't need GPU access), remove the `--gpus all` and `--device /dev/dri` lines from `run.sh` to avoid Docker errors on startup.

## Network Firewall (Optional)

The container includes an iptables-based firewall (`init-firewall.sh`) that restricts outbound traffic to approved domains only (Anthropic API, GitHub, npm, PyPI). It is disabled by default in the entrypoint — uncomment the line in `entrypoint.sh` to enable it.

## Remote Server Access

See [client-server.md](client-server.md) for instructions on running the container on a remote server and accessing it via SSH tunnel.
