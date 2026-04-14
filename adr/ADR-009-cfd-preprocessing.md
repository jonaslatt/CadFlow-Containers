# ADR-009: CFD Preprocessing Workflows

## Status
Proposed

## Date
2026-04-07

## Context

CadFlow targets engineers who perform CAD as preprocessing for CFD simulations. These users need to create, simplify, defeature, and prepare geometry for meshing — a workflow that existing tools handle either poorly (manual, error-prone) or expensively (commercial tools like ANSYS SpaceClaim, SimScale). This ADR defines the CFD-specific operations CadFlow must support and how they integrate with the intent graph and meshing tools.

Key forces:
- **Surface naming is the #1 CFD preprocessing feature.** Without named face groups, all surfaces default to "Wall" and retroactive labeling is very difficult.
- **snappyHexMesh (OpenFOAM) is the primary meshing target.** It requires clean STL with named solids.
- **GMSH is the secondary meshing target.** It uses Physical Groups for boundary conditions and has a Python API.
- **Defeaturing is tedious and manual in open-source tools.** Commercial tools like SpaceClaim automate this; CadFlow can use the AI agent to assist.
- **The topological naming problem is real.** Face indices change on rebuild; CadQuery's query-based selectors are the mitigation strategy.

## Research Findings

### Salome-Meca Geometry Preprocessing

Salome's GEOM module provides the reference open-source CFD prep workflow:
- **Import:** IGES, BREP, STEP, STL, XAO, VTK formats
- **Repair:** Shape Healing (Shape Processing, Limit Tolerance, sewing, remove small edges/faces)
- **Explode:** Decompose compounds into sub-shapes. "Flat" mode recursively extracts all simple sub-shapes.
- **Partition:** Build compound by partitioning objects against tools. Essential for creating conformal meshes at interfaces.
- **Groups:** Primary mechanism for boundary condition tagging. **Must explicitly transfer** from GEOM module to SMESH module — if not transferred, groups don't appear in solver setup.
- **Defeaturing:** Largely manual — identify features, explode, delete, heal. No automatic threshold-based removal.

