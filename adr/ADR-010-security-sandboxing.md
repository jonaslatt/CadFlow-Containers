# ADR-010: Security, Sandboxing, and Resource Management

## Status
Proposed

## Date
2026-04-07

## Context

CadFlow executes user- and AI-generated CadQuery code on shared infrastructure. This code is arbitrary Python that calls into a C++ geometry kernel (OCCT) which can segfault. The system also makes Claude API calls that cost real money. This ADR addresses three interrelated concerns: how to sandbox code execution safely, how to handle OCCT crashes, and how to manage costs.

Key forces:
- **Python cannot be sandboxed internally.** Its introspective object graph allows escape from any in-process sandbox.
- **OCCT can segfault.** Known crashes in BRepMesh, STEP import, Boolean operations, and filleting. A segfault kills the entire process.
- **Claude API calls cost money.** Haiku is $0.25/M tokens; Opus is $15/M — a 60x range. Uncontrolled usage can bankrupt a small SaaS.
- **User geometry is sensitive IP.** Engineering designs are often trade secrets or subject to export controls.

## Research Findings

### Sandboxing Options

**Docker alone is NOT sufficient for untrusted code.** Containers share the host kernel. Known escape CVEs include CVE-2022-0185 (heap overflow), CVE-2019-5736 (runc overwrite), and CVE-2016-5195 (Dirty COW). Docker with `--privileged` or CAP_SYS_ADMIN gives direct host access. ([Northflank: Sandboxing AI Agents](https://northflank.com/blog/how-to-sandbox-ai-agents))

**Firecracker microVMs** (AWS, Rust): ~125ms boot, <5 MiB overhead, 150+ VMs/sec/host. Each VM has its own kernel. Hardware virtualization fully isolates guest from host. Companion "jailer" for defense-in-depth. ~50K lines of Rust (96% less than QEMU). AWS Lambda and **E2B** (AI sandbox platform) use Firecracker. ([AWS: Firecracker](https://aws.amazon.com/blogs/opensource/firecracker-open-source-secure-fast-microvm-serverless/), [E2B](https://e2b.dev/))

**gVisor** (Google): User-space kernel in Go. Intercepts all syscalls via Sentry component. Only ~70 host syscalls exposed (vs ~300+). 10-30% I/O overhead. OCI-compliant (`runsc`), integrates with Docker and Kubernetes. Native GKE support. ([gVisor Security Model](https://gvisor.dev/docs/architecture_guide/security/))

**nsjail** (Google): Lightweight process isolation via Linux namespaces + seccomp-bpf syscall filtering. Minimal overhead. Good as inner sandbox within a container/microVM. ([nsjail](https://nsjail.dev/))

**Pyodide:** NOT viable for CadFlow. OCCT is a large C++ library that cannot practically run in browser WASM. No threading, limited memory. ([Pyodide Constraints](https://pyodide.org/en/stable/usage/wasm-constraints.html))

### OCCT Memory Safety

Known crash scenarios:
- Segfaults in `BRepMesh_Delaun` (OCCT 7.6.1)
- STEP/IGES import crashes (null curves, degenerated BSplines)
- Boolean operation failures in `BRepAlgoAPI_Fuse`
- Fillet edge cases (fixed in OCCT main, not stable releases)

OCCT's `OSD::SetSignal()` converts some signals (SIGSEGV, SIGFPE) to C++ exceptions, but this is not guaranteed for all crash types. OCP (CadQuery's wrapper) propagates C++ exceptions to Python, but true segfaults kill the process.

**CadQuery threading:** `SetRunParallel(True)` is the default, recruiting all CPU cores. Must limit threads before import:
```python
import OCP
pool = OCP.OSD.OSD_ThreadPool.DefaultPool_s(N_THREADS)
import cadquery as cq
```

Sources: [FreeCAD OCCT crash #25289](https://github.com/freecad/freecad/issues/25289), [CadQuery threading #1600](https://github.com/CadQuery/cadquery/issues/1600)

### AI Cost Control

**Anthropic rate limits:** Token bucket algorithm with RPM, TPM, and daily quota. Tiered; increases with spend. Monthly spend limits available. Usage API provides detailed breakdowns. ([Claude Rate Limits](https://platform.claude.com/docs/en/api/rate-limits))

**Reserve-commit pattern** for budget enforcement:
1. Estimate worst-case cost (input + max_tokens)
2. Reserve budget atomically; deny if insufficient
3. Execute API call
4. Commit actual usage; release unused reservation

Three scopes compose hierarchically: per-user daily, per-run cap, per-tenant monthly. Returns ALLOW, ALLOW_WITH_CAPS, or DENY. ([RunCycles: Budget Limits](https://runcycles.io/blog/openai-api-budget-limits-per-user-per-run-per-tenant))

**Model routing:** Route simple tasks to Haiku ($0.25/M), medium to Sonnet, complex to Opus ($15/M) — 60x cost difference.

### Data Security (Onshape Reference)

Onshape implements: AES-256 at rest, TLS 1.2+ in transit, no local file storage (clients get encrypted visual approximations), granular ACL, SOC 2 Type II audits, full audit logging, continuous pen testing. ([Onshape Security](https://www.onshape.com/en/features/security))

GDPR considerations: data minimization, purpose limitation (no AI training without consent), right to erasure, data portability (STEP export), privacy by design, data residency. ([GDPR for Data Engineers](https://blog.pmunhoz.com/data-engineering/gdpr_data_engineers_guide))

### Concurrent User Scaling

- **Process pool** (not thread pool) for OCCT — each worker is an isolated OS process with cgroup limits
- **KEDA** for Kubernetes event-driven autoscaling based on job queue depth
- **Cloud Run/Lambda** as overflow for burst demand (cold starts 3-10s for OCCT images)
- Warm K8s worker pool for steady-state; serverless overflow for spikes

## Options Considered

### Option A: Docker-Only with Process Isolation

Run each geometry operation in a Docker container. Use Python `multiprocessing` for crash isolation within the container.

- **Pros:** Simple to implement. Docker is well-understood. Process isolation handles OCCT segfaults.
- **Cons:** Docker alone is insufficient for untrusted code (shared kernel, known escapes). No defense-in-depth. A kernel exploit compromises all containers.
- **Real-world precedent:** cadquery2web uses Docker + whitelist validation — reasonable for a demo, not for production multi-tenant.

### Option B: Firecracker microVM per Operation

Every geometry operation runs in its own Firecracker microVM with a fresh CadQuery environment.

- **Pros:** Maximum security — hardware-level isolation per operation. OCCT segfault affects only that VM. No shared kernel attack surface.
- **Cons:** 125ms boot per operation adds latency. Cold start with full CadQuery stack is 3-10s. Operational complexity (KVM required, custom orchestration). Overkill for trusted operations from the backend itself.
- **Real-world precedent:** AWS Lambda (every invocation in a Firecracker VM). E2B provides managed Firecracker sandboxes.

### Option C: Layered Defense-in-Depth (Recommended)

Multiple isolation layers: outer container/VM for infrastructure isolation, inner process isolation for crash safety, nsjail/seccomp for syscall restriction, and code whitelisting for the application layer.

- **Pros:** Each layer mitigates different threats. Inner layers are lightweight (minimal latency). Outer layers provide strong guarantees. Proportionate security — not every operation needs a full VM.
- **Cons:** Multiple layers to configure and maintain. More complex than single-layer approaches.
- **Real-world precedent:** Google's production systems use gVisor + seccomp layered isolation.

## Decision

**Option C: Layered Defense-in-Depth.**

### Security Architecture

```
┌─────────────────────────────────────────────┐
│ Layer 1: Infrastructure Isolation            │
│ Docker + gVisor runtime (runsc)              │
│ OR Firecracker microVM (for multi-tenant)    │
├─────────────────────────────────────────────┤
│ Layer 2: Process Isolation                   │
│ Subprocess per geometry operation            │
│ Watchdog replaces crashed workers            │
├─────────────────────────────────────────────┤
│ Layer 3: Syscall Restriction                 │
│ nsjail or seccomp-bpf filters               │
│ Restrict network, filesystem, IPC            │
├─────────────────────────────────────────────┤
│ Layer 4: Application Sandboxing              │
│ CadQuery code whitelist validation           │
│ Blocked: os, subprocess, socket, importlib   │
│ Allowed: cadquery, math, typing              │
├─────────────────────────────────────────────┤
│ Layer 5: Resource Limits                     │
│ 2-4 OCCT threads, 2GB RAM, 60s timeout      │
│ Enforced via cgroups + rlimits               │
└─────────────────────────────────────────────┘
```

### Phase 1 (MVP): Docker + Process Isolation + Whitelist

- Geometry workers run as subprocesses within a Docker container
- Code whitelist validation (following cadquery2web pattern): block `os`, `subprocess`, `socket`, `importlib`, `__import__`
- Each worker: 2 OCCT threads, 2GB memory limit (cgroups), 60s wall-clock timeout
- Watchdog replaces crashed workers within 1s
- gVisor runtime (`runsc`) for stronger container isolation on supported hosts

### Phase 2 (Multi-tenant): gVisor/Firecracker + nsjail

- gVisor as default container runtime on Kubernetes (native GKE support)
- nsjail within containers for additional syscall filtering
- Evaluate E2B for managed Firecracker sandboxes if density requires it
- Per-user worker isolation (users don't share worker processes)

### OCCT Crash Handling

| Scenario | Detection | Recovery |
|----------|-----------|----------|
| Segfault (SIGSEGV) | Worker process exits with signal | Watchdog spawns replacement; user gets "operation failed" with suggestion to simplify |
| Infinite loop | Wall-clock timeout (60s) | Worker killed via SIGKILL; same recovery |
| Memory exhaustion | OOM killer (cgroup limit) | Worker killed; same recovery |
| CadQuery exception | Caught in worker; returned as error | Structured error with actionable guidance sent to agent/user |
| Boolean failure | BRepAlgoAPI returns error status | Error with suggestion: "Try simplifying operands or using a different Boolean strategy" |

### AI Cost Control Architecture

```
User Request
  → Estimate tokens (input + max_tokens)
  → Reserve budget (per-user daily + per-tenant monthly)
  → Route to model:
      Simple (parameter tweak) → Haiku ($0.25/M)
      Medium (new feature)     → Sonnet ($3/M)
      Complex (design from scratch) → Opus ($15/M)
  → Execute API call (with max_tokens cap)
  → Commit actual usage
  → Release unused reservation
```

**Budget enforcement:**
- Free tier: 50 AI operations/day, Haiku only
- Pro tier: 500 AI operations/day, Sonnet default, Opus for complex tasks
- Circuit breaker: if per-user daily cost exceeds $10, pause AI access and notify
- Monthly per-tenant cap: hard limit prevents runaway costs

### Data Security

- **Encryption:** AES-256 at rest (database, file storage), TLS 1.3 in transit
- **Access control:** Document-level permissions (Owner, Editor, Viewer). Instant revocation.
- **Audit logging:** All geometry operations, AI interactions, exports logged with user, timestamp, operation type
- **Data portability:** STEP and BREP export for all user models (GDPR compliance)
- **Right to erasure:** Hard delete of all user data (geometry, intent graphs, conversation history) on request
- **AI training:** User geometry is NEVER used for AI training without explicit opt-in consent
- **Data residency:** EU-region deployment from day one (AWS eu-central-1 Frankfurt or eu-west-1 Ireland). All user geometry, intent graphs, and PII stored in EU. Verify Anthropic's Claude API data processing terms for EU compliance (data processing addendum, sub-processor list).

### Concurrent User Architecture

```
Load Balancer
  → FastAPI (multiple replicas)
      → Job Queue (Redis)
          → Geometry Worker Pool (K8s pods, autoscaled via KEDA)
              ├── Worker Pod 1 (gVisor, 2 OCCT threads, 2GB)
              ├── Worker Pod 2
              └── Worker Pod N (scaled by queue depth)
```

- **Steady state:** K8s worker pool with warm workers (sub-second dispatch)
- **Burst:** KEDA autoscaler adds workers when queue depth > threshold
- **Priority:** Pro tier jobs dispatched before Free tier
- **Scale-to-zero:** Worker pods scale down after 10 minutes of idle (cost control)

## Consequences

### Positive
- Layered isolation means no single vulnerability compromises the system
- Process isolation handles OCCT segfaults without server downtime
- Code whitelisting blocks the most common attack vectors immediately
- Reserve-commit pattern prevents runaway AI costs
- Model routing optimizes cost without sacrificing capability
- Architecture scales from single-user to multi-tenant without redesign

### Negative / Trade-offs
- Multiple isolation layers add configuration complexity
- gVisor adds 10-30% I/O overhead (acceptable for geometry computation)
- Code whitelisting may block legitimate CadQuery patterns (escape hatch: vetted code can bypass)
- Budget management adds UX friction for free tier users
- Audit logging increases storage requirements

### Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Code whitelist too restrictive | Maintain an allowed-list that grows with user feedback; escape hatch for admin-approved code |
| gVisor incompatibility with OCCT | Test thoroughly; fall back to Docker + nsjail if needed |
| Worker pool exhaustion under load | KEDA autoscaling + queue-based admission control; reject requests when queue full |
| AI cost budget depleted mid-session | Graceful degradation: disable AI, allow manual CAD operations |
| Data breach | Encryption at rest + in transit, minimal data retention, regular pen testing |

## Dependencies

- **ADR-004** (Backend): Worker pool architecture, FastAPI integration
- **ADR-005** (Agentic Workflow): AI cost control affects agent autonomy levels
- **ADR-007** (Dev Process): CI/CD must include security scanning
- **ADR-011** (Billing): Cost control architecture feeds into billing/credit system
