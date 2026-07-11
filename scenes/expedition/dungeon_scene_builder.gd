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
	# 阶段 9 条 1 步2：地形 Transform 收集迁入 builder（wall_h_map 两遍预计算 + floor/wall/ceiling），
	# 产出填 build_result.floor_transforms/ceiling_transforms/wall_transforms_by_height/wall_h_map。
	# MultiMesh 批渲染 + merged collisions 暂留 procedural（步3-4 再迁），改读 build_result.* 而非旧类字段。
	_build_terrain(layout, result)
	_build_hazards(layout, result)
	_build_chests(layout, result)
	_build_extraction_portal(layout, result)
	return result

# ── terrain Transform 收集（阶段 9 条 1 步2） ─────────────────────
## 收集 floor/wall/ceiling Transform 到 build_result，并预计算 wall_h_map（两遍消除相邻墙格高度差接缝）。
## 不创建 MultiMesh/碰撞体（步3-4 再迁）；procedural 的 _build_multi_meshes/_build_merged_collisions 改读 build_result.*。
func _build_terrain(layout: DungeonLayout, result: DungeonBuildResult) -> void:
	if layout.is_empty():
		return
	var grid: Array = layout.grid
	var grid_width: int = grid[0].size() if grid.size() > 0 else 0
	var grid_height: int = grid.size()
	var tile_size: float = layout.tile_size
	var offset_x: float = -(float(grid_width) * tile_size) / 2.0
	var offset_z: float = -(float(grid_height) * tile_size) / 2.0
	var OFFSET := Vector3(offset_x, 0, offset_z)
	# ── wall_h_map 两遍预计算（消除相邻墙格高度差接缝）──
	# 第一遍：每个墙格取所有 4 邻格（含其他墙格）的最大 layout.heights 值
	var wall_h_map: Dictionary = {}
	for wy in range(grid_height):
		for wx in range(grid_width):
			if int(grid[wy][wx]) == 2:
				var best: float = float(layout.heights[wy][wx])
				for d in [Vector2i(0,-1), Vector2i(0,1), Vector2i(1,0), Vector2i(-1,0)]:
					var nx2 = wx + d.x
					var ny2 = wy + d.y
					if nx2 >= 0 and nx2 < grid_width and ny2 >= 0 and ny2 < grid_height:
						best = maxf(best, float(layout.heights[ny2][nx2]))
				wall_h_map[Vector2i(wx, wy)] = best if best > 0.0 else 3.0
	# 第二遍：相邻墙格互相传播最大值（消除"隔一格"仍存在的高度差）
	for wy in range(grid_height):
		for wx in range(grid_width):
			if int(grid[wy][wx]) == 2:
				var key := Vector2i(wx, wy)
				var cur: float = wall_h_map[key]
				for d in [Vector2i(0,-1), Vector2i(0,1), Vector2i(1,0), Vector2i(-1,0)]:
					var nk := Vector2i(wx + d.x, wy + d.y)
					if wall_h_map.has(nk) and float(wall_h_map[nk]) > cur:
						cur = float(wall_h_map[nk])
				wall_h_map[key] = cur
	result.wall_h_map = wall_h_map
	# ── floor/wall/ceiling Transform 收集 ──
	var CEILING_THICKNESS: float = 0.2  # 与 procedural 类顶 const 一致
	for y in range(grid_height):
		for x in range(grid_width):
			var cell_type: int = int(grid[y][x])
			var cell_pos := OFFSET + Vector3(x * tile_size, 0, y * tile_size)
			# floor（所有非 void 格都铺地板）
			var ft := Transform3D()
			ft.origin = cell_pos - Vector3(0, 0.05, 0)
			result.floor_transforms.append(ft)
			# wall
			if cell_type == 2:
				var wall_height: float = float(wall_h_map.get(Vector2i(x, y), 3.0))
				var wt := Transform3D()
				wt.origin = cell_pos
				wt.origin.y += wall_height / 2.0
				var size := Vector3(tile_size, wall_height, tile_size)
				var key := _wall_segment_key(size)
				if not result.wall_transforms_by_height.has(key):
					result.wall_transforms_by_height[key] = {"size": size, "transforms": []}
				(result.wall_transforms_by_height[key]["transforms"] as Array).append(wt)
			elif cell_type != 0:
				# ceiling
				var ceiling_height: float = float(layout.heights[y][x])
				var ct := Transform3D()
				ct.origin = cell_pos + Vector3(0, ceiling_height + CEILING_THICKNESS * 0.5, 0)
				result.ceiling_transforms.append(ct)

func _wall_segment_key(size: Vector3) -> String:
	return "%d,%d,%d" % [int(size.x), int(size.y), int(size.z)]

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
