# 死代码 / 孤儿代码检查报告

**日期**：2026-07-17
**范围**：`res://` 下全部 `.gd` / `.tscn` / `.tres`（710 个代码文件，排除 `.godot`、`addons`）。
**方法**：构建引用图（preload/load/extends/change_scene/ext_resource/全文 `res://` 字面量）→ 解析 `project.godot` 的 `main_scene` 与 autoload（含 `uid://` 解析）→ 从入口做 BFS 可达性 → 求差集。

## 结论速览

**没有发现"互相引用、但确实未接入主系统"的游戏逻辑死簇。** 扫描器最初报出大量"孤儿"，但逐个人工核验后，绝大多数属于以下三类**误报**：

1. **autoload 以单例名访问**（非路径）：`FxHelper`/`GameEvents`/`HitStopServer`/`GameState` 在 `project.godot` 里以 `uid://` 注册，被代码以单例名调用，路径扫描看不到。
2. **运行时动态实例化**：大量脚本/场景用 `class_name` + `Xxx.new()`、节点路径子节点（`$Node`）、或运行时 `load` 被引用，没有字面 `res://` 路径。
3. **测试文件按文件名 glob 发现**：CI 的 `run_all_gdunit_batched.ps1` 递归扫描 `*_test.gd`，不是靠 import 引用，所以测试文件天然"零引用"——它们都在跑，不是死代码。

因此初始 363 个"零引用"文件里，**真正可疑的只有少数 scratch / 遗留文件**（见下）。

## 一、确认存活的动态加载项（非死代码，勿删）

以下被扫描器标为"零引用"，但已验证为**活跃**，仅因动态实例化而不在静态路径图中：

| 文件 | 存活证据 |
|---|---|
| `scenes/expedition/prop_distributor.gd` | `class_name PropDistributor`，`item_spawner.gd` 等 `.new()` 调用 |
| `scenes/characters/enemies/state/enemy_state_data.gd` | `class_name EnemyStateData` |
| `scenes/characters/player/view_model_animator.gd` | `class_name ViewModelAnimator` |
| `scenes/traps/snare_trap.gd` | `class_name SnareTrap`（地牢运行时生成） |
| `shaders/shader_warmer.gd` | `class_name ShaderWarmer`，`world.gd:36` `ShaderWarmer.new()` |
| `scenes/ui/save_load_panel.tscn` | `pause_menu.gd` 以 `$SaveLoadPanel` 子节点引用 |
| `assets/meshes/props/baked_*.tscn` (28) | 运行时 `load baked_<kind>.tscn`（voxel 道具系统） |
| `materials/*_mat.tres` (53) | 被导入的 mesh/材质内部引用，非脚本路径 |
| `data/weapons/greatsword.tres` 等 | `weapon_registry` 经 `weapons.json` 加载 |
| 全部 `*_test.gd` / 集成测试 | CI 按 `*_test.gd` 文件名 glob 发现并运行 |

## 二、互相引用但未接入的簇

扫描器共标出 89 个"互相引用且无外部链接"的簇，**全部为下列两类，无游戏逻辑死簇**：

- **活跃运行时系统**（有测试引用 + 运行时动态加载，非死）：`enemy_state*`、`player_state*`、`fx/*`(blood_spurt/metal_spark/voxel_chip/damage_number)、`character_panel`、`skill_bar`、`expedition_hud` 等。
- **有意为之的编辑器/性能工具**（自包含、手动运行、本就不接入玩法）：
  - `tools/tavern_topdown_capture_scene.gd` ↔ `.tscn` + `tavern_topdown_render_file.gd`
  - `tools/tavern_cellar_side_capture_scene.gd` ↔ `.tscn`
  - `tools/tavern_material_topdown_capture_scene.gd` ↔ `.tscn`
  - `tools/tavern_perf_probe_scene.tscn`、`tools/tavern_topdown_subviewport_capture.gd`
  - `tools/dungeon_view_perf_probe.gd` ↔ `.tscn`（有 `dungeon_view_perf_probe_test.gd`）

> 这些工具簇正是用户担心的"多个孤儿互相引用未接入"形态，但它们是**工具脚本**，设计上就是手动/编辑器调用，不属于遗漏接入的 bug。

