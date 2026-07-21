# AGENTS.md — Lantern Tavern

This file provides guidance to Agent (AI coding assistant) when working with this project.

## Project Overview

**Lantern Tavern** — a 3D dungeon-crawler tavern management game built in Godot 4.7 with **GDScript**.

It is the **3D version** of the game design documented at `D:\Dungun ta\docs\` (Dungeon Tavern design docs). The design reference covers: tavern management, brewing/alchemy, exploration/extraction (WFC), turn-based combat, equipment system, employee system, reputation/relationships, and the "失序症" (Disorder Syndrome) main story.

## Architecture — Code Organization

```
Lantern Tavern/
├── data/                    ← Game data (resources, scripts, JSON)
│   ├── weapon_data.gd       — WeaponData Resource class
│   ├── weapon_registry.gd   — Autoload: reads weapons.json at runtime
│   └── weapons/
│       ├── *.tres           — Individual WeaponData resources (backward compat)
│       └── weapons.json     ← SINGLE SOURCE OF TRUTH for equipment stats
├── globals/                 ← Autoload singletons
├── scenes/
│   ├── ui/                  — UI panels (Control)
│   │   ├── model_viewer.gd  — 3D model gallery (dynamic from WeaponRegistry)
│   │   └── character_panel.gd — Equipment inspect panel (dynamic from WeaponRegistry)
│   ├── characters/          — Player, enemies, components
│   └── equipment/           — Pickable items, thrown items
├── assets/
│   └── meshes/weapons/      — GLB models (pipeline-generated)
├── tests/
│   └── gdunit/              ← gdUnit4 test suites
├── addons/gdUnit4/          ← Test framework
└── project.godot
```

## Equipment Data Flow

```
weapons.json (JSON)  ──→  WeaponRegistry (autoload)  ──→  model_viewer.gd
                     │                                  └──  character_panel.gd
                     ├──  *.tres (backward compat)
                     └──  Pipeline (Blender → godot_import → auto-register)
