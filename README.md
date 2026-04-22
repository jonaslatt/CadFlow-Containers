# CadFlow Development Container

A Docker-based development environment for CadFlow — an agentic CAD tool built on CadQuery/OCCT with Claude Code for autonomous AI development. Runs Claude Code in autonomous mode with all dependencies pre-installed (CadQuery, OCCT, Node.js, pnpm, Python, meshing tools).

## Contents

- **[Dockerfile.dev](Dockerfile.dev)** — Container image with CadQuery, Node.js, pnpm, Claude Code, and all dependencies
- **[.devcontainer/](.devcontainer/)** — Launch scripts, firewall, and VS Code Dev Container config
- **[ai-workflows/](ai-workflows/)** — Autonomous AI workflow definitions (debug loop, etc.)
- **[client-server.md](client-server.md)** — Remote server access via SSH tunnel
- **[adr/](adr/)** — Architecture Decision Records for CadFlow

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

**Claude Code CLI** — The run script mounts your host `~/.claude/` directory into the container for OAuth credentials. If you use API billing instead, set `ANTHROPIC_API_KEY` before running.

**CadFlow server** — The FastAPI backend calls the Anthropic API directly via the Claude Agent SDK, so it always requires `ANTHROPIC_API_KEY`. Mounted `~/.claude/` credentials are not sufficient.

```bash
export ANTHROPIC_API_KEY=sk-ant-...
```

Without it the server starts but all agent/chat requests will fail.

## Container Contents

| Component | Details |
|-----------|---------|
| **Python** | CadQuery, ocp-tessellate, gmsh, FastAPI, uvicorn, pytest |
| **Node.js** | pnpm, Turborepo, Claude Code CLI |
| **System** | Git, tmux (required), iptables (optional firewall), Podman (for sandbox testing) |
| **Ports** | 3000 (frontend), 8000 (backend API) |

## Automated Actions

These actions run non-interactively via the run script:

```bash
# Run an implementation plan
.devcontainer/run.sh implement <plan-file>

# Run review + follow-up fixes (branch is optional)
.devcontainer/run.sh full-review <plan-file> [branch]
```

Plan files are resolved relative to `/workspace` inside the container.

## Debug Loop

The debug loop is an autonomous Claude Code session that continuously runs tests, identifies failures, and applies fixes. It must be started manually:

```bash
# 1. Start an interactive shell in the container
.devcontainer/run.sh shell

# 2. Inside the container, start tmux
tmux

# 3. Start Claude Code
claude --dangerously-skip-permissions
```

Then at the Claude Code prompt, enter:

```
Read ai-workflows/debug-loop.md and execute the startup procedure. Then start the autonomous debug loop as described in that document.
```

See [ai-workflows/debug-loop.md](ai-workflows/debug-loop.md) for the full procedure.

## GPU Setup

The `run.sh` script passes `--gpus all` and `--device /dev/dri` to Docker automatically. This requires the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) on the host.

If you don't have an NVIDIA GPU, remove the `--gpus all` and `--device /dev/dri` lines from `run.sh` to avoid Docker errors.

## Network Firewall (Optional)

The container includes an iptables-based firewall (`init-firewall.sh`) that restricts outbound traffic to approved domains (Anthropic API, GitHub, npm, PyPI). It is disabled by default — uncomment the relevant line in `entrypoint.sh` to enable it.

## tmux

**tmux is required inside the container.** Claude Code uses it to manage background processes (dev servers, build processes, test suites) and to capture their output. Without tmux, Claude Code cannot run parallel workstreams. It is pre-installed in the image.

## Remote Server Access

See [client-server.md](client-server.md) for running the container on a remote server and accessing it via SSH tunnel.
