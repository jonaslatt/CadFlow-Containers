# ADR-007: Software Development Process and AI-Assisted Development

## Status

Proposed

## Date

2026-04-07

## Context

CadFlow is a web-based agentic CAD tool built on OpenCASCADE/CadQuery with Claude AI
for intelligent geometry manipulation and CFD preprocessing. The project faces a
fundamental question: how should a small team develop a complex, multi-domain
application (3D CAD, AI agents, CFD) while maximizing the leverage that AI-assisted
development tools provide?

Traditional software development processes were designed around human-only teams with
known velocity constraints. The introduction of Claude Code and similar AI coding
assistants fundamentally changes the equation: implementation speed increases
dramatically, but architectural coherence, test coverage, and code quality require
even more discipline to maintain. Without a deliberate process, the speed gains from
AI can amplify technical debt faster than they deliver value.

The CadFlow codebase spans multiple domains:

- **3D geometry kernel** (CadQuery/OpenCASCADE): Parametric modeling, B-Rep operations
- **Web frontend** (React/Three.js): 3D viewer, feature tree, interactive selection
- **AI agent layer**: Intent graph, natural language to geometry, parametric editing
- **CFD preprocessing**: Meshing, boundary conditions, domain extraction, solver export
- **Infrastructure**: Container orchestration, REST API, real-time communication

Each domain has different testing strategies, different rates of change, and different
risk profiles. The development process must accommodate all of them while keeping the
team productive and the architecture sound.

### Key Questions

1. How do we structure the repository for AI-tool visibility and developer ergonomics?
2. What git workflow balances speed with quality for a small AI-augmented team?
3. How do we configure Claude Code for maximum effectiveness across all domains?
4. What development cadence and phasing keeps scope manageable while building toward
   the full vision?
5. How do we prevent AI-generated code from introducing architectural drift?

## Research Findings

### Claude Code Best Practices

The recommended Claude Code workflow follows a four-phase loop [1]:

1. **Explore** -- Let Claude read the codebase, understand patterns, identify relevant
   files. Use subagents for investigation tasks that require reading many files.
2. **Plan** -- Ask Claude to propose an approach before writing code. Review the plan
   for architectural alignment before proceeding.
3. **Implement** -- Execute the plan incrementally. Give Claude explicit verification
   criteria: tests to pass, expected outputs, screenshots to match.
4. **Commit** -- Review changes, run tests, commit with conventional messages and
   AI attribution trailers.

CLAUDE.md configuration is critical for consistent AI behavior [1][2]:

- **Budget**: ~150-200 instructions, under 300 lines total. Larger files dilute
  signal and waste context on every interaction.
- **Include**: Build/test commands, code style rules, repository etiquette,
  key architecture decisions, file naming conventions.
- **Exclude**: Anything Claude can determine by reading the code itself (e.g.,
  "this is a React app" when package.json contains react).
- **Progressive disclosure**: Use `.claude/skills/` for domain-specific knowledge
  that is loaded on demand, not on every interaction. This is ideal for CadFlow
  where CadQuery API knowledge, Three.js patterns, and CFD terminology are only
  relevant to specific tasks.

Session management matters for quality [1]:

- `/clear` between unrelated tasks to prevent context pollution.
- Subagents for investigation -- a fresh context that reports findings back without
  bloating the main session.
- Git worktrees for parallel AI development -- multiple Claude sessions working on
  different features simultaneously without branch conflicts.

The **Writer/Reviewer pattern** is strongly recommended [2]: use one Claude session
to write code, then a fresh session to review it. The reviewing session has no
sunk-cost bias toward the implementation and will catch issues the writing session
glosses over.

### Monorepo Structure

AI coding tools strongly favor monorepo structures [3][4]:

- **Full context visibility**: Claude can see the API contract, the frontend consumer,
  and the backend implementation in a single session. Cross-stack changes become
  atomic rather than coordinated across repositories.
- **Pattern recognition**: Consistent patterns across packages are easier for AI to
  learn and replicate when all code lives together.
- **Simplified dependency management**: Internal packages reference each other
  directly rather than through published versions.

