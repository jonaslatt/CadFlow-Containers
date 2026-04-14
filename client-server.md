# CadFlow: Remote Server Setup

Run the backend and frontend in a Docker container on a server, access from your laptop via SSH tunnel.

## Ports

| Service          | Port |
|------------------|------|
| Frontend (Vite)  | 3000 |
| Backend (Uvicorn)| 8000 |

## Step 1 — Start services in the container

Both services must bind to `0.0.0.0` (not just localhost) so they are reachable from outside the container.

**Terminal 1 — Backend API:**

```bash
source /workspace/.venv/bin/activate
cd /workspace/apps/api
PYTHONPATH=/workspace/packages/kernel/src:src uvicorn cadflow_api.main:app --reload --host 0.0.0.0 --port 8000
```

> **Note:** The `PYTHONPATH` prefix is required so that both the `cadflow_kernel` package and the API source are importable.

**Terminal 2 — Frontend dev server:**

```bash
cd /workspace
pnpm --filter web dev --host 0.0.0.0
```

## Step 2 — SSH tunnel from your laptop

On your **laptop**, run:

```bash
ssh -L 3000:localhost:3000 -L 8000:localhost:8000 user@your-server
```

This forwards:
- `laptop:3000` → `server:3000` → Vite dev server
- `laptop:8000` → `server:8000` → FastAPI backend

## Step 3 — Open in your browser

Navigate to `http://localhost:3000` on your laptop.

## Docker networking notes

If you SSH into the **server host** but the container has its own network, ensure the container ports are exposed.

Check current port mappings:

```bash
docker ps   # look at the PORTS column
```

If ports aren't exposed, either:

1. **Add port mappings** when starting the container:
   ```bash
   docker run -p 3000:3000 -p 8000:8000 ...
   ```

2. **Or adjust the SSH tunnel** to match the host-side ports. For example, if `docker run -p 9000:3000 -p 9001:8000`, then:
   ```bash
   ssh -L 3000:localhost:9000 -L 8000:localhost:9001 user@your-server
   ```
