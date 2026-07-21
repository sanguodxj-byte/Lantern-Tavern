# 场景实例化脚本排错报告

**日期**：2026-07-16
**方法**：headless 递归实例化 `res://scenes/` 下全部 `.tscn`，逐个 `load → instantiate → add_child → tick → free`，崩溃可续跑（`tools/scene_instantiate_probe.gd` + 驱动 `D:/tmp/run_probe_driver.sh`）。

## 总览

| 指标 | 结果 |
|---|---|
| 扫描场景数 | **106** |
| 成功实例化 | **106 / 106** |
| 加载失败 | 0 |
| 实例化失败 | 0 |
| 硬崩溃(signal 11) | 0（探针加 `is_instance_valid` 守卫后） |
| 脚本级错误(SCRIPT ERROR) | **1 类，已修复** |

所有场景均能实例化并进出场景树。唯一的**脚本级 bug** 已定位并修复。

---

## 已修复：脚本 bug（`scenes/rooms/base_room.gd`）

**症状**：17× `SCRIPT ERROR: Cannot call method 'find_item_by_name' on a null value.`
波及全部房间/关卡场景（base_room、Cellar、centerpillarroom、foyer、jailcell、jailconnector、kitchen、sacrifice_room、level_01_welcome）。

**根因**：`fill_ceilings()` 直接调用 `floors.mesh_library.find_item_by_name(...)`，但当引用的 meshlib 加载失败时 `mesh_library == null` → 空值方法调用硬崩溃。此外 `@onready var editor_key_indicator := %EditorKeyIndicator` 在部分房间指向已被移除的节点 → `Node not found` 报错。

**修复**：
- 4 个 `@onready` 唯一名节点改用 `get_node_or_null(...)`，缺失时安全返回 null。
- `fill_ceilings()` 对 `floors` / `floors.mesh_library` / `ceilings` 逐一判空，缺资源时 `push_warning` 优雅降级，不再崩溃。
- `prep_enemies()` / `on_scream_heard()` / `on_enemy_death()` 补 `enemies` 判空。

**回归测试**：`tests/gdunit/base_room_robustness_test.gd`（4 用例，全部 PASSED）。

---

## 待处理：GridMap 房间贴图（遗留资产，非脚本，非"缺失"）

> **更正（2026-07-17）**：先前报告把根因写成"贴图缺失"是不准确的。**源瓦片贴图确实存在**于
> `assets/textures/terrain/level0_dungeon/source_tiles/`（如 `wall_stone_brick.png`、`ceiling_stone_slab.png` 等），
> 由 `tools/build_level0_dungeon_atlas.py` 程序化生成，并拼成**现役地牢图集**
> `level0_dungeon_terrain_atlas_32px.png`（被 `DungeonTerrainConfig` / `ProceduralDungeon` 的地形 Shader 使用）。

真正缺失的是 GridMap 旧系统引用的**烘焙图集产物**（已被新图集取代，其元数据 JSON 的 `deprecated_replaces` 已登记旧路径）：

- `res://assets/meshes/walls/walls-tiles_dungeon-texture.png` — **不存在**（旧烘焙产物）
- `res://assets/meshes/walls/ceiling-tiles_dungeon-texture.png` — **不存在**（旧烘焙产物）

连锁后果：`assets/meshlibs/walls-tiles.meshlib`、`ceilings-tiles.meshlib` 加载失败 → 房间 GridMap 无地面/天花板网格。

**影响面评估**：`base_room.tscn` 及其 7 个子房间（Cellar / centerpillarroom / foyer / jailcell / jailconnector / kitchen / sacrifice_room）
在运行时**没有任何 spawner / config 外部引用**（已 grep 确认），属于**孤立的遗留房间**。
现役地牢由 `ProceduralDungeon`（地形 Shader + 新图集）生成，不依赖这两个 meshlib。
因此该缺失**不影响实际游玩**——脚本侧的 null 容错（上节修复）已足以让这些场景安全实例化。

**处置建议**（需资产/设计决策，非脚本排错范围）：
1. 维持现状：7 个 GridMap 房间作为遗留资产搁置，脚本已不崩。
2. 若要让这些房间重新显示墙体/天花：需恢复 `walls-tiles_dungeon-texture.png` / `ceilings-tiles_dungeon-texture.png`，
   路径二选一——(a) 按其原始 UV 布局重新烘焙该图集；(b) 若其 UV 网格与新图集 8×4@32px 对齐，
   直接把 `level0_dungeon_terrain_atlas_32px.png` 复刻/软链到期望路径（待验证 UV 对齐度）。

