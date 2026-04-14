# ADR-004: Backend Architecture and Communication

## Status
Proposed

## Date
2026-04-07

## Context

CadFlow requires a backend that can safely execute CadQuery/OCCT geometry operations, stream results to a browser-based 3D viewer, and integrate Claude as an AI agent for natural language CAD interactions. The backend must handle three distinct communication patterns: CRUD operations on projects/models, real-time geometry updates during interactive editing, and streaming AI responses from Claude.

Key forces at play:
- **Geometry computation is CPU-intensive and crash-prone.** OCCT can segfault on edge cases; these crashes must not bring down the server.
- **Real-time feedback is essential.** Users expect sub-second visual updates when modifying parameters.
- **Claude integration requires streaming.** LLM responses must stream token-by-token to the UI.
- **Small team.** The architecture must be buildable and operable by 1-3 developers.
- **Security.** User/agent-generated CadQuery code executes arbitrary Python — sandboxing is critical (detailed in ADR-010).

## Research Findings

### Onshape's Cloud Architecture

Onshape is the closest production analog. Key architectural details from their public documentation:

- **Three server types:** Authentication/Document servers (high request volume, low compute), Modeling servers (persistent user sessions), and Geometry servers (isolated, compute-optimized, crash-safe). If a geometry server crashes, data remains safe. ([Onshape: How Does Onshape Really Work?](https://www.onshape.com/en/blog/how-does-onshape-really-work), [Onshape Architecture Docs](https://onshape-public.github.io/docs/api-intro/architecture/))
- **Dual protocol:** HTTPS/REST for standard API calls + WebSocket with custom wire protocol for real-time bidirectional geometry communication.
- **Tessellation on demand:** Tessellated mesh data is NOT stored persistently — generated on demand and cached. Clients receive triangles, not BREP.
- **Git-inspired data model:** MongoDB with every change recorded as an incremental diff (microversion). ([Onshape: Cloud-Native Architecture](https://www.onshape.com/en/blog/cloud-native-architecture-empowers-cad-pdm))

### CadQuery Server Architectures

The CadQuery ecosystem has established patterns for serving geometry to browsers:

- **OCP CAD Viewer** (the modern stack): Three-layer architecture — `ocp-tessellate` (Python, tessellates OCP shapes via BRepMesh_IncrementalMesh) → `cad-viewer-widget` (ipywidget wrapper) → `three-cad-viewer` (Three.js renderer). WebSocket communication on port 3939. ([OCP CAD Viewer GitHub](https://github.com/bernhard-42/vscode-ocp-cad-viewer))
- **cadquery2web:** Three-tier Docker Compose — Frontend (Three.js) / Backend (Node.js queue) / CadQuery Server (Python). Implements strict whitelist validation on imports and functions. Coarse tessellation for preview, high-res for export. ([cadquery2web GitHub](https://github.com/30hours/cadquery2web))
- **cq-server:** Flask-based, REST endpoints returning HTML/JSON/STEP/glTF/STL. No longer actively maintained.
- **ocp-tessellate:** Uses OCCT's BRepMesh_IncrementalMesh with configurable linear deflection (default 0.1) and angular tolerance (default 0.2). Apache-2.0, actively maintained. ([ocp-tessellate GitHub](https://github.com/bernhard-42/ocp-tessellate))

### Communication Protocols

| Protocol | Direction | Overhead | Reconnect | Best For |
|----------|-----------|----------|-----------|----------|
| **WebSocket** | Bidirectional | 2 bytes/frame | Manual | Interactive editing, geometry updates |
| **SSE** | Server→client | HTTP headers | Automatic | LLM streaming, status updates |
| **REST** | Request/response | 500+ bytes | N/A | CRUD, infrequent operations |
| **gRPC-Web** | Server streaming | Binary protobuf | Manual | High-throughput binary data |

Onshape uses WebSocket for geometry; OCP CAD Viewer uses WebSocket. SSE is the natural fit for Claude's streaming responses. ([RxDB: WebSockets vs SSE vs Polling](https://rxdb.info/articles/websockets-sse-polling-webrtc-webtransport.html))

### Claude API Integration Patterns

- **Tool use:** JSON schema-defined tools with `strict: true` for schema conformance. Claude decides when to call tools based on descriptions and context. ([Tool Use Overview](https://platform.claude.com/docs/en/agents-and-tools/tool-use/overview))
- **Fine-Grained Tool Streaming:** Stream tool parameters without full buffering, reducing latency. ([Fine-Grained Tool Streaming](https://platform.claude.com/docs/en/agents-and-tools/tool-use/fine-grained-tool-streaming))
- **Programmatic Tool Calling:** Claude writes code that calls multiple tools and processes outputs, reducing API round-trips dramatically. ([Programmatic Tool Calling](https://platform.claude.com/docs/en/agents-and-tools/tool-use/programmatic-tool-calling))
- **Agent SDK:** `query()` returns async iterator, streaming messages as Claude thinks and calls tools. Maintains conversation context across multiple calls. ([Agent SDK](https://platform.claude.com/docs/en/agent-sdk/overview))

### Geometry Data Transfer

Proven pipeline from the CadQuery ecosystem:
1. CadQuery produces OCP `TopoDS_Shape` (BREP)
2. `ocp-tessellate` runs `BRepMesh_IncrementalMesh`, extracts vertices + triangles per face
3. JSON serialization of mesh data over WebSocket
4. `three-cad-viewer` renders via Three.js/WebGL

Compression options: **Draco** (60-90% vertex data reduction, glTF extension) or **MeshOpt** (similar compression, faster decoding, GPU-friendly). For incremental updates: re-tessellate only changed features, send deltas. ([Draco with glTF](https://cesium.com/blog/2018/04/09/draco-compression/), [meshoptimizer](https://meshoptimizer.org/))

### Sandboxing Summary

Python cannot be sandboxed internally. Options range from Docker (simple, medium security) to Firecracker microVMs (125ms boot, hardware isolation) to gVisor (user-space kernel, 10-30% overhead). cadquery2web demonstrates the whitelist validation pattern. Full analysis in ADR-010.

## Options Considered

### Option A: Monolithic Python Server (In-Process CadQuery)

A single FastAPI process runs CadQuery directly in the same Python interpreter.

- **Pros:** Simplest to build. Zero communication overhead between API and geometry kernel. Easy to debug.
- **Cons:** An OCCT segfault kills the entire server. No isolation between users. Cannot enforce resource limits per operation. No crash recovery.
- **Real-world precedent:** CQ-editor runs CadQuery in-process — acceptable for a desktop app, dangerous for a server.

### Option B: Full Microservices (Onshape-Style)

Separate services for auth, document management, modeling sessions, and geometry computation. Each with its own database, deployment, and scaling policy.

- **Pros:** Maximum scalability and isolation. Geometry crashes are fully contained. Services scale independently. Matches Onshape's battle-tested architecture.
- **Cons:** Massively over-engineered for a small team. 4+ services to build, deploy, monitor, and version. Network serialization overhead between every service. Distributed system complexity (consistency, failure modes, debugging).
- **Real-world precedent:** Onshape, with a team of 50+ engineers and years of development.

### Option C: Modular Monolith with Isolated Geometry Workers (Recommended)

A single FastAPI backend handles REST, WebSocket, and SSE, but delegates CadQuery execution to isolated worker processes. The backend and workers communicate via a job queue.

- **Pros:** Single service to deploy and monitor. OCCT crashes kill only the worker process, not the server. Resource limits (CPU, memory, time) enforced per worker. Easy to evolve toward microservices later. Matches cadquery2web's proven pattern.
- **Cons:** Worker communication adds latency (~10-50ms per operation). Worker pool management adds complexity. Not as scalable as true microservices.
- **Real-world precedent:** cadquery2web (Docker-isolated CadQuery workers), Celery-based task architectures used by many Python web apps.

## Decision

**Option C: Modular Monolith with Isolated Geometry Workers.**

### Architecture Overview

```
Browser (React + Three.js)
  ├── REST ──────→ FastAPI ──→ PostgreSQL (projects, users, intent graphs)
  ├── WebSocket ─→ FastAPI ──→ Geometry Worker Pool (CadQuery/OCCT)
  │                              ├── Worker 1 (subprocess, sandboxed)
  │                              ├── Worker 2
  │                              └── Worker N
  └── SSE ───────→ FastAPI ──→ Claude Agent SDK (streaming)
```

### Communication Protocol Mix

| Channel | Protocol | Purpose |
|---------|----------|---------|
| Project CRUD | REST | Create/read/update/delete projects, list history |
| Geometry updates | WebSocket | Stream tessellated mesh data during interactive editing |
| Agent responses | SSE | Stream Claude's token-by-token responses |
| File upload/download | REST | Import STEP, export STL/STEP/BREP |

### Backend Technology

- **Framework:** FastAPI (Python) — native async support, WebSocket and SSE built-in, OpenAPI docs, excellent Claude SDK integration (Python-native).
- **Geometry workers:** Subprocess pool managed by the FastAPI process. Each worker pre-imports CadQuery with configured thread limits (`OSD_ThreadPool.DefaultPool_s(2)`). Workers have cgroup-enforced memory limits (2GB) and wall-clock timeouts (60s). A watchdog replaces crashed workers.
- **Task queue:** For V1, use Python `multiprocessing.Pool` or `concurrent.futures.ProcessPoolExecutor`. Graduate to Celery + Redis when scaling demands it.
- **Database:** PostgreSQL — relational for users/projects/permissions, JSONB for intent graph documents (per ADR-008).

### Tessellation Pipeline

1. User action triggers intent graph modification
2. Backend sends CadQuery code to a geometry worker
3. Worker executes CadQuery, produces `TopoDS_Shape`
4. Worker runs `ocp-tessellate` to generate mesh data (vertices, normals, triangles, edges per face)
5. Mesh data serialized and sent back to backend
6. Backend streams mesh data to client via WebSocket
7. Three.js/R3F updates the 3D scene incrementally

Two tessellation levels: coarse (low deflection) for interactive preview, fine (high deflection) for export.

### Claude Integration

- Claude Agent SDK (Python) integrated directly into the FastAPI backend
- Domain-specific tools defined as JSON schemas:
  - `cad_execute_code` — run CadQuery script in sandboxed worker
  - `cad_modify_feature` — edit intent graph node parameters
  - `cad_query_geometry` — measure distances, volumes, face counts, bounding box
  - `cad_export` — generate STEP/STL/BREP/glTF
  - `cad_validate` — run BRepCheck_Analyzer, watertight check
  - `cad_search_docs` — look up CadQuery API reference
- Agent responses stream via SSE to the frontend chat panel
- Programmatic Tool Calling for multi-step geometry operations to reduce round-trips

### Error Handling

| Error Type | Handling |
|-----------|----------|
| OCCT segfault | Worker process dies; watchdog replaces it; user gets "operation failed, please simplify geometry" |
| CadQuery exception | Caught in worker; returned as structured error with actionable message |
| Claude timeout | SSE stream sends timeout event; user can retry |
| Worker timeout (60s) | Worker killed; user warned about operation complexity |
| Invalid geometry | BRepCheck_Analyzer result returned; agent can suggest fixes |

### Session Management

- Each WebSocket connection represents an editing session
- Intent graph is the session state, persisted server-side (PostgreSQL JSONB)
- Geometry worker assignments are ephemeral — any worker can handle any request
- Claude conversation context maintained per session via Agent SDK

## Consequences

### Positive
- Single service simplifies deployment, monitoring, and debugging
- Process isolation protects the server from OCCT crashes
- Proven tessellation pipeline (ocp-tessellate → three-cad-viewer) reduces implementation risk
- Protocol mix (REST + WebSocket + SSE) matches each communication pattern optimally
- FastAPI's async support handles concurrent WebSocket/SSE connections efficiently
- Evolving to microservices later requires extracting the worker pool — not a rewrite

### Negative / Trade-offs
- Worker communication adds ~10-50ms latency per geometry operation
- Worker pool management (health checks, crash recovery, scaling) is custom code
- FastAPI is single-language (Python) — JavaScript/TypeScript developers can't contribute to the backend without learning Python
- PostgreSQL JSONB is less natural for graph queries than a graph database (acceptable per ADR-008 analysis)

### Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Worker pool becomes bottleneck under load | Implement queue-based autoscaling; add workers dynamically |
| WebSocket connections drop under poor network | Implement reconnect with state recovery from server-side intent graph |
| Claude API costs exceed budget | Reserve-commit pattern with per-user budgets (ADR-010) |
| FastAPI event loop blocked by synchronous code | Use `run_in_executor` for all blocking operations; workers are separate processes |
| ocp-tessellate quality insufficient | Two-level tessellation; fall back to custom tessellation for edge cases |

## Dependencies

- **ADR-001** (Product Scope): Feature set determines which CadQuery operations workers must support
- **ADR-003** (Frontend Stack): Three.js/R3F on the client consumes tessellated geometry from WebSocket
- **ADR-005** (Agentic Workflow): Claude tool definitions and agent loop architecture
- **ADR-008** (Data Model): Intent graph persistence in PostgreSQL JSONB
- **ADR-010** (Security): Worker sandboxing with gVisor/Firecracker, resource limits