## 三、真正可疑、建议清理的项（高置信度）

| 文件 | 类型 | 证据 | 建议 |
|---|---|---|---|
| `_trash_20260715/`（4×.gd + 5×.ps1 + .uid） | 回收站目录 | 目录名即 trash，内容为本项目早期 scratch 与 PS1 批处理 | **删除** |
| `_seed_probe.gd` | 根目录临时探针 | 文件头自注"临时探针"，无引用 | **删除** |
| `tools/script_entry_probe.gd` | 旧场景探针 | 已被 `tools/scene_instantiate_probe.gd` 取代，全仓无引用 | **删除** |
| `tools/verify_tavern_scene.gd` | scratch 工具 | 仅自身注释里提到自己，无调用方 | 删除或保留（确认无用后删） |
| `tools/generate_pixel_icons.gd` | scratch 工具 | 无 `class_name`、全仓无调用方（仅 codemap 生成文档提及） | 删除或保留 |
| `scenes/tavern/tavern_baked_geometry.tscn` | 疑似遗留几何 | **全仓零引用**（含 `tavern.tscn` 也不引用），疑似被 `tavern_structure.gd` 手工结构取代 | **先核验再删**（中置信度遗留） |

## 四、方法局限性（重要）

- autoload 单例名调用、`class_name` 动态 `new()`、节点路径子节点、运行时拼路径 `load()`、`*_test.gd` glob 发现——这些都无法被纯路径引用图捕获，会表现为"孤儿"。本报告已对每一项人工核验。
- `materials/*.tres` 多被导入的 `.mesh`/`.glb` 内部引用，扫描器看不到，需要 Godot 资源依赖图才能精确判断，故未断言其死活。
- 若需 100% 确认 `tavern_baked_geometry.tscn` 等是否仍被加载，建议用 Godot 编辑器 `编辑 → 复制依赖` 或 `grep` `.import` 反向查，或在 headless 下 `ResourceLoader.load` 验证。

## 五、建议动作

1. 删除 `_trash_20260715/`、`_seed_probe.gd`、`tools/script_entry_probe.gd`（确认无用）。
2. 核验 `tavern_baked_geometry.tscn` 是否仍在用；若否，删除并同步 `docs/gdscript_codemap.json`。
3. 保留其余（动态加载项、测试、编辑器工具）——它们不是死代码。

## 六、已执行清理（2026-07-17）

用户确认"清理"后，已删除以下高置信度孤儿 / scratch 文件，且均验证无回归：

| 文件 | 类型 | 验证结果 |
|---|---|---|
| `_seed_probe.gd` | 根目录临时探针（自注"临时探针"） | 零引用，删除 |
| `tools/script_entry_probe.gd` | 被 `scene_instantiate_probe.gd` 取代 | 零引用，删除 |
| `tools/verify_tavern_scene.gd` | scratch 工具 | 零调用方，删除 |
| `tools/generate_pixel_icons.gd` | scratch 工具 | 零调用方，删除 |
| `scenes/tavern/tavern_baked_geometry.tscn` | 疑似遗留几何 | 核验：`tavern_structure.gd` 只预载材质不加载 tscn；`world.tscn`/`tavern.tscn` 均不包含；命名不匹配运行时 `baked_<kind>.tscn` 模式；全仓零引用 → 删除（程序生成产物，非手工场景，不违反 tavern 铁律） |
| `_trash_20260715/` | 回收站目录（含 4×.gd + 5×.ps1） | 递归删除 |

**连带修正**：
- `tests/gdunit/procedural_dungeon_test.gd:16` 注释中残留已删文件名 `_seed_probe` → 改为"历史层级探针验证"。

**验证**：
- 全仓复检：除一条无害注释（已修）外无残留代码引用。
- headless 加载 `tavern.tscn` / `world.tscn` / `base_level.tscn` 均 `OK`，无 `Resource file not found`、无 `SCRIPT ERROR`。
- 重跑 `docs/gdscript_codemap.json` / `CODEMAP.md`（现扫描 482 个 `.gd`，较清理前少 4 个），被删文件已从图谱移除，根目录无游离副本。