---

## 无需处理（正常降级 / headless 噪声 / 可选清理）

- `[PickableItem] Material GLB not found ... using fallback box`：脚本已有回退逻辑，属预期告警。
- `ProjectileEntity: projectile_data 为空，立即销毁`：无数据实例化时的自毁保护，正常。
- `ERROR: Parameter "material" is null`：headless dummy 渲染器噪声，真机不出现。
- `... RID allocations leaked at exit` / `Pages in use at exit`：headless 退出清理噪声，非场景问题。
- `invalid UID ... using text path instead`（pickable_sword、pause_menu、各敌人 rig 等）：UID 缓存与文本路径不一致，Godot 已回退文本路径。可选：编辑器内重新保存对应场景刷新 UID。
- `A node in the scene this one inherits from has been removed or moved ... re-save`（kobold、foyer、jailconnector）：继承场景漂移。可选：编辑器内重新保存以消除。
- 2× `Loaded resource as image file, this will not work on export`（技能图标 PNG）：导出时会失效，建议改为正常导入的 Image 资源。

---

## 已执行清理（2026-07-17）：移除整条 GridMap 房间遗留系统

经用户确认（`子房间和meshlib是旧残留，进行移除` → `整条 GridMap 房间系统`），移除了与旧 GridMap 房间/关卡相关的全部遗留资产：

**删除的文件**
- 7 个子房间场景：`scenes/rooms/Cellar.tscn`、`centerpillarroom.tscn`、`foyer.tscn`、`jailcell.tscn`、`jailconnector.tscn`、`kitchen.tscn`、`sacrifice_room.tscn`
- 房间基类：`scenes/rooms/base_room.tscn`、`scenes/rooms/base_room.gd`（+ `.uid`）
- 两个 GridMap 图集：`assets/meshlibs/walls-tiles.meshlib`、`ceilings-tiles.meshlib`
- 遗留手工关卡：`scenes/levels/level_01_welcome.tscn`（继承 base_level.tscn 并把上述 7 房间拼装为关卡，运行时无外部引用）
- 昨天为验证该崩溃写的测试：`tests/gdunit/base_room_robustness_test.gd`（+ `.uid`）
- 诊断脚本：`tools/meshlib_diag.gd`

**保留并解耦**
- `scenes/levels/base_level.gd` —— **活跃关卡基类**（`procedural_dungeon.gd`、`wfc_visual_test.gd` 继承它，现役 WFC 地牢依赖它）。**未删**。
- `scenes/levels/base_level.tscn` —— 移除了其中依赖已删 meshlib 的 `Floors` GridMap 节点及其 `walls-tiles.meshlib` ext_resource，仅保留 `Rooms/PlayerSpawn/Hallways/Doors` 空容器，作为可复用关卡基础场景。
- `tests/gdunit/base_level_test.gd` —— 原 `test_level_01_exists()` 断言已删的 `level_01_welcome.tscn` 存在，已替换为 `test_base_level_decoupled_from_legacy_meshlib()`（验证 base_level.tscn 不再引用两个已删 meshlib）。测试 9/9 PASSED。

**删除前已核验**：`base_room`/`level_01_welcome` 在 `.gd/.tscn` 中除自身/测试/codemap 文档外无任何引用；`base_level` 的活跃性由 `procedural_dungeon.gd` 的 `extends BaseLevel` 确认。主场景为 `main_menu.tscn`，现役地牢由 `ProceduralDungeon`(WFC) 运行时生成，不依赖任何被删文件。

**影响**：meshlib 是旧烘焙产物，现役地牢图集为 `level0_dungeon_terrain_atlas_32px.png`（由 `DungeonTerrainConfig` 的地形 Shader 使用），二者无关。移除后现役链路不受影响；headless 加载 `base_level.tscn`/`procedural_dungeon.tscn`/`base_level.gd` 均 OK，无 `Resource file not found ... meshlib` 报错。

**后续可选**：`docs/gdscript_codemap.json` 仍含 `BaseRoom`/`level_01_welcome` 的陈旧条目，可由 `tools/gdscript_codemap.py` 重新生成以消除。
