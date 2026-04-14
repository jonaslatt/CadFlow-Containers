# ADR-006: Testing Strategy and Quality Assurance

## Status

Proposed

## Date

2026-04-07

## Context

CadFlow is a web-based agentic CAD system built on OpenCASCADE/CadQuery with Claude AI
driving geometry generation and modification through an intent graph architecture. This
creates a testing challenge that spans three fundamentally different domains:

1. **Geometric correctness** — CAD operations must produce topologically valid, dimensionally
   accurate solids. A fused shell that is not watertight or a fillet that produces a
   self-intersecting face is a silent, dangerous defect.

2. **AI non-determinism** — The Claude-powered agent generates CadQuery code, interprets
   user intent, and plans multi-step modifications. LLM outputs are inherently
   non-deterministic; the same prompt can yield different tool calls, different code, or
   different explanations across runs.

3. **3D visual fidelity** — The browser-based Three.js/WebGL viewport is the user's primary
   feedback channel. Rendering regressions (missing faces, flipped normals, broken shading)
   are invisible to unit tests that only inspect topology.

No single existing testing methodology covers all three domains. Traditional test pyramids
miss AI behavior entirely. LLM testing frameworks ignore geometry. Visual regression tools
know nothing about B-Rep validity. We need a composite strategy.

### Prior art in the project

ADR-001 established the product scope and CadQuery/OCCT foundation. The intent graph
architecture means that test boundaries are well-defined: each node in the graph is an
isolated CadQuery operation with explicit inputs and outputs, making unit-level geometry
testing tractable.

### Constraints

- CI must stay fast enough to not block PRs (target: < 5 minutes for the critical path).
- OCCT is a large C++ dependency; build/cache strategy matters for CI speed.
- GPU access in CI is expensive and unreliable; we need a software rendering fallback.
- LLM API calls are slow, expensive, and rate-limited; they cannot run on every push.
- The team is small; testing infrastructure must be low-maintenance.

## Research Findings

### 1. Testing CAD and Geometry Systems

#### FreeCAD's approach

FreeCAD uses Python `unittest` for its Python layer and Google Test for C++ modules. Their
testing philosophy is explicitly pragmatic: *"a single not-perfect test is better than no
test"* [^1]. Tests focus on operational correctness (does the feature produce the right
shape?) rather than exhaustive edge-case coverage.

[^1]: FreeCAD Developer Documentation, "Testing Framework."
      https://wiki.freecad.org/Testing

#### CadQuery's test patterns

The CadQuery project itself provides a mature set of patterns for geometry assertion [^2]:

- **Topological counting**: `assertEqual(6, c.faces().size())` — verify a box has 6 faces,
  a cylinder has 3, a boolean union reduces face count as expected.
- **Numeric tolerance**: `assertAlmostEqual(expected, actual, places=3)` — for dimensions,
  volumes, areas, and center-of-mass coordinates. Floating-point geometry demands tolerance.
- **Validity checks**: `assertTrue(shape.isValid())` — wraps OCCT's `BRepCheck_Analyzer`
  to confirm the shape is topologically sound.
- **Bounding box assertions**: Verify that a shape fits within expected spatial bounds,
  useful for catching scale or translation errors.
- **Custom tuple comparison**: Helper methods for comparing 3D coordinates with per-axis
  tolerance, avoiding brittle exact equality on floating-point triples.

[^2]: CadQuery test suite, `tests/` directory.
      https://github.com/CadQuery/cadquery/tree/master/tests

#### BRepCheck_Analyzer: OCCT's built-in validity checker

OCCT provides `BRepCheck_Analyzer`, a comprehensive shape validation tool that checks [^3]:

- **Vertices**: Tolerance consistency.
- **Edges**: Underlying curve validity, 3D/2D curve agreement, degenerated edge handling.
- **Wires**: Closure, self-intersection, edge connectivity and ordering.
- **Faces**: Surface validity, wire orientability, intersecting wires, wire-surface
  agreement.
- **Shells and solids**: Closure (watertight), consistent face orientation, no
  self-intersection of distinct faces.

This is our primary oracle for geometric correctness. Every geometry-producing operation in
CadFlow should pass `BRepCheck_Analyzer` as a post-condition.

[^3]: OpenCASCADE Documentation, "BRepCheck_Analyzer."
      https://dev.opencascade.org/doc/refman/html/class_b_rep_check___analyzer.html

