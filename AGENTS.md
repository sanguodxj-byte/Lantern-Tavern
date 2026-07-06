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
- Every static voxel box must be attached to the model by face contact or intentional overlap. Floating, corner-only, or visually detached parts are forbidden.
- New or changed voxel models must pass the voxel attachment/unit tests and produce front/side/top screenshots with `tools/voxel_prop_three_view_capture.gd`.
- Dynamic effects such as fire are separate from the static voxel body; they still need correct attachment/origin placement relative to the body.

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

The asset pipeline lives in `D:\123\blender\pipeline\`. It generates 3D weapon models from JSON asset specs:

```
asset_specs/weapons/*.json  →  run_all.py (Blender)  →  .glb  →  godot_import.py  →  Lantern Tavern project
```

Pipeline results are validated automatically. Newly generated weapons are auto-registered in `weapons.json` by `godot_import.py`.