For small teams, pnpm workspaces combined with Turborepo is the recommended
toolchain [4][5]:

- **pnpm**: Efficient disk usage via content-addressable storage, strict dependency
  isolation, native workspace protocol.
- **Turborepo**: Build orchestration with dependency-aware task scheduling, remote
  caching, incremental builds. Low configuration overhead compared to Nx or Bazel.
- **Package structure**: `packages/` for shared libraries, `apps/` for deployable
  services, clear dependency graph.

### Git Workflow

**GitHub Flow** is the right fit for a small team [6][7]:

- `main` is always deployable.
- Short-lived feature branches (`feat/intent-graph`, `fix/viewer-memory-leak`).
- Pull requests for all changes, even AI-generated ones.
- No long-lived develop/staging branches that create merge overhead.

**Conventional Commits** provide machine-readable commit history [8]:

```
type(scope): description

feat(agent): add intent graph traversal for boolean operations
fix(viewer): resolve memory leak in tessellation worker
refactor(api): extract geometry validation middleware
docs(adr): add ADR-007 development process
test(cfd): add boundary condition assignment tests
```

AI attribution is handled via Git trailers [1][2]:

```
Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
```

This preserves provenance without cluttering the commit message. It also enables
future analysis of AI-assisted vs. human-only contributions.

**Code review follows a three-tier model** [2][9]:

1. **Automated checks**: Linting, type checking, test suite, build verification.
   These run in CI on every push and must pass before any review.
2. **AI review**: Tools like CodeRabbit or a dedicated Claude reviewer session
   examine the diff for bugs, style violations, and missed edge cases. This catches
   the majority of mechanical issues.
3. **Human review**: Focuses on architecture alignment, business logic correctness,
   security implications, and UX decisions. Humans review what AI cannot: intent,
   trade-offs, and strategic direction.

The cardinal rule: **AI proposes, AI never owns**. Every merge requires human
approval. AI review augments but never replaces human judgment on architectural
and business decisions.

### Claude Code Extensions

Claude Code supports several extension mechanisms that CadFlow should leverage [1][10]:

**MCP Servers** -- Model Context Protocol servers provide Claude with live access to
external systems:

- **GitHub MCP**: Read issues, PRs, reviews, and CI status without leaving the
  coding session. Enables "fix the failing test from PR #42" workflows.
- **PostgreSQL/SQLite MCP**: Direct database access for debugging data issues or
  generating migrations.
- **File System MCP**: Structured access to project files with permission boundaries.
- **Memory MCP**: Persistent key-value storage across sessions for project context
  that does not fit in CLAUDE.md.

**Skills** (`.claude/skills/`) -- Domain-specific knowledge loaded on demand [1]:

```yaml
---
name: cadquery-modeling
description: CadQuery/OpenCASCADE modeling patterns for CadFlow
globs: ["packages/kernel/**", "**/*.cq.py"]
---
# CadQuery Modeling Conventions
- All geometry operations return new Workplane objects (immutable pattern)
- Use selectors for face/edge/vertex picking: >Z, <X, |Y, #XY
- ...
```

Skills are ideal for CadFlow's multi-domain nature. A `cadquery-modeling` skill,
a `threejs-viewer` skill, and a `cfd-preprocessing` skill each load only when
Claude is working in that domain.

**Custom Subagents** (`.claude/agents/`) -- Dedicated assistants with their own
system prompts and tool access [1]:

- `reviewer.md`: Code review agent with architecture guidelines.
- `test-writer.md`: Test generation agent with coverage requirements.
- `cfd-expert.md`: Domain expert for CFD preprocessing decisions.

**Hooks** (`settings.json`) -- Deterministic scripts triggered at workflow points [1]:

- Pre-commit: Run linters, formatters, type checks.
- Post-commit: Update changelog, notify team.
- Pre-push: Run full test suite, check for secrets.

Hooks are not AI -- they are regular scripts that execute reliably every time,
providing guardrails that AI behavior alone cannot guarantee.

### ADR-Driven Development