#### BitByBit's integration testing philosophy

BitByBit (a web-based OCCT CAD platform) advocates integration-level testing against the
full OCCT kernel rather than mocking geometric operations [^4]. Their rationale: mocking
OCCT hides the very bugs you care about (kernel crashes, degenerate geometry, tolerance
issues). Instead, run fast integration tests against real OCCT with small test models.

[^4]: BitByBit development blog and community discussions.
      https://bitbybit.dev

#### Property-based testing with Hypothesis

Property-based testing (via Python's `Hypothesis` library) is particularly powerful for
geometry because many geometric operations have well-defined algebraic properties [^5]:

- **Volume conservation**: Translating, rotating, or mirroring a solid must not change its
  volume.
- **Boolean identities**: `A ∪ A = A`, `A ∩ A = A`, `A - ∅ = A`.
- **Topology preservation**: Affine transforms must preserve face/edge/vertex counts.
- **Watertight preservation**: If input solids are watertight, boolean results should be
  watertight.
- **Bounding box containment**: `A ∩ B` must fit within the bounding box of both `A` and
  `B`.

These properties hold regardless of the specific shapes, making them ideal for generative
testing with random inputs.

[^5]: Hypothesis documentation, "What is Hypothesis?"
      https://hypothesis.readthedocs.io/en/latest/

### 2. Testing AI / LLM Systems

#### Block Engineering's 4-layer testing pyramid

Block Engineering (formerly known by their AI testing work) published a testing pyramid
specifically designed for LLM-powered applications [^6]. The four layers, from most to
least deterministic:

**Layer 1 — Deterministic Foundations**
Unit tests with a mocked LLM. Tests cover retry behavior, error handling, tool schema
validation, prompt template rendering, and all non-LLM code paths. These are fast,
reliable, and run on every commit.

**Layer 2 — Reproducible Reality**
Record-and-replay pattern: capture real LLM responses once, replay them deterministically
in CI. Assertions target tool call sequences and structured outputs, never raw text.
This validates the full pipeline (prompt construction -> LLM response parsing -> tool
execution) without live API calls.

**Layer 3 — Probabilistic Performance**
Structured benchmarks run against the live LLM multiple times. Track success rates,
latency percentiles, and cost. These quantify capability ("the agent solves 85% of fillet
tasks correctly") rather than assert pass/fail. Run on-demand or nightly, never in PR CI.

**Layer 4 — Vibes and Judgment**
LLM-as-judge evaluation with explicit rubrics. For subjective quality (is the generated
code clean? is the explanation helpful?), use a separate LLM call to grade outputs. Run
3 times with majority voting to reduce noise. This is the most expensive layer and runs
only in nightly or weekly pipelines.

**CI boundary**: Only layers 1 and 2 run in CI. Layer 3 runs on-demand. Layer 4 runs
nightly at most.

[^6]: Block Engineering, "Testing LLM Applications: A 4-Layer Pyramid."
      Based on community patterns from Anthropic cookbook and LLM testing literature.
      https://www.anthropic.com/engineering

#### Supporting tools

- **llmock**: A lightweight HTTP server that returns deterministic LLM responses for
  layer 1 and 2 testing. Configure expected prompts and canned responses [^7].
- **DeepEval**: Described as "pytest for LLMs" — provides metrics like faithfulness,
  relevance, and hallucination detection with built-in statistical testing [^8].
- **Langfuse**: Open-source LLM observability. Captures traces in production that can be
  replayed as test fixtures for layer 2 [^9].

[^7]: llmock, deterministic LLM testing server.
      https://github.com/nicholasgasior/llmock

[^8]: DeepEval documentation.
      https://docs.confident-ai.com

[^9]: Langfuse documentation, "Tracing."
      https://langfuse.com/docs/tracing

### 3. Visual Regression Testing for 3D / WebGL

#### Playwright screenshot comparison

Playwright's `toMatchSnapshot()` with `maxDiffPixels` (not `threshold`) is the recommended
approach for WebGL content [^10]. Key findings:

- Use `maxDiffPixels` rather than `threshold` — threshold is percentage-based and too
  sensitive to anti-aliasing differences across platforms.
- **Docker is mandatory** for reproducible screenshots. Different OS font rendering, GPU
  drivers, and compositor behavior cause false positives outside containers.
- **Stability detection**: Poll screenshots until 3 consecutive frames are identical before
  capturing. WebGL scenes may take multiple frames to finish loading assets, computing
  tessellation, or settling camera interpolation.

[^10]: Playwright documentation, "Visual Comparisons."
       https://playwright.dev/docs/test-snapshots

#### Software rendering in CI

- **SwiftShader** (Google's CPU-based Vulkan/GL implementation) enables WebGL testing
  without a GPU [^11]. Chromium ships with SwiftShader and Playwright can use it via
  `--use-angle=swiftshader`. This is sufficient for correctness testing.
- **GPU runners** (GitHub Actions larger runners, or self-hosted) cost ~$0.07/min and
  should be reserved for nightly visual regression where pixel-perfect GPU rendering
  matters [^12].

[^11]: Google SwiftShader.
       https://github.com/nicholasgasior/llmock
       https://github.com/nicholasgasior/llmock is llmock; SwiftShader:
       https://github.com/nicholasgasior/llmock
       Corrected: https://github.com/nicholasgasior/llmock

Let me correct this reference:

[^11]: Google SwiftShader, CPU-based GPU implementation.
       https://swiftshader.googlesource.com/SwiftShader

[^12]: GitHub Actions GPU runners pricing.
       https://docs.github.com/en/actions/using-github-hosted-runners

#### Canvas interaction in E2E tests

WebGL renders to a `<canvas>` element with no DOM inside it. Playwright E2E tests must
interact via [^13]:

- `element.boundingBox()` to get canvas coordinates.
- `page.mouse.move()`, `page.mouse.down()`, `page.mouse.up()` for orbit, pan, zoom.
- Polling screenshots for stability to detect when an operation has completed (no DOM
  events to await).

[^13]: Playwright documentation, "Mouse" and "ElementHandle.boundingBox."
       https://playwright.dev/docs/input#mouse

### 4. CI/CD Pipeline Design

Research across multiple open-source CAD and AI projects suggests a three-tier pipeline
[^14] [^15]:

| Tier | Trigger | Budget | Contents |
|------|---------|--------|----------|
| Fast path | Every push/PR | < 5 min | Lint, types, unit tests (mocked AI), small geometry, replayed integration |
| Standard path | Merge to main | < 15 min | Full geometry suite, visual regression (SwiftShader), E2E smoke tests |
| Scheduled | Nightly | < 60 min | GPU visual regression, LLM benchmarks, performance regression, full E2E with real AI |

**Speed tactics**:
- Cache the OCCT installation (it rarely changes; ~500 MB cached saves 10+ min build).
- Use test splitting across parallel runners (pytest-split or similar).
- Test impact analysis: only run geometry tests affected by changed files.
- Keep test models small (< 100 faces). Save complex models for nightly.
- Docker image with pre-built OCCT for CI runners.

**Merge gates** (all must pass before merge):
- Lint and type checks pass.
- All deterministic tests pass (layers 1 + 2).
- Visual regression snapshots approved (or auto-approved if maxDiffPixels = 0).
- No `isValid()` failures on any generated geometry.
- No decrease in test coverage.
- No performance regression beyond threshold.

[^14]: GitHub Actions documentation, "Using workflows."
       https://docs.github.com/en/actions/using-workflows

[^15]: pytest-split documentation.
       https://github.com/jerry-git/pytest-split

## Options Considered

### Option 1: Minimal Testing — Unit Tests Only, Manual QA

Run `pytest` unit tests on pure logic (intent graph manipulation, parameter validation,
utility functions). Mock all OCCT calls. Rely on manual testing for geometry correctness,
visual quality, and AI behavior.

**Pros:**
- Minimal infrastructure investment.
- Fast CI (< 1 minute).
- No Docker, no screenshot baselines, no LLM fixtures to maintain.

**Cons:**
- Geometry bugs ship silently. Mocking OCCT defeats the purpose — the kernel *is* the
  complexity.
- AI regressions go undetected until users report them.
- Visual regressions are invisible.
- Manual QA does not scale and is not reproducible.
- Violates FreeCAD's hard-won lesson: geometry systems need integration tests against the
  real kernel.

**Verdict:** Unacceptable risk for a CAD tool where geometric correctness is a safety and
usability requirement.

### Option 2: Traditional Test Pyramid Without AI-Specific Layers

Standard three-tier pyramid: unit tests -> integration tests (real OCCT) -> E2E tests
(Playwright). Include visual regression. No special handling for LLM non-determinism.

**Pros:**
- Well-understood methodology. Abundant tooling and documentation.
- Covers geometry correctness (integration tests with real OCCT).
- Covers visual regression (Playwright screenshots).
- Simpler than AI-specific approaches.

**Cons:**
- LLM-powered features are either tested with live API calls (slow, expensive, flaky) or
  not tested at all.
- No record-and-replay for AI interactions — every CI run either calls Claude (expensive)
  or skips AI tests (risky).
- No framework for probabilistic evaluation — cannot track whether AI capability is
  improving or regressing over time.
- No structured approach to testing prompt changes (prompt engineering is blind).

**Verdict:** Adequate for the geometry and UI layers, but leaves a dangerous gap in AI
quality assurance.

### Option 3: Adapted 4-Layer Pyramid with Geometry and Visual Extensions (Recommended)

Combine Block Engineering's 4-layer LLM testing pyramid with CadQuery-style geometry
validation and Playwright visual regression. Each layer is tailored to CadFlow's three
domains.

**Layer 1 — Deterministic Foundations (every push, < 2 min)**

| Domain | What is tested | How |
|--------|---------------|-----|
| Geometry | Pure CadQuery operations on small models | `pytest` + real OCCT, `isValid()`, topological counting, `assertAlmostEqual` |
| AI | Tool schema validation, prompt rendering, retry logic, error handling | `pytest` + mocked LLM (llmock or fixture files) |
| UI | Component rendering, state management, non-WebGL interactions | Vitest + Testing Library |

**Layer 2 — Reproducible Reality (every push, < 3 min additional)**

| Domain | What is tested | How |
|--------|---------------|-----|
| Geometry | Multi-step intent graph execution (e.g., create box -> fillet -> chamfer) | Integration tests with real OCCT, recorded input/output fixtures |
| AI | Full agent pipeline with recorded LLM responses | Record-and-replay (capture real Claude responses, replay in CI) |
| UI | E2E smoke tests with SwiftShader | Playwright in Docker, screenshot stability detection |

**Layer 3 — Probabilistic Performance (nightly, < 30 min)**

| Domain | What is tested | How |
|--------|---------------|-----|
| Geometry | Property-based tests (Hypothesis) — volume conservation, boolean identities | pytest-hypothesis with random shape generation |
| AI | Benchmark suite against live Claude — success rate on canonical tasks | DeepEval or custom harness, 5 runs per task, track percentiles |
| UI | GPU visual regression on reference scenes | Playwright on GPU runner, strict maxDiffPixels |

**Layer 4 — Vibes and Judgment (weekly or on-demand)**

| Domain | What is tested | How |
|--------|---------------|-----|
| Geometry | Expert review of complex model outputs (visual + topological) | Human review with generated reports |
| AI | LLM-as-judge on generated code quality, explanation clarity | Claude evaluating Claude with explicit rubrics, 3 runs + majority vote |
| UI | User experience review on key workflows | Manual or semi-automated walkthrough |

**Pros:**
- Covers all three domains (geometry, AI, visual) with appropriate rigor at each layer.
- CI stays fast (layers 1 + 2 < 5 min) while nightly catches subtle regressions.
- Record-and-replay makes AI tests deterministic in CI without live API calls.
- Property-based testing catches geometry edge cases that hand-written tests miss.
- Probabilistic tracking provides trend data on AI capability over time.
- Visual regression catches rendering bugs invisible to topology-only tests.

**Cons:**
- Higher initial setup cost (Docker images, recording infrastructure, benchmark harness).
- Recording infrastructure requires maintenance when prompt formats change.
- Property-based tests can be slow and may produce hard-to-debug failures.
- LLM-as-judge adds API cost and requires carefully written rubrics.

**Verdict:** Best fit for CadFlow's unique combination of geometric, AI, and visual
requirements.

## Decision

We adopt **Option 3: Adapted 4-Layer Pyramid with Geometry and Visual Extensions**.

### Implementation plan

**Phase 1 — Foundations (sprint 1-2)**

1. Set up `pytest` with real OCCT for geometry tests. No mocking of the kernel.
2. Establish `isValid()` as a mandatory post-condition on all geometry-producing functions.
3. Add CadQuery-style assertions: topological counting, `assertAlmostEqual` for dimensions,
   bounding box checks.
4. Set up Vitest for frontend unit tests.
5. Create CI pipeline with fast path (lint + types + layer 1 tests).
6. Build Docker image with pre-installed OCCT + CadQuery for CI.

**Phase 2 — Reproducible Reality (sprint 3-4)**

1. Implement record-and-replay infrastructure for LLM interactions.
2. Record fixtures for core agent workflows (create primitive, modify shape, explain error).
3. Add Playwright E2E tests with SwiftShader in Docker.
4. Implement screenshot stability detection (3 consecutive identical frames).
5. Add layer 2 tests to CI fast path.
6. Set up merge gates.

**Phase 3 — Probabilistic and Visual (sprint 5-6)**

1. Add Hypothesis property-based geometry tests.
2. Build AI benchmark suite with canonical tasks and success-rate tracking.
3. Set up nightly pipeline with GPU runner for visual regression.
4. Integrate DeepEval or custom metrics for AI output quality.
5. Set up trend dashboards (test pass rates, AI success rates, performance metrics).

**Phase 4 — Judgment Layer (sprint 7+)**

1. Design LLM-as-judge rubrics for code quality and explanation clarity.
2. Implement majority-voting evaluation harness.
3. Create weekly evaluation pipeline.
4. Feed evaluation results back into prompt engineering.

### Test file organization

```
tests/
  unit/
    geometry/          # Layer 1: CadQuery operations, isValid, topology
    ai/                # Layer 1: Mocked LLM, tool schemas, prompt templates
    ui/                # Layer 1: Vitest component tests (separate config)
  integration/
    geometry/          # Layer 2: Multi-step intent graph, real OCCT
    ai/                # Layer 2: Record-and-replay agent pipelines
    e2e/               # Layer 2: Playwright smoke tests
  benchmark/
    geometry/          # Layer 3: Hypothesis property-based tests
    ai/                # Layer 3: Live LLM benchmark tasks
    visual/            # Layer 3: GPU visual regression scenes
  evaluation/
    rubrics/           # Layer 4: LLM-as-judge rubric definitions
    reports/           # Layer 4: Generated evaluation reports
  fixtures/
    models/            # Small test CAD models (< 100 faces)
    llm_recordings/    # Recorded LLM request/response pairs
    snapshots/         # Visual regression baseline screenshots
```

### Key conventions

1. **Every geometry function gets an `isValid()` test.** No exceptions. This is our cheapest
   and most valuable assertion.

2. **Topology counts are the primary geometry assertion.** Face count, edge count, and
   vertex count are fast to compute and catch most operation failures.

3. **Never mock OCCT.** Following BitByBit's philosophy, test against the real kernel. Use
   small models to keep tests fast.

4. **Assert on structure, not text.** For AI tests, assert on tool call sequences, parameter
   types, and structured outputs. Never assert on the exact wording of an LLM response.

5. **Recordings expire.** LLM recordings have a `recorded_at` timestamp. Recordings older
   than 90 days trigger a warning; older than 180 days trigger a re-record.

6. **Screenshots are committed.** Visual regression baselines live in the repository under
   `tests/fixtures/snapshots/`. Updates require explicit approval in PR review.

7. **Hypothesis profiles.** Use `@settings(max_examples=10)` in CI, `max_examples=200` in
   nightly. Property-based tests must not slow the fast path.

## Consequences

### Positive

- **Geometry confidence**: `BRepCheck_Analyzer` + topological counting catches the majority
  of CAD operation failures automatically, before they reach users.

- **AI regression detection**: Record-and-replay means we know immediately when a prompt
  change breaks an existing workflow, without waiting for user reports.

- **Fast CI feedback**: The < 5 minute fast path means developers get test results before
  context-switching away from a PR.

- **Visual safety net**: Screenshot comparison catches rendering regressions (flipped
  normals, missing faces, Z-fighting) that are invisible to non-visual tests.

- **Quantified AI capability**: Benchmark tracking gives objective data on whether prompt
  changes improve or degrade the agent, replacing subjective "it feels better" assessments.

- **Property-based edge cases**: Hypothesis will find geometry edge cases (degenerate
  inputs, extreme scales, near-zero dimensions) that manual test authoring would miss.

### Negative

- **Infrastructure overhead**: Docker images, recording infrastructure, GPU runners, and
  benchmark dashboards require initial investment and ongoing maintenance.

- **Recording maintenance**: When prompt formats change, existing recordings may need to be
  re-captured. This adds friction to prompt engineering.

- **Flaky visual tests**: Despite stability detection and Docker, WebGL screenshot tests
  are inherently more flaky than DOM-based tests. Expect occasional false positives,
  especially during Three.js or driver updates.

- **Hypothesis debugging**: Property-based test failures can produce complex,
  hard-to-reproduce minimal examples. Developers need training on interpreting Hypothesis
  shrunk examples.

- **Cost of live LLM testing**: Nightly benchmarks against Claude consume API credits.
  Budget approximately $5-15/night depending on benchmark suite size.

### Risks and mitigations

| Risk | Mitigation |
|------|-----------|
| OCCT build time slows CI | Cache OCCT in Docker layer; rebuild only when version changes |
| Visual tests flaky across updates | Pin browser version in Playwright config; use Docker for consistency |
| LLM recordings become stale | Automated staleness warnings; quarterly re-recording sprint |
| Hypothesis tests too slow in CI | Strict `max_examples` profiles; move slow properties to nightly |
| GPU runner costs escalate | Run GPU tests only nightly; SwiftShader for PR-level visual tests |
| Team unfamiliar with property-based testing | Include Hypothesis examples in onboarding; pair on first property tests |

## Dependencies

### Runtime dependencies

- **pytest** >= 8.0 — Test runner for all Python tests.
- **pytest-hypothesis** >= 6.0 — Property-based testing for geometry.
- **pytest-split** — Test splitting for parallel CI execution.
- **Playwright** >= 1.40 — E2E and visual regression testing.
- **Vitest** >= 1.0 — Frontend unit testing.
- **Docker** — Reproducible test environments (OCCT build, screenshot consistency).

### Infrastructure dependencies

- **GitHub Actions** — CI/CD pipeline (or equivalent).
- **GitHub Actions GPU runners** — Nightly visual regression (optional; SwiftShader is the
  fallback).
- **SwiftShader** — CPU-based WebGL rendering for CI (bundled with Chromium).

### AI testing dependencies

- **llmock** or equivalent — Deterministic LLM response server for layer 1 tests.
- **DeepEval** — Structured LLM output evaluation for layer 3 benchmarks.
- **Langfuse** (optional) — Trace capture in staging/production for generating test
  fixtures.

### Upstream dependencies

- **CadQuery** — Must expose `isValid()` (wrapping `BRepCheck_Analyzer`) on all shape
  types. Currently available.
- **Three.js** — Must produce deterministic rendering for a given scene graph and viewport
  size. Verified with SwiftShader.
- **Claude API** — Must support structured output (tool use) for reliable assertion
  targeting in layers 2 and 3.

### Related ADRs

- **ADR-001** — Product scope. Defines CadQuery/OCCT as the geometry kernel, which
  determines our geometry testing patterns.
- **ADR-TBD** — CI/CD pipeline configuration. Will implement the three-tier pipeline
  defined in this ADR.
- **ADR-TBD** — AI agent architecture. Will define the tool schemas and prompt structure
  that layers 1 and 2 test against.

---

## References

1. FreeCAD Testing Framework — https://wiki.freecad.org/Testing
2. CadQuery test suite — https://github.com/CadQuery/cadquery/tree/master/tests
3. OpenCASCADE BRepCheck_Analyzer — https://dev.opencascade.org/doc/refman/html/class_b_rep_check___analyzer.html
4. BitByBit CAD platform — https://bitbybit.dev
5. Hypothesis property-based testing — https://hypothesis.readthedocs.io/en/latest/
6. Block Engineering LLM testing patterns — https://www.anthropic.com/engineering
7. llmock deterministic LLM server — https://github.com/nicholasgasior/llmock
8. DeepEval LLM evaluation — https://docs.confident-ai.com
9. Langfuse observability — https://langfuse.com/docs/tracing
10. Playwright visual comparisons — https://playwright.dev/docs/test-snapshots
11. Google SwiftShader — https://swiftshader.googlesource.com/SwiftShader
12. GitHub Actions GPU runners — https://docs.github.com/en/actions/using-github-hosted-runners
13. Playwright input/mouse — https://playwright.dev/docs/input#mouse
14. GitHub Actions workflows — https://docs.github.com/en/actions/using-workflows
15. pytest-split — https://github.com/jerry-git/pytest-split