```

Add a new weapon: edit `weapons.json` → restart game → appears everywhere.  
Add a new weapon via Pipeline: write asset spec → run pipeline → `godot_import` auto-writes to `weapons.json`.

## 🚨 MANDATORY RULE: Manual Tavern Scene Edits Only

The tavern scene and tavern materials are hand-authored. Do **not** run, recreate, add, or use any tavern baking/generation/merge/bulk-rewrite workflow.

- Never run or reintroduce tavern bake scripts, material atlas generators, structure merge scripts, generated BuiltStructure replacement scripts, or broad scene rewrite tools.
- Never overwrite `scenes/tavern/tavern.tscn` or `Structure/BuiltStructure` wholesale to apply a localized change.
- All tavern edits must be target-only: modify exactly the requested node, material, script, or small resource needed for the task.
- If a tavern change would require batch regeneration or atlas baking, stop and ask the user instead of generating or applying it.
- Tests and automation must preserve hand-authored tavern geometry/materials and must not assert that baked tavern assets are regenerated.

## 🚨 MANDATORY RULE: Voxel Modeling Workflow

All voxel models must follow `docs/17-体素建模工作流.md`.

- The scale is fixed: `1m = 32px`, `1px = 1/32m`. Write dimensions in pixels first, then convert to meters.
- Every static voxel box must be attached by face contact only (positive volume overlap forbidden; causes z-fighting). Floating, corner-only, or visually detached parts are forbidden.
- Character/enemy GLBs must pass `tests/gdunit/character_voxel_overlap_test.gd`; prop kinds pass `voxel_overlap_scan_test.gd`.
- Blender generators must call `tools/voxel_overlap_guard.assert_parts_no_positive_volume_overlap` before export.
- New or changed voxel models must pass the voxel attachment/unit tests and produce front/side/top screenshots with `tools/voxel_prop_three_view_capture.gd`.
- Dynamic effects such as fire are separate from the static voxel body; they still need correct attachment/origin placement relative to the body.

## 🚨 MANDATORY RULE: One Model Per Modeling Workflow

Model design, generation, rig export, and regeneration must always target exactly one model.

- Batch model generators are forbidden. A modeling entry point must not accept multiple model IDs, an `all` target, a tier target, a wildcard, or a directory and must not loop over a model registry to write multiple assets.
- Do not hide batch generation in shell, PowerShell, Python, editor, or CI loops. Tier lists, directory scans, glob expansion, comma-separated IDs, and a command or job that invokes several model generators are all forbidden.
- This applies to every 3D model category: characters, creatures, players, weapons, armor, props, and environment assets. Each modeled asset must have one fixed identity and one independently authored generation path.
- Every character or creature model must have its own `tools/generate_voxel_<model_id>.py` source. That file owns the model's dimensions, silhouette, semantic parts, materials, and single output identity.
- A model generator may write only that model's static GLB, rig GLB, and its own verification images. It must fail when asked to target another model.
- Shared modules may provide voxel primitives, attachment guards, rendering helpers, and rig/animation mechanics. Shared modules must not contain a model registry, model-specific design table, or multi-output generation loop.
- Shared base-body, generic humanoid, creature-family, and silhouette templates are forbidden. Every model generator must define all of that model's primary masses, proportions, stepped contour, palette, and identity anchors itself; adding small signature plates to a shared body is not independent modeling.
- The character art direction is Barony-style authored voxel art, with the project S-tier rock golem as the internal quality reference. Use clustered voxel masses, stepped or broken contours, readable depth layers, deliberate asymmetry, and material color ramps. Broad smooth cuboids covered by decorative micro-parts are forbidden.
- Mesh or part count is not a quality metric. Each model's gdUnit test must assert its intended width, height, and depth envelope in pixels with a bounded tolerance, plus named primary silhouette parts visible across front, side, and top views. Micro-parts must not compensate for a collapsed primary volume.
- Do not add wrappers, shell scripts, editor tools, CI jobs, or documentation commands that invoke multiple model generators in one operation. Rebuild and inspect models one at a time.
- Read-only validation may scan multiple existing assets. This exception is limited to tests, reports, and capture inspection; it must never rewrite or re-export model assets.
- Removed batch workflows must not be restored, including character tier remakes, creature batches, humanoid remake batches, roguelike monster batches, or multi-character rig export.

## 🚨 MANDATORY RULE: No Built-in Weapons On Character Models

Character and creature 3D voxel models must **never** build, Bake, or hardcode hand-held weapons (swords, bows, crossbows, axes, pickaxes, spears, daggers, staves, etc.) directly into the character mesh geometry.

- Weapons belong exclusively to the **Equipment System** (`weapons.json`, `WeaponRegistry`, equipment scenes) and are mounted dynamically at runtime to bone attachment sockets (e.g. `Hand.L` / `Hand.R`).
- Character models must consist solely of character body, facial features, hair, armor/clothing, belts, pouches, capes, and non-weapon accessories.
- Hands and arms must be modeled in ready/holding poses with open sockets to receive equipment.

## 🚨 MANDATORY RULE: Agent Visual Verification Workflow

Visual verification uses two different capture classes. Do not use one as a substitute for the other:

1. **Structural 2D projections** are deterministic drawings used to inspect dimensions, voxel attachment, map topology, and semantic markers.
2. **Real 3D captures** use Godot cameras and viewports and are required to inspect materials, lighting, shading, particles, and occlusion.

### Model Three-View Capture

For every new or changed voxel model, generate `front`, `side`, and `top` views for exactly that model after the unit tests pass. The `--asset=<model_id>` selector is mandatory for model acceptance:

```bash
"D:/123/Godot_v4.7-stable_mono_win64.exe" --headless --path "D:/123/Lantern Tavern" --script res://tools/voxel_prop_three_view_capture.gd -- --asset=<model_id>
```

An unscoped capture, `--monsters-only`, a tier selector, a wildcard, a directory loop, or multiple IDs must not be used as evidence that an individual changed model was verified. Broad read-only scans remain diagnostic only under the exception above.

Outputs:

- Props and tutorial assets: `reports/props_preview/<asset>_{front,side,top}.png`
- Monster assets: `reports/characters_preview/voxel_<monster>_{front,side,top}.png`
- Real 3D model renders must use a distinct `voxel_<monster>_render_{preview,front,side,top}.png` stem. Structural projections and real 3D renders must never overwrite one another.

`voxel_prop_three_view_capture.gd` is a structural voxel projection tool. It projects mesh bounds into a 2D bitmap and does not prove production material, lighting, shadow, particle, or occlusion quality. The tool uses explicit asset allowlists; a new asset must be added to the appropriate list and covered by its asset test.

For real 3D appearance checks, use the existing SubViewport-based tools or the focused visual verification test:

- `tools/voxel_prop_material_render_preview.gd` — real 3D material contact sheet; requires a non-headless renderer.
- `tests/gdunit/weapon_visual_verification_test.gd` — focused real 3D `front/side/top` capture for its declared test assets.

### Dungeon 2D Top-Down Map

Run the deterministic procedural dungeon map test when changing dungeon generation, spawning, hazards, stairs, extraction, or top-down marker metadata:

```bash
"D:/123/Godot_v4.7-stable_mono_win64.exe" --headless -s tests/gdunit4_runner.gd -- --ignoreHeadlessMode -a tests/gdunit/dungeon_topdown_generation_test.gd
```

The test instantiates the real procedural dungeon, collects semantic markers, renders the grid to a 2D bitmap, and saves:

```text
reports/dungeon_topdown_generation_test.png
```

This map is for topology and semantic validation, not production 3D appearance. The test currently uses a deterministic seed in the test source. Do not treat older seed images in `reports/dungeon_topdown/` as proof that the current test regenerated them.

### Tavern Real 3D Top-Down Capture

For tavern geometry, material, lighting, and visibility checks, use the existing orthographic capture scripts:

```bash
# Full hand-authored tavern scene, semantic capture materials
"D:/123/Godot_v4.7-stable_mono_win64.exe" --headless --path "D:/123/Lantern Tavern" --script res://tools/tavern_topdown_render_file.gd