The "Vibe ADR" workflow integrates architectural decision records with AI-assisted
implementation [11][12]:

1. **Define**: Identify the decision to be made. Write the context and constraints.
2. **Draft ADR**: Research options, evaluate trade-offs, propose a decision. The ADR
   itself becomes the prompt context for implementation.
3. **Implement with AI**: Feed the ADR to Claude as context. The decision rationale
   guides implementation choices without constant human re-explanation.
4. **Review**: Fresh Claude session reviews implementation against the ADR. Does the
   code match the stated decision? Are consequences addressed?
5. **Commit and Reset**: Commit the implementation, `/clear` the session, start
   fresh for the next task.

**Test-Driven Development works exceptionally well with AI** [2][13]:

- **Small increments** keep context focused. A single test + implementation cycle
  fits cleanly in Claude's working memory.
- **Immediate feedback** prevents broken code from polluting the session context.
  When tests fail, Claude can see the failure and fix it before moving on.
- **Specification by example**: Tests serve as executable specifications that are
  unambiguous, unlike natural language descriptions.
- **Refactoring safety**: With tests in place, Claude can refactor aggressively
  without fear of breaking behavior.

The TDD + AI loop:

```
Write test (human defines intent) -->
  Run test (expect failure) -->
    Claude implements (minimal code to pass) -->
      Run test (expect pass) -->
        Claude refactors (tests guard behavior) -->
          Commit
```

### Implementation Phasing

CadFlow development is organized into phases that build incrementally on each
other. Each phase delivers a usable product increment [14]:

**Phase 0 -- Foundation** (Weeks 1-4):

- Monorepo setup: pnpm workspaces + Turborepo
- CadQuery container: Docker image with OpenCASCADE, CadQuery, Python API
- Three.js viewer: Basic 3D rendering, orbit controls, grid
- REST API: FastAPI service bridging frontend to CadQuery kernel
- CI/CD: GitHub Actions, automated testing, container builds
- CLAUDE.md + skills: Initial AI development configuration

**Phase 1 -- Agent Integration** (Weeks 5-10):

- Claude integration: Natural language to CadQuery code generation
- Intent graph: DAG of modeling operations with dependency tracking
- Selectors: AI-powered face/edge/vertex selection from descriptions
- Parametric editing: Modify parameters, recompute downstream geometry
- Conversation UI: Chat interface for geometry manipulation

**Phase 2 -- Interactive CAD** (Weeks 11-18):

- 3D selection: Click-to-select faces, edges, vertices in the viewer
- Feature tree: Visual DAG of modeling history with drag-and-drop reorder
- Undo/redo: Operation-level undo via intent graph rollback
- Constraint system: Geometric constraints between features
- Export: STEP, STL, BREP file export

**Phase 3 -- CFD Preprocessing** (Weeks 19-28):

- Meshing: Surface and volume mesh generation via Gmsh integration
- Boundary conditions: AI-assisted BC assignment from descriptions
- Domain extraction: Fluid domain extraction from solid geometry
- Solver export: OpenFOAM, SU2 case file generation
- Validation: Mesh quality checks, BC completeness verification

**Phase 4 -- Production** (Weeks 29+):

- Collaboration: Multi-user editing, presence indicators
- Version control: Git-like versioning for CAD models
- Templates: Parametric template library for common geometries
- Advanced AI: Multi-step reasoning, design optimization suggestions
- Performance: WebGPU rendering, worker-based tessellation

Each phase has a clear definition of done, a test suite that validates the
increment, and an ADR trail documenting key decisions made during implementation.

## Options Considered

### Option 1: Traditional Waterfall with Comprehensive Upfront Design

Write detailed specifications for all components before implementation begins.
Follow a sequential phase gate process: Requirements -> Design -> Implementation
-> Testing -> Deployment.

**Pros:**

- Comprehensive documentation produced before any code is written.
- Clear handoff points between phases.
- Well-understood process with established tooling.

**Cons:**

- Extremely slow for a small team. Months of design before any working software.
- Does not leverage AI acceleration at all. Treats Claude Code as a faster typist
  rather than a development partner.