Sources: [Salome GEOM Docs](https://docs.salome-platform.org/latest/gui/GEOM/index.html), [CristalX Salome Guide](https://cristalx.readthedocs.io/en/latest/salome.html)

### OpenFOAM / snappyHexMesh Requirements

- **Input:** Triangulated STL (ASCII preferred). STL "solid" names become patch names (must be valid C/C++ identifiers).
- **Quality:** Jagged STL triangulations → jagged mesh. Background mesh must be pure hex with aspect ratio ~1 near surfaces.
- **Feature edges:** Extracted via `surfaceFeatureExtract` with `includedAngle` (typically 150°).
- **Multi-region:** Separate watertight STLs per region with matching interface geometry. Regions defined via `faceZone` and `cellZone` markers.
- **Common failures:** Edge snapping with misaligned background, "leaked" meshes from coarse cells, mesh quality violations requiring iterative relaxation.
- **cfMesh** is substantially more tolerant of poor surface quality — performs wrapping and volume meshing simultaneously.

Sources: [OpenFOAM snappyHexMesh Guide](https://www.openfoam.com/documentation/user-guide/4-mesh-generation-and-conversion/4.4-mesh-generation-with-the-snappyhexmesh-utility), [Wolf Dynamics SHM Reference](https://www.wolfdynamics.com/wiki/meshing_OF_SHM.pdf)

### GMSH Integration

- **Kernels:** Built-in (simple primitives) and OpenCASCADE (full Booleans, STEP/IGES import, fillet/chamfer).
- **Physical Groups:** Primary mechanism for boundary conditions. Defined by (dimension, tag) pair. API: `gmsh.model.addPhysicalGroup()` + `gmsh.model.setPhysicalName()`.
- **Critical behavior:** By default, GMSH exports ONLY mesh elements in physical groups. Set `Mesh.SaveAll=1` to override.
- **Fragment:** `gmsh.model.occ.fragment()` is essential for conformal meshes at volume interfaces.
- **Mesh refinement:** Field-based — Distance, Threshold, Min fields for combining strategies.
- **OpenFOAM export:** `gmshToFoam` only converts MSH format version 2.
- **API:** Python, C++, C, Julia. Full workflow: initialize → geometry → synchronize → physical groups → mesh → write.

Sources: [GMSH Reference Manual](https://gmsh.info/doc/texinfo/gmsh.html), [J. Dokken GMSH Tutorial](https://jsdokken.com/src/tutorial_gmsh.html)

### Common CFD Geometry Problems

| Problem | Description | Impact |
|---------|-------------|--------|
| Gaps and holes | Incomplete surfaces | Non-watertight; meshers can't determine inside/outside |
| Overlaps | Intersecting faces | Duplicate cells or meshing failure |
| Slivers | Very thin faces/edges | Degenerate mesh elements |
| Small features | Fillets, chamfers, tiny holes | Force extremely fine mesh without flow physics benefit |
| Non-manifold edges | Edge shared by >2 faces | Prevents proper volume determination |
| Self-intersections | Surfaces crossing themselves | Ambiguous volume definition |

**Defeaturing strategies:** Fillet removal (below threshold radius), small hole filling, chamfer removal, thin feature deletion, Boolean simplification. **Wrapping approaches** (ANSYS Fluent, cfMesh) bypass repair by shrink-wrapping a surface around dirty geometry.

Sources: [Simularge: CAD for CFD](https://www.simularge.com/blog/preparing-cad-geometry-for-cfd-simulations-essential-steps-and-best-practices), [Cadence: Geometry Challenges](https://community.cadence.com/cadence_blogs_8/b/cfd/posts/hurdling-geometry-model-challenges-for-cfd-mesh-generation)

### Common CFD Setups

| Setup | Geometry Needs |
|-------|---------------|
| **External aero** | Bounding domain (far-field box), refinement zones (near body + wake), boundary layer prisms, inlet < outlet distance |
| **Internal flow** | Fluid volume extraction from solid CAD, inlet/outlet planar caps, watertight domain, face groups for BCs |
| **Conjugate heat transfer** | Multi-region (fluid + solid), conformal mesh at interfaces, fine inflation layers (y+ < 1) |
| **Multiphase** | Same as single-phase + mesh refinement near expected interface; VOF captures interface dynamically |

Sources: [IdealSimulations: CFD Domain](https://www.idealsimulations.com/resources/cfd-computational-domain/), [SimScale: Vehicle Aero Tutorial](https://www.simscale.com/docs/tutorials/aerodynamic-simulation-vehicle/)

### Commercial Tool Advantages

What SpaceClaim, SimScale, and COMSOL do that open-source tools don't:
- **Automatic defeaturing** with tolerance-based thresholds (SpaceClaim's Fill Tool, COMSOL's Remove Details)
- **Virtual geometry operations** (COMSOL) — ignore features without modifying B-rep
- **Fault-tolerant wrapping** (ANSYS Fluent, SimScale) — mesh dirty geometry without repair
- **Integrated flow volume extraction** — one-click fluid domain from solid geometry
- **Scripting + GUI synergy** — interactive repair with scriptable automation

Sources: [SimScale CAD Mode](https://www.simscale.com/docs/cad-preparation/cad-mode/), [ANSYS SpaceClaim Defeaturing](https://innovationspace.ansys.com/knowledge/forums/topic/defeaturing-geometry-with-fill-tool-in-spaceclaim/), [COMSOL Defeaturing](https://doc.comsol.com/6.2/doc/com.comsol.help.cad/cad_ug_cad_import_repair_defeaturing.5.07.html)

### Surface Naming and the Topological Naming Problem

- **The problem:** When geometry regenerates, face indices shift. FreeCAD spent years solving this (shipped in 1.0).
- **OCAF TNaming:** Tracks shape evolution (PRIMITIVE, GENERATED, MODIFY, DELETE, SELECTED). `TNaming_Selector` re-identifies faces after rebuild.
- **CadQuery's approach:** Query-based selectors (`faces(">Z")`, `edges("|Z")`) describe geometric properties, not indices. Inherently more robust. The `tag("name")` method stores workplane state references.
- **XDE:** OCCT framework for storing names, colors, layers on shapes down to face/edge level. STEP export preserves these via `STEPCAFControl_Writer`.
- **For CadFlow:** Intent graph + query selectors = right approach. Must map to STL solid names (snappyHexMesh) and GMSH Physical Groups.

Sources: [CadQuery Selectors](https://cadquery.readthedocs.io/en/latest/selectors.html), [OCAF Guide](https://dev.opencascade.org/doc/occt-7.4.0/overview/html/occt_user_guides__ocaf.html), [FreeCAD TNP](https://wiki.freecadweb.org/Topological_naming_problem)

## Options Considered

### Option A: Minimal Export-Only

CadFlow exports STEP and STL. All CFD preprocessing (defeaturing, surface naming, domain creation) is done in external tools (Salome, GMSH GUI).

- **Pros:** Minimal scope. Fastest to build. Users can use existing workflows.
- **Cons:** No CFD differentiation. No reason for CFD users to choose CadFlow over FreeCAD. The agent can't assist with CFD-specific tasks.
- **Real-world precedent:** Most code-based CAD tools (OpenSCAD, CadQuery alone) work this way.

### Option B: Full Integrated CFD Preprocessor

CadFlow includes built-in meshing, solver setup, and post-processing. A mini-SimScale.

- **Pros:** Complete workflow in one tool. Maximum value for CFD users.
- **Cons:** Meshing is an enormous engineering effort. Solver setup requires deep CFD domain knowledge. Post-processing is a separate product. Scope explosion guarantees nothing ships.
- **Real-world precedent:** SimScale took years and millions in funding to build this.

### Option C: Smart Geometry Preparation + Mesher Integration (Recommended)

CadFlow handles geometry preparation (the painful part) and delegates meshing to GMSH/snappyHexMesh via well-defined export pipelines. The AI agent assists with CFD-specific geometry tasks.

- **Pros:** Focused scope. Addresses the actual pain point (geometry prep, not meshing itself). GMSH and snappyHexMesh are mature; no need to reinvent. Agent can genuinely help (suggest defeaturing, auto-create domains). Named STL export for snappyHexMesh is a killer feature.
- **Cons:** Users must still use external tools for meshing (until V2 GMSH integration). Export format compatibility requires careful testing.
- **Real-world precedent:** SpaceClaim focuses on geometry prep; meshing is handled by Fluent. This separation works well.

## Decision

**Option C: Smart Geometry Preparation + Mesher Integration.**

### Core CFD Operations (V1)

**Surface naming and grouping:**
- Users (or the agent) assign names and boundary condition types to face groups via intent graph metadata
- Face groups are defined using CadQuery selectors (query-based, robust to topology changes)
- Intent graph stores: `{node_id, face_selector, group_name, bc_type}` where `bc_type` ∈ {inlet, outlet, wall, symmetry, interface, farfield}
- On export, face groups map to:
  - STL: separate solid names (for snappyHexMesh)
  - GMSH: Physical Groups (for GMSH meshing)
  - STEP: XDE labels (for Salome interop)

**Defeaturing:**
- `cad_cfd_defeature(max_fillet_radius, max_hole_diameter, remove_chamfers)` — threshold-based automatic removal
- Implementation: iterate over fillets, identify those below radius threshold, suppress. Same for holes below diameter threshold.
- Agent can suggest defeaturing parameters based on model analysis ("I found 12 fillets under 2mm radius and 8 holes under 3mm diameter — shall I remove them?")

**Flow domain creation:**
- External flow: `cad_cfd_create_domain(type="bounding_box", padding=[5, 5, 10, 5, 5, 20])` — creates rectangular far-field enclosure with specified padding multipliers (body lengths)
- Internal flow: `cad_cfd_create_domain(type="cavity_extract")` — Boolean subtract body from bounding domain to get fluid volume
- Inlet/outlet caps: automatically created as named planar faces

**Watertight validation:**
- `cad_cfd_check_watertight()` — runs BRepCheck_Analyzer for closure, checks face orientations, reports gaps/holes
- Returns actionable diagnostics: "3 open edges found between faces 12 and 15; suggesting sewing operation"

**STL import and repair:**
- Import STL via OCP's `StlAPI_Reader` — produces a triangulated mesh shape
- STL→BREP conversion is lossy; imported STL is positioned as a mesh repair/export object, not a parametric modeling entry point
- Represented in the intent graph as an `import_stl` node (opaque, like the `custom_code` escape hatch)
- Repair operations applicable to imported STL and native geometry:
  - Sewing (join adjacent faces within tolerance)
  - Fill holes (cap open boundaries)
  - Fix face orientations
  - Remove duplicate faces
  - Remove degenerate triangles
- Agent can analyze imported STL and suggest repairs: "This STL has 47 open edges and 3 non-manifold vertices. Shall I attempt auto-repair with 0.1mm sewing tolerance?"

### Export Pipeline

```
Intent Graph + Surface Groups
    │
    ├── STL Export (for snappyHexMesh)
    │   ├── Tessellate each face group separately
    │   ├── Write as multi-solid STL (one solid per group)
    │   ├── Solid names = group names (valid C identifiers)
    │   └── Feature edges exported via surfaceFeatureExtract format
    │
    ├── STEP Export (for GMSH / Salome)
    │   ├── Export via STEPCAFControl_Writer with XDE labels
    │   ├── Face-level names preserved in STEP AP242
    │   └── Colors indicate boundary condition types
    │
    ├── BREP Export (for direct OCCT consumers)
    │   └── OCCT native binary format
    │
    └── GMSH Script Export (V1.1)
        ├── Generate .geo script with Physical Groups
        ├── Map face groups to Physical Surface definitions
        └── Include mesh sizing directives from intent graph metadata
```

### Agent-Assisted CFD Preparation

The AI agent has CFD-specific tools (defined in ADR-005) and domain knowledge:

1. **Suggest defeaturing:** "This model has 23 fillets under 1mm. For external aerodynamics at Re=10^6, these won't affect the flow. Shall I remove them?"
2. **Auto-create domains:** "For this airfoil, I'll create a C-type domain with 10c upstream, 20c downstream, and 5c lateral extent."
3. **Recommend surface groups:** "I've identified likely inlet (face >X), outlet (face <X), and wall (remaining) surfaces. Please review."
4. **Validate for meshing:** "The geometry is watertight. STL quality: min angle 15°, max aspect ratio 3.2. Ready for snappyHexMesh."
5. **Fix geometry issues:** "Found 2 non-manifold edges. I can fix them by sewing with 0.01mm tolerance."

### V1.1: GMSH API Integration

- Call GMSH Python API from CadFlow backend to generate meshes directly
- Specify mesh sizing via Distance/Threshold fields mapped from intent graph metadata
- Preview mesh statistics (element count, quality metrics) before full generation
- Export to OpenFOAM format via `gmshToFoam` (MSH v2)

### V2: Meshing Preview

- Interactive mesh preview in the 3D viewport (surface mesh displayed as wireframe overlay)
- Mesh quality visualization (color-coded by element quality)
- Refinement zone specification via 3D interaction (drag boxes/spheres for refinement regions)

## Consequences

### Positive
- Surface naming via intent graph metadata is architecturally foundational — building it early means deep integration
- Named STL export for snappyHexMesh eliminates the most painful step in the OpenFOAM workflow
- Query-based selectors for face groups are robust to topology changes — groups survive parameter modifications
- Agent-assisted defeaturing democratizes a task that currently requires expensive commercial tools
- GMSH API integration (V1.1) provides a complete geometry-to-mesh pipeline

### Negative / Trade-offs
- No built-in meshing in V1 — users must use external tools
- Query-based selectors may be ambiguous when multiple faces match the same query (e.g., two faces both ">Z")
- Defeaturing can change model topology in unexpected ways (removing a fillet may merge faces)
- STL quality depends on tessellation parameters — too coarse = bad mesh, too fine = huge files

### Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Face groups don't survive rebuild | Use multiple selectors per group (primary + fallback); validate groups after every rebuild |
| STL solid naming breaks snappyHexMesh | Enforce valid C identifier naming; validate before export |
| Defeaturing produces invalid geometry | Run BRepCheck_Analyzer after each defeaturing step; undo if invalid |
| GMSH integration (V1.1) is harder than expected | GMSH has a mature Python API; start with simple cases |
| Agent suggests wrong boundary conditions | Always require user confirmation for BC assignments in Suggest/Propose modes |

## Dependencies

- **ADR-001** (Product Scope): CFD operations defined as V1 MVP features
- **ADR-005** (Agentic Workflow): CFD-specific tool definitions for the agent
- **ADR-008** (Data Model): Surface group metadata stored in intent graph; STEP AP242 export with XDE labels
- **ADR-010** (Security): Defeaturing and domain creation run in sandboxed geometry workers