# Material-preserving tavern top-down scene capture
"D:/123/Godot_v4.7-stable_mono_win64.exe" --headless --path "D:/123/Lantern Tavern" res://tools/tavern_material_topdown_capture_scene.tscn
```

The capture scripts write runtime-only material overrides and hide underground nodes on the instantiated scene. They must never overwrite `scenes/tavern/tavern.tscn`, `Structure/BuiltStructure`, or any hand-authored tavern material. These captures are visual checks only; they are not tavern baking, generation, merging, atlas generation, or bulk rewrite workflows.

### Agent Inspection Checklist

After each capture, an agent must:

- Confirm the command exits successfully and every expected PNG exists and is readable.
- Confirm the image is not blank or mostly uniform.
- For models, inspect all three views for scale errors, detached/floating/corner-only parts, z-fighting, and misplaced dynamic-effect origins.
- For dungeon maps, inspect walkable topology and the presence/placement of player, enemy, item, hazard, stairs, and extraction markers.
- Use real 3D captures for material, lighting, shading, particle, and occlusion judgments; never infer those properties from structural projections.
- Report missing or stale outputs explicitly instead of silently treating existing report files as newly generated evidence.

## 🚨 MANDATORY RULE: Unit Tests for All Modifications

**All code changes MUST include corresponding unit tests using gdUnit4.**

This is non-negotiable. The following rules apply:

### 1. Scope
- **New files**: must have a companion test file in `tests/gdunit/`
- **Modified files**: existing tests may need updating; if no test exists for the functionality being changed, a new test must be added
- **Bug fixes**: must include a test that reproduces the bug before the fix passes after
- **Data changes** (weapons.json, .tres files): must update corresponding tests (resource existence checks, data integrity)

### 2. Test Pattern
All tests extend `GdUnitTestSuite` and follow this pattern:

```gdscript
extends GdUnitTestSuite

func test_descriptive_name() -> void:
    # Arrange
    var obj = MyClass.new()
    
    # Act
    obj.do_something()
    
    # Assert
    assert_str(obj.result).is_equal("expected")
```

### 3. Assertion Methods
Use the gdUnit4 assert chain:
- `assert_str(value)` — `.is_equal()`, `.contains()`, `.is_empty()` etc.
- `assert_int(value)` — `.is_equal()`, `.is_greater()`, `.is_less()` etc.
- `assert_float(value)` — `.is_equal()`, `.is_equal_approx()` etc.
- `assert_bool(value)` — `.is_true()`, `.is_false()`
- `assert_array(value)` — `.has_size()`, `.contains()` etc.
- `assert_object(value)` — `.is_instanceof()`, `.is_null()`, `.is_not_null()`

### 4. Test Naming
- Test files: `{functionality}_test.gd` (e.g. `weapon_registry_test.gd`)
- Test functions: `test_{what_is_being_tested}()`

### 5. Running Tests
```bash
# CLI (headless) — Godot executable at D:\123\Godot_v4.7-stable_mono_win64.exe
"D:/123/Godot_v4.7-stable_mono_win64.exe" --headless -s tests/gdunit4_runner.gd -- --ignoreHeadlessMode -a <test_file_or_directory>

# Run a single test file:
"D:/123/Godot_v4.7-stable_mono_win64.exe" --headless -s tests/gdunit4_runner.gd -- --ignoreHeadlessMode -a tests/gdunit/<test_file>.gd

# Run all tests:
"D:/123/Godot_v4.7-stable_mono_win64.exe" --headless -s tests/gdunit4_runner.gd -- --ignoreHeadlessMode -a tests/gdunit/

# Or from Godot editor: Project → Tools → gdUnit4 → Run All Tests
```

### 6. CI Enforcement
- All tests must pass before merging any changes
- New code without tests will be rejected during review
- Test coverage should cover: normal paths, edge cases, and error conditions

## Blender Asset Pipeline

The single-asset pipeline lives in `D:\123\blender\pipeline\`. Each invocation must receive exactly one JSON asset spec for exactly one asset:

```
one JSON asset spec  →  run_pipeline.py --spec <spec.json>  →  one .glb  →  godot_import.py  →  Lantern Tavern project
```

Directory targets, wildcards, repeated `--spec`, `--batch`, and any wrapper or loop that invokes the pipeline for several specs are forbidden. The pipeline validates and imports only that one asset; when it is a weapon, `godot_import.py` may register only that weapon in `weapons.json`.

## Agent skills

### Issue tracker

Issues and PRDs are tracked in this repository's GitHub Issues. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the five canonical triage labels without project-specific aliases. See `docs/agents/triage-labels.md`.

### Domain docs

This is a single-context repository; read root `CONTEXT.md` and `docs/adr/` when present. See `docs/agents/domain.md`.
