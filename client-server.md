# CadFlow: Remote Server Setup

Run the container on a remote server and access the frontend and backend from your laptop via SSH tunnel.

## Ports

| Service           | Port |
|-------------------|------|
| Frontend (Vite)   | 3000 |
| Backend (Uvicorn) | 8000 |

## Step 1 — Start services inside the container

Both services must bind to `0.0.0.0` so they are reachable from outside the container.

**Backend:**

```bash
source /workspace/.venv/bin/activate
cd /workspace/apps/api
PYTHONPATH=/workspace/packages/kernel/src:src uvicorn cadflow_api.main:app --reload --host 0.0.0.0 --port 8000
```

> The `PYTHONPATH` prefix is required for both `cadflow_kernel` and the API source to be importable.

**Frontend:**

```bash
cd /workspace
pnpm --filter web dev --host 0.0.0.0
```

## Step 2 — SSH tunnel from your laptop

```bash
ssh -L 3000:localhost:3000 -L 8000:localhost:8000 user@your-server
```

## Step 3 — Open in browser

Navigate to `http://localhost:3000`.

## Docker port mapping

If the container ports aren't exposed to the server host, add `-p 3000:3000 -p 8000:8000` to the `docker run` command (already included in `run.sh`).

If you mapped to non-standard host ports (e.g. `-p 9000:3000 -p 9001:8000`), adjust the tunnel accordingly:

```bash
ssh -L 3000:localhost:9000 -L 8000:localhost:9001 user@your-server
```
