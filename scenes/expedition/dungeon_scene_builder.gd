## DungeonSceneBuilder — 把 DungeonLayout 实例化为 Godot 场景节点（阶段 7）。
#
# 职责：承接阶段 5/6 已 100% 数据化的 spec（hazard_anchors / enemy_spawn_specs /
# chest_spawn_specs），instantiate prefab 并挂到 DungeonBuildResult 的分 root 上。
# 地板/墙体/天花板/门 MultiMesh 等重型几何**第一版仍保留 procedural_dungeon.gd 内**，
# 阶段 10 缩减 procedural 时再逐步迁入（见重构方案原则 1）。
#
# 严格遵守：
#   - 集中节点创建，不再全 add 到 ProceduralDungeon 根；分 root 容器
#   - 不重新规划布局（layout 已含 hazard/spawn spec），只做 prefab 映射 + instantiate
#   - hazard_type / enemy_type / chest_type 字符串 ID 映射到 prefab，不改 layout
class_name DungeonSceneBuilder
extends RefCounted

const SPIKES_TRAP_PREFAB := preload("res://scenes/traps/spikes_trap.tscn")
const FLAME_VENT_TRAP_PREFAB := preload("res://scenes/traps/flame_vent_trap.tscn")
const ACID_TRAP_PATH := "res://scenes/traps/acid_trap.tscn"
const CHEST_PREFAB := preload("res://scenes/props/chest/chest.tscn")
const BOSS_CHEST_PREFAB := preload("res://scenes/props/chest/boss_chest.tscn")
const EXTRACTION_PORTAL_PREFAB := preload("res://scenes/expedition/extraction_portal.tscn")

## 构建：按 layout instantiate hazard/chest 节点，挂到 build_result 的分 root。
## parent: ProceduralDungeon 或同等 Node3D 容器；调用方持 build_result 引用。
## 返回 DungeonBuildResult。第一版不构建 terrain/wall/floor（保留 procedural）。
func build(layout: DungeonLayout, parent: Node3D) -> DungeonBuildResult:
	var result := DungeonBuildResult.new()
	if layout.is_empty() or parent == null or not is_instance_valid(parent):
		return result
	# 创建分 root
	result.terrain_root = _new_root("TerrainRoot", parent)
	result.collision_root = _new_root("CollisionRoot", parent)
	result.doors_root = _new_root("DoorsRoot", parent)
	result.hazards_root = _new_root("HazardsRoot", parent)
	result.decor_root = _new_root("DecorRoot", parent)
	result.spawn_root = _new_root("SpawnRoot", parent)
	result.interaction_root = _new_root("InteractionRoot", parent)
	result.streamed_visual_root = _new_root("StreamedVisualRoot", parent)
	result.streamed_physics_root = _new_root("StreamedPhysicsRoot", parent)
	# 第一版只实例化 hazard + chest + extraction portal（敌人由 DungeonSpawner autoload 旧路径生成，阶段 10 再迁；
	# downstairs portal 是手工 MeshInstance3D 拼装，属 terrain 类，暂留 procedural）
	_build_hazards(layout, result)
	_build_chests(layout, result)
	_build_extraction_portal(layout, result)
	return result

# ── hazard prefab 映射 ───────────────────────────────────────────
func _build_hazards(layout: DungeonLayout, result: DungeonBuildResult) -> void:
	for anchor in layout.hazard_anchors:
		var prefab := _hazard_prefab_for(String(anchor["hazard_type"]))
		if prefab == null:
			continue
		var instance := prefab.instantiate() as Node3D
		if instance == null:
			continue
		var cell: Vector2i = anchor["anchor_cell"]
		instance.position = _cell_to_world(cell, layout.tile_size)
		instance.set_meta("hazard_anchor", true)
		instance.set_meta("topdown_kind", "hazard")
		instance.set_meta("hazard_cell", cell)
		result.hazards_root.add_child(instance)
		result.streamed_physics_nodes.append(instance)

func _hazard_prefab_for(hazard_type: String) -> PackedScene:
	match hazard_type:
		"spikes":
			return SPIKES_TRAP_PREFAB
		"flame_vent":
			return FLAME_VENT_TRAP_PREFAB
		"acid":
			return load(ACID_TRAP_PATH) as PackedScene
		_:
			return null

# ── chest prefab 映射 ────────────────────────────────────────────
func _build_chests(layout: DungeonLayout, result: DungeonBuildResult) -> void:
	for spec in layout.chest_spawn_specs:
		var chest_type: String = spec["chest_type"]
		var prefab := _chest_prefab_for(chest_type)
		if prefab == null:
			continue
		var instance := prefab.instantiate() as Node3D
		if instance == null:
			continue
		var cell: Vector2i = spec["cell"]
		instance.position = _cell_to_world(cell, layout.tile_size)
		instance.set_meta("topdown_kind", "chest")
		instance.set_meta("chest_type", chest_type)
		result.interaction_root.add_child(instance)
		result.streamed_physics_nodes.append(instance)

func _chest_prefab_for(chest_type: String) -> PackedScene:
	match chest_type:
		"boss_chest":
			return BOSS_CHEST_PREFAB
		"normal_chest":
			return CHEST_PREFAB
		_:
			return null

# ── extraction portal prefab 映射 ───────────────────────────────
## 撤离传送门 instantiate。信号接线（extraction_requested.connect）属 runtime 阶段 9 聃畴，
## builder 只 instantiate 节点 + set_meta，不接信号。
func _build_extraction_portal(layout: DungeonLayout, result: DungeonBuildResult) -> void:
	if layout.is_key_cell_missing(layout.extraction_cell):
		return  # extraction 是 0.2 概率 role，未命中不放
	var instance := EXTRACTION_PORTAL_PREFAB.instantiate() as Node3D
	if instance == null:
		return
	instance.position = _cell_to_world(layout.extraction_cell, layout.tile_size)
	instance.name = "ExtractionPortal"
	instance.set_meta("topdown_kind", "extraction")
	result.interaction_root.add_child(instance)
	result.streamed_physics_nodes.append(instance)

# ── helpers ──────────────────────────────────────────────────────
func _new_root(name: String, parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = name
	parent.add_child(root)
	return root

## 格坐标 → 世界坐标（与 procedural_dungeon.gd 的 OFFSET 公式一致，但 scene builder 不持有 OFFSET；
## 调用方若需居中，自行在 parent 上设 transform。这里返回格原点世界位）
func _cell_to_world(cell: Vector2i, tile_size: float) -> Vector3:
	return Vector3(cell.x * tile_size, 0.0, cell.y * tile_size)