- Specifications become stale before implementation begins. CAD and CFD domains
  have enough complexity that design assumptions will be invalidated during
  implementation.
- No feedback loop. Problems discovered during implementation require expensive
  rework of upstream design documents.
- Incompatible with the exploratory nature of 3D geometry and AI agent development
  where the right approach often emerges from experimentation.

### Option 2: Pure "Vibe Coding" with Minimal Process

Let Claude Code drive development with minimal upfront planning. Start with a
high-level description and let the AI generate code freely. Accept whatever
architecture emerges.

**Pros:**

- Maximum speed in the short term. Working prototypes within hours.
- Low ceremony. No ADRs, no formal reviews, no phased planning.
- Leverages AI creativity -- Claude may find novel solutions that a rigid plan
  would preclude.

**Cons:**

- **High risk of architectural drift**. Without explicit decisions, each Claude
  session may make different assumptions. The intent graph might use one pattern
  while the viewer uses another. Inconsistency compounds.
- **Technical debt accumulates invisibly**. AI-generated code often works but may
  not be maintainable, testable, or aligned with the project's long-term
  architecture.
- **No institutional memory**. Without ADRs, the team (and future Claude sessions)
  cannot understand why decisions were made. Every session re-derives context from
  code alone.
- **Testing gaps**. Without TDD discipline, AI tends to write code first and tests
  as an afterthought (or not at all). For a CAD kernel, untested geometry
  operations are a ticking time bomb.
- **Context rot**. Long unstructured sessions accumulate stale context. Claude
  starts referencing deleted files, outdated patterns, or abandoned approaches.
- **Security and quality risks**. No review gate means AI hallucinations, insecure
  patterns, and subtle bugs ship directly to main.

### Option 3: ADR-Driven, TDD-First, AI-Augmented Development (Recommended)

Combine structured architectural decision-making (ADRs) with test-driven
development and deliberate AI-assistance practices. Use phases to manage scope
but iterate within each phase using the Explore -> Plan -> Implement -> Commit
loop.

**Pros:**

- **AI leverage with guardrails**. Claude Code accelerates implementation while
  ADRs, tests, and reviews prevent architectural drift.
- **Institutional memory**. ADRs capture decisions and rationale. Future Claude
  sessions can read ADRs to understand constraints without human re-explanation.
- **TDD keeps AI focused**. Small test-first cycles fit naturally in Claude's
  context window. Tests serve as unambiguous specifications.
- **Phased delivery**. Each phase produces a working increment. The team can
  validate direction before investing in the next phase.
- **Scalable process**. Works for a solo developer today and a small team tomorrow.
  ADRs and conventional commits make onboarding straightforward.
- **Monorepo + AI synergy**. Full codebase visibility enables Claude to make
  atomic cross-stack changes with awareness of all consumers.

**Cons:**

- **More ceremony than vibe coding**. Writing ADRs, tests-first, and conducting
  reviews takes time. For a small team, this overhead must be kept lean.
- **Requires discipline**. The process only works if followed consistently. A
  tired developer skipping TDD "just this once" erodes the safety net.
- **Initial setup cost**. Configuring CLAUDE.md, skills, hooks, CI/CD, and the
  monorepo takes time before any feature work begins. (Mitigated by Phase 0
  being explicitly about this setup.)

## Decision

We adopt **Option 3: ADR-Driven, TDD-First, AI-Augmented Development**.

### Core Process

Every feature follows this cycle:

```
1. ADR (if architectural)  -->  Capture decision before implementation
2. Write tests             -->  Define expected behavior as executable specs
3. Explore + Plan          -->  Claude reads context, proposes approach
4. Implement               -->  Claude writes code, tests validate incrementally
5. Review                  -->  Fresh Claude session + human review
6. Commit + Clear          -->  Conventional commit, /clear, move on
```

### Repository Structure

Monorepo with pnpm workspaces and Turborepo:

