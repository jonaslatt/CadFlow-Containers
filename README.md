# CadFlow Containers

Development container setup for CadFlow — an agentic CAD tool built on CadQuery/OCCT with Claude Code for autonomous AI development.

## Contents

- **[Dockerfile.dev](Dockerfile.dev)** — Container image with CadQuery, Node.js, pnpm, Claude Code, and all dependencies
- **[.devcontainer/](.devcontainer/)** — Launch scripts, firewall, and VS Code Dev Container config
- **[ai-workflows/](ai-workflows/)** — Autonomous AI workflow definitions (debug loop, etc.)
- **[using-container.md](using-container.md)** — How to build, run, and use the container
- **[client-server.md](client-server.md)** — Remote server access via SSH tunnel
- **[adr/](adr/)** — Architecture Decision Records for CadFlow

## Quick Start

```bash
export GH_TOKEN=ghp_...
docker build -f Dockerfile.dev -t cadflow-dev .
.devcontainer/run.sh claude
```

See [using-container.md](using-container.md) for full details.