```
cadflow/
  apps/
    web/               # React + Three.js frontend
    api/               # FastAPI backend
  packages/
    kernel/            # CadQuery/OpenCASCADE wrapper
    agent/             # Claude AI agent layer
    cfd/               # CFD preprocessing
    shared/            # Shared types, utilities
  adr/                 # Architectural Decision Records
  .claude/
    CLAUDE.md          # Global AI instructions (<300 lines)
    skills/            # Domain-specific knowledge
      cadquery.md      # CadQuery patterns and conventions
      threejs.md       # Three.js viewer patterns
      cfd.md           # CFD preprocessing domain knowledge
    agents/            # Custom subagents
      reviewer.md      # Code review agent
      test-writer.md   # Test generation agent
    settings.json      # Hooks configuration
  turbo.json           # Turborepo pipeline config
  pnpm-workspace.yaml  # Workspace definition
```

### Git Workflow

- **Branch strategy**: GitHub Flow. `main` + short-lived feature branches.
- **Branch naming**: `type/description` (e.g., `feat/intent-graph`,
  `fix/tessellation-leak`).
- **Commits**: Conventional Commits with AI attribution trailers.
- **PRs**: Required for all changes. Automated checks -> AI review -> Human review.
- **Merging**: Squash merge for feature branches to keep main history clean.

### Claude Code Configuration

- **CLAUDE.md**: Build commands, test commands, code style, architecture invariants.
  Under 300 lines. Reviewed and updated each phase.
- **Skills**: One per domain. Loaded on demand via glob patterns. Updated as
  patterns emerge during implementation.
- **Subagents**: Reviewer agent for the Writer/Reviewer pattern. Test-writer agent
  for generating comprehensive test cases.
- **Hooks**: Pre-commit formatting and linting. Pre-push test execution.
- **MCP servers**: GitHub for issue/PR integration. SQLite for persistent
  project memory.

### Testing Strategy

- **Unit tests**: All geometry operations, agent logic, API endpoints.
- **Integration tests**: CadQuery container health, API-to-kernel round trips.
- **Visual regression**: Three.js viewer snapshots for rendering correctness.
- **E2E tests**: Critical user flows (describe geometry -> see result in viewer).
- **Coverage target**: 80% for kernel and agent packages. Lower bar acceptable
  for UI during early phases.

### Development Cadence

- **Daily**: Explore -> Plan -> Implement -> Commit cycles. Multiple features
  per day during implementation phases.
- **Weekly**: Review ADR backlog, update CLAUDE.md if patterns have shifted,
  prune stale branches.
- **Per-phase**: Retrospective on process effectiveness. Adjust testing strategy,
  Claude configuration, and phasing as needed.

## Consequences

### Positive

- **Architectural coherence**: ADRs create a shared understanding that persists
  across Claude sessions and team members. Every session starts with the same
  architectural context.
- **Accelerated implementation**: Claude Code handles the implementation bulk
  while humans focus on design, review, and domain decisions. The TDD loop
  keeps AI output verifiable.
- **Reduced rework**: Test-first development catches integration issues early.
  The three-tier review process (automated, AI, human) catches different classes
  of defects.
- **Traceable decisions**: The ADR trail explains why the codebase looks the way
  it does. New team members (human or AI) can reconstruct the reasoning.
- **Parallel development**: Git worktrees enable multiple Claude sessions working
  on different features simultaneously without interference.
- **Incremental delivery**: Phased approach ensures working software at every
  stage. The team can pivot based on user feedback without wasting unreleased
  work.

### Negative

- **Process overhead**: ADRs, TDD, and reviews add time to each feature. For a
  solo developer, this can feel burdensome. Mitigation: keep ADRs concise
  (this document notwithstanding), skip ADRs for purely tactical changes, and
  let AI handle test boilerplate.
- **CLAUDE.md maintenance**: The AI configuration files require ongoing curation.
  Stale instructions degrade Claude's effectiveness. Mitigation: review CLAUDE.md
  at phase boundaries and when Claude consistently misunderstands a pattern.
- **Toolchain complexity**: Monorepo + Turborepo + pnpm + Docker + Claude Code +
  MCP servers is a lot of moving parts. Mitigation: Phase 0 is dedicated to
  getting this infrastructure solid before feature work begins.
- **AI dependency**: The process is designed around Claude Code's capabilities.
  If Anthropic changes the tool significantly or the team switches to a different
  AI assistant, process adaptation will be needed. Mitigation: the core practices
  (ADRs, TDD, code review) are tool-agnostic. Only the Claude-specific
  configuration (CLAUDE.md, skills, hooks) would need porting.

### Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| AI-generated code introduces subtle geometry bugs | Medium | High | TDD with property-based tests for geometry operations; visual regression for viewer |
| CLAUDE.md grows beyond 300-line budget | High | Medium | Quarterly review; move domain knowledge to skills; delete obvious instructions |
| Team skips TDD under deadline pressure | Medium | High | Pre-commit hooks enforce test existence; CI fails without coverage threshold |
| Monorepo becomes unwieldy at scale | Low | Medium | Turborepo caching mitigates build times; package boundaries enforce modularity |
| Context rot in long Claude sessions | High | Medium | Strict /clear discipline; subagents for investigation; session length limits |

## Dependencies

### Tools and Infrastructure

- **pnpm** (>=9.0): Package management and workspace protocol [5]
- **Turborepo** (>=2.0): Monorepo build orchestration and caching [4]
- **Claude Code**: AI-assisted development (CLI and editor integration) [1]
- **GitHub Actions**: CI/CD pipeline for automated checks [6]
- **Docker**: CadQuery/OpenCASCADE containerization [14]
- **CodeRabbit** (or equivalent): AI-powered code review in PRs [9]

### MCP Servers

- **GitHub MCP**: PR and issue integration for Claude Code [10]
- **SQLite MCP**: Persistent project memory across sessions [10]
- **File System MCP**: Structured file access with permission boundaries [10]

### Upstream ADRs

- **ADR-001**: Product scope and vision. Defines what CadFlow is and is not.
- **ADR-002** (pending): Technology stack. Confirms CadQuery, React, Three.js,
  FastAPI choices.
- **ADR-003** (pending): Intent graph architecture. Defines the core data model
  that the agent layer operates on.

### Team Prerequisites

- All developers must have Claude Code installed and configured.
- All developers must understand the ADR format and conventional commits.
- CLAUDE.md and skills files are treated as production code: reviewed, tested
  (via AI behavior observation), and versioned.

## References

1. Anthropic. "Claude Code: Best practices for agentic coding." 2025.
   https://www.anthropic.com/engineering/claude-code-best-practices

2. Anthropic. "Tips for using Claude Code effectively." Documentation, 2025.
   https://docs.anthropic.com/en/docs/claude-code/tips-and-tricks

3. Narwhal Digital. "Why monorepos are ideal for AI-driven development." 2025.
   https://narwhaldigital.com/why-monorepos-are-ideal-for-ai-driven-development/

4. Vercel. "Turborepo documentation." 2025.
   https://turbo.build/repo/docs

5. pnpm. "Workspaces documentation." 2025.
   https://pnpm.io/workspaces

6. GitHub. "GitHub Flow documentation." 2025.
   https://docs.github.com/en/get-started/quickstart/github-flow

7. Atlassian. "Comparing Git workflows." 2025.
   https://www.atlassian.com/git/tutorials/comparing-workflows

8. Conventional Commits. "Specification v1.0.0." 2025.
   https://www.conventionalcommits.org/en/v1.0.0/

9. CodeRabbit. "AI-powered code review documentation." 2025.
   https://docs.coderabbit.ai/

10. Anthropic. "Claude Code MCP servers and extensions." Documentation, 2025.
    https://docs.anthropic.com/en/docs/claude-code/mcp-servers

11. Karl Hughes. "Vibe ADRs: Architecture decisions in the age of AI." 2025.
    https://www.karlhughes.com/posts/vibe-adrs

12. Cognitect. "Architecture Decision Records." 2025.
    https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions

13. Kent Beck. "Test-Driven Development: By Example." Addison-Wesley, 2003.

14. CadQuery. "CadQuery documentation." 2025.
    https://cadquery.readthedocs.io/
