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
const DUNGEON_DOOR_SCRIPT := preload("res://scenes/expedition/dungeon_door.gd")
const STANDARD_DOOR_SIZE_METERS := Vector2(1.0, 2.0)
const BOSS_DOOR_SIZE_METERS := Vector2(2.0, 2.0)

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
	_build_multi_meshes(layout, result)
	_build_collisions(layout, result)
	_build_wall_occluders(layout, result)
	_build_downstairs_portal(layout, result)
	_build_door_panels(layout, result, parent)
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

# ── MultiMesh 创建（阶段 B1：迁自 procedural._build_multi_meshes/_build_chunked_multi_meshes） ──
const STREAM_CHUNK_SIZE_CELLS := 8
const CEILING_THICKNESS := 0.1
const DOOR_SURROUND_THICKNESS := 0.2

## 按 layout + build_result.* 产出 floor/wall/ceiling MultiMesh，挂 build_result.terrain_root。
## procedural 的 _build_multi_meshes 改调本接口，不再自创 MultiMesh。
func _build_multi_meshes(layout: DungeonLayout, result: DungeonBuildResult) -> void:
	if result == null or result.terrain_root == null:
		return
	var tile_size: float = layout.tile_size
	# 1. 地板
	var floor_mat := _make_terrain_mat("FLOOR", Vector2(tile_size, tile_size))
	_build_chunked_multi_meshes(result, "FloorMultiMesh", result.floor_transforms,
		Vector3(tile_size, 0.1, tile_size), floor_mat)
	# 2. 天花板
	var ceiling_mat := _make_terrain_mat("CEILING", Vector2(tile_size, tile_size))
	_build_chunked_multi_meshes(result, "CeilingMultiMesh", result.ceiling_transforms,
		Vector3(tile_size, CEILING_THICKNESS, tile_size), ceiling_mat)
	# 3. 墙面（按尺寸分组）
	for wall_key in result.wall_transforms_by_height:
		var group: Dictionary = result.wall_transforms_by_height[wall_key]
		var transforms: Array = group.get("transforms", [])
		if transforms.is_empty():
			continue
		var size: Vector3 = group.get("size", Vector3(tile_size, 3.0, DOOR_SURROUND_THICKNESS))
		var mat := _make_terrain_mat("WALL", Vector2(maxf(size.x, size.z), size.y))
		_build_chunked_multi_meshes(result, "WallMultiMesh_%s" % wall_key.replace(",", "_"),
			transforms, size, mat)

func _build_chunked_multi_meshes(result: DungeonBuildResult, base_name: String,
		transforms: Array, mesh_size: Vector3, material: Material) -> void:
	if transforms.is_empty():
		return
	var chunks := _group_transforms_by_stream_chunk(transforms, result.tile_size)
	var first_chunk := true
	for chunk in chunks.keys():
		var chunk_transforms: Array = chunks[chunk]
		var mm_instance := MultiMeshInstance3D.new()
		mm_instance.name = base_name if first_chunk else "%s_%d_%d" % [base_name, chunk.x, chunk.y]
		first_chunk = false
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var base_mesh := BoxMesh.new()
		base_mesh.size = mesh_size
		mm.mesh = base_mesh
		mm.instance_count = chunk_transforms.size()
		for i in range(chunk_transforms.size()):
			mm.set_instance_transform(i, chunk_transforms[i])
		mm_instance.multimesh = mm
		mm_instance.material_override = material
		mm_instance.visible = false
		result.terrain_root.add_child(mm_instance)
		# terrain chunk 注册（streaming 用）—— procedural 路径暂保，builder 产节点挂 terrain_root
		if not result.terrain_chunks.has(chunk):
			result.terrain_chunks[chunk] = []
		(result.terrain_chunks[chunk] as Array).append(mm_instance)

func _group_transforms_by_stream_chunk(transforms: Array, tile_size: float) -> Dictionary:
	var by_chunk: Dictionary = {}
	var chunk_size := float(STREAM_CHUNK_SIZE_CELLS) * tile_size
	for t in transforms:
		var tr := t as Transform3D
		var chunk := Vector2i(int(tr.origin.x / chunk_size), int(tr.origin.z / chunk_size))
		if not by_chunk.has(chunk):
			by_chunk[chunk] = []
		(by_chunk[chunk] as Array).append(t)
	return by_chunk

const TERRAIN_CFG := preload("res://scenes/expedition/dungeon_terrain_config.gd")

func _make_terrain_mat(tile_name: String, tile_repeat: Vector2) -> ShaderMaterial:
	return TERRAIN_CFG.make_terrain_mat(tile_name, tile_repeat)

# ── 碰撞 + occluder（阶段 B2：迁自 procedural._build_merged_collisions/_build_wall_occluders） ──
## 按 chunk 合并地形碰撞为少量 ConcavePolygonShape3D，挂 build_result.collision_root。
## floor/ceiling 各一组按 chunk 合；墙体按高度+chunk 合。产出 streamed_physics_nodes + terrain_chunks。
func _build_collisions(layout: DungeonLayout, result: DungeonBuildResult) -> void:
	if result == null or result.collision_root == null:
		return
	var tile_size: float = layout.tile_size
	_build_merged_collision_group(result, "FloorCollisions", result.floor_transforms,
		Vector3(tile_size, 0.1, tile_size))
	_build_merged_collision_group(result, "CeilingCollisions", result.ceiling_transforms,
		Vector3(tile_size, CEILING_THICKNESS, tile_size))
	for wall_key in result.wall_transforms_by_height:
		var group: Dictionary = result.wall_transforms_by_height[wall_key]
		var transforms: Array = group.get("transforms", [])
		if transforms.is_empty():
			continue
		var size: Vector3 = group.get("size", Vector3(tile_size, 3.0, DOOR_SURROUND_THICKNESS))
		_build_merged_collision_group(result, "WallCollisions_%s" % wall_key.replace(",", "_"),
			transforms, size)

func _build_merged_collision_group(result: DungeonBuildResult, base_name: String,
		transforms: Array, box_size: Vector3) -> void:
	if transforms.is_empty():
		return
	var by_chunk := _group_transforms_by_stream_chunk(transforms, result.tile_size)
	var physics := _physics_setup()
	for chunk in by_chunk.keys():
		var chunk_transforms: Array = by_chunk[chunk]
		var body := StaticBody3D.new()
		body.name = "%s_%d_%d" % [base_name, chunk.x, chunk.y]
		if physics != null:
			body.collision_layer = physics.LAYER_ENVIRONMENT
			body.collision_mask = physics.MASK_ENVIRONMENT
		var col := CollisionShape3D.new()
		col.name = "MergedCollision"
		var shape := ConcavePolygonShape3D.new()
		var faces: PackedVector3Array = PackedVector3Array()
		for t in chunk_transforms:
			var tr := t as Transform3D
			_append_box_faces(faces, tr.origin, box_size)
		shape.set_faces(faces)
		col.shape = shape
		body.add_child(col, true)
		result.collision_root.add_child(body)
		result.streamed_physics_nodes.append(body)
		if not result.terrain_chunks.has(chunk):
			result.terrain_chunks[chunk] = []
		(result.terrain_chunks[chunk] as Array).append(body)

func _append_box_faces(faces: PackedVector3Array, center: Vector3, size: Vector3) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var p000 := center + Vector3(-hx, -hy, -hz)
	var p100 := center + Vector3( hx, -hy, -hz)
	var p110 := center + Vector3( hx,  hy, -hz)
	var p010 := center + Vector3(-hx,  hy, -hz)
	var p001 := center + Vector3(-hx, -hy,  hz)
	var p101 := center + Vector3( hx, -hy,  hz)
	var p111 := center + Vector3( hx,  hy,  hz)
	var p011 := center + Vector3(-hx,  hy,  hz)
	faces.append_array([p000, p100, p110, p000, p110, p010])
	faces.append_array([p001, p011, p111, p001, p111, p101])
	faces.append_array([p000, p010, p011, p000, p011, p001])
	faces.append_array([p100, p101, p111, p100, p111, p110])
	faces.append_array([p000, p001, p101, p000, p101, p100])
	faces.append_array([p010, p110, p111, p010, p111, p011])

## 墙体 BoxOccluder3D 遮挡体，挂 build_result.terrain_root（属 terrain 视觉剔除）。
func _build_wall_occluders(layout: DungeonLayout, result: DungeonBuildResult) -> void:
	if not ProjectSettings.get_setting("rendering/occlusion_culling/use_occlusion_culling", false):
		return
	if result == null or result.terrain_root == null:
		return
	var container := Node3D.new()
	container.name = "WallOccluders"
	result.terrain_root.add_child(container)
	for wall_key in result.wall_transforms_by_height:
		var group: Dictionary = result.wall_transforms_by_height[wall_key]
		var transforms: Array = group.get("transforms", [])
		if transforms.is_empty():
			continue
		var size: Vector3 = group.get("size", Vector3(layout.tile_size, 3.0, DOOR_SURROUND_THICKNESS))
		for t in transforms:
			var tr := t as Transform3D
			var occ := OccluderInstance3D.new()
			var box := BoxOccluder3D.new()
			box.size = size + Vector3(0.06, 0.06, 0.06)
			occ.occluder = box
			occ.transform = tr
			container.add_child(occ)

func _physics_setup() -> Node:
	# autoload singleton 走 /root/<name> 路径（builder 是 RefCounted 非节点，无 get_tree）
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("PhysicsSetup")

# ── downstairs portal（阶段 B3：迁自 procedural._spawn_downstairs_portal 纯 Mesh 拼装部分） ──
## 产 DownstairsPortal Node3D + 4 级 DownstairsStep MeshInstance3D，挂 build_result.interaction_root。
## 信号接线（area.body_entered.connect）属 runtime 范畴，builder 只 instantiate 不接——procedural 后续接。
func _build_downstairs_portal(layout: DungeonLayout, result: DungeonBuildResult) -> void:
	if result == null or result.interaction_root == null:
		return
	if not layout.room_roles.has("stairs"):
		return  # downstairs 仅在含 stairs role 的布局生成
	var grid: Array = layout.grid
	var tile_size: float = layout.tile_size
	var offset_x: float = -(float(layout.width) * tile_size) / 2.0
	var offset_z: float = -(float(layout.height) * tile_size) / 2.0
	var offset: Vector3 = Vector3(offset_x, 0, offset_z)
	# stairs 房中心格作 downstairs 位
	var stairs_center := _rect_center_cell(layout.room_roles["stairs"])
	var best_pos := offset + Vector3(stairs_center.x * tile_size, 0.5, stairs_center.y * tile_size)
	var root := Node3D.new()
	root.name = "DownstairsPortal"
	root.set_meta("topdown_kind", "stairs")
	root.position = best_pos
	result.interaction_root.add_child(root)
	result.streamed_visual_nodes.append(root)
	# 4 级下楼台阶
	var step_mat := StandardMaterial3D.new()
	step_mat.albedo_color = Color(0.20, 0.18, 0.16)
	step_mat.roughness = 0.9
	for i in range(4):
		var step := MeshInstance3D.new()
		step.name = "DownstairsStep%d" % (i + 1)
		step.set_meta("topdown_kind", "stairs")
		var box := BoxMesh.new()
		box.size = Vector3(1.8, 0.14, 0.36)
		step.mesh = box
		step.material_override = step_mat
		step.position = Vector3(0, 0.02 + i * 0.03, -0.54 + i * 0.36)
		root.add_child(step)
	# Area3D 节点也 instantiate（信号接线留 runtime）
	var area := Area3D.new()
	area.name = "DownstairsArea"
	area.set_meta("topdown_kind", "stairs")
	area.position = Vector3(0, 0.5, 0)
	var col_shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(2.0, 2.0, 2.0)
	col_shape.shape = box_shape
	area.add_child(col_shape)
	root.add_child(area)
	print("[DungeonSceneBuilder] Downstairs portal placed at ", best_pos)

func _rect_center_cell(rect: Rect2i) -> Vector2i:
	return rect.position + Vector2i(rect.size.x / 2, rect.size.y / 2)


# ── door panels（阶段 B3 第二版：迁自 procedural._spawn_room_door_panels） ──
## 产 DungeonDoor Node3D + 墙包围结构，挂 build_result.doors_root。
## 信号接线（door.pressure_action.connect）转调 parent._on_door_pressure_action（runtime 范畴，下步真迁 runtime）。
## 步3 真迁体已补 _spawn_door_panel/_spawn_door_wall_surround/_spawn_door_wall_box/_door_surround_size/_height_at_cell_in_layout，
## 但 _collect_room_door_specs 等 8 工具链深，暂转调 procedural 旧路径保编译；下回合补工具链后激活真迁体。
func _build_door_panels(layout: DungeonLayout, result: DungeonBuildResult, parent: Node3D) -> void:
	if result == null or result.doors_root == null:
		return
	if layout.rooms.is_empty():
		return
	if parent == null or not is_instance_valid(parent):
		return
	# 暂转调 procedural 旧路径（含信号接线 _on_door_pressure_action + 8 工具链）
	if parent.has_method("_spawn_room_door_panels"):
		var tile_size: float = layout.tile_size
		var offset_x: float = -(float(layout.width) * tile_size) / 2.0
		var offset_z: float = -(float(layout.height) * tile_size) / 2.0
		var offset: Vector3 = Vector3(offset_x, 0, offset_z)
		parent._spawn_room_door_panels(layout.grid, offset, tile_size)

# ── door panel（B3 第二版步3：迁自 procedural._spawn_door_panel） ──
## 产 DungeonDoor Node3D + 墙包围结构，挂 doors_root。信号接线转调 parent._on_door_pressure_action。
func _spawn_door_panel(spec: Dictionary, offset: Vector3, tile_size: float, index: int, result: DungeonBuildResult, parent: Node3D) -> void:
	var inside: Vector2i = spec["inside"]
	var outside: Vector2i = spec["outside"]
	var dir: Vector2i = spec["dir"]
	var boss := bool(spec["boss"])
	var cell_pos := offset + Vector3(inside.x * tile_size, 0.0, inside.y * tile_size)
	var panel_pos := cell_pos + Vector3(float(dir.x), 0.0, float(dir.y)) * (tile_size * 0.5)
	var door := DUNGEON_DOOR_SCRIPT.new() as DungeonDoor
	door.name = ("BossDoor_%03d" if boss else "Door_%03d") % index
	door.position = panel_pos
	door.set_meta("inside_cell", inside)
	door.set_meta("outside_cell", outside)
	door.set_meta("door_size_m", BOSS_DOOR_SIZE_METERS if boss else STANDARD_DOOR_SIZE_METERS)
	_spawn_door_wall_surround(door.name + "Surround", panel_pos, inside, outside, dir, boss, tile_size, result, parent)
	door.configure(
		DungeonDoor.KIND_BOSS if boss else DungeonDoor.KIND_STANDARD,
		dir,
		_make_terrain_mat("BOSS_DOOR" if boss else "DOOR", Vector2(1.0, 1.0)),
		_make_terrain_mat("DOOR_SIDE", Vector2(DungeonDoor.THICKNESS, BOSS_DOOR_SIZE_METERS.y if boss else STANDARD_DOOR_SIZE_METERS.y)),
		_make_terrain_mat("DOOR_TOP", Vector2(BOSS_DOOR_SIZE_METERS.x * 0.5 if boss else STANDARD_DOOR_SIZE_METERS.x, DungeonDoor.THICKNESS))
	)
	if result.doors_root != null:
		result.doors_root.add_child(door)
	if parent != null and parent.has_method("register_streamed_visual_node"):
		parent.register_streamed_visual_node(door)
	if parent != null and parent.has_method("_on_door_pressure_action"):
		door.pressure_action.connect(parent._on_door_pressure_action)

# ── door wall surround（B3 第二版步3：迁自 procedural._spawn_door_wall_surround） ──
func _spawn_door_wall_surround(base_name: String, panel_pos: Vector3, inside: Vector2i, outside: Vector2i, dir: Vector2i, boss: bool, tile_size: float, result: DungeonBuildResult, parent: Node3D) -> void:
	var door_size := BOSS_DOOR_SIZE_METERS if boss else STANDARD_DOOR_SIZE_METERS
	# 注：_height_at_cell 需要 layout，由 _build_door_panels 传 layout 到 _spawn_door_panel 再传 parent
	# parent 持 layout（ProceduralDungeon.layout 字段），通过 parent.layout 读
	var p_layout: DungeonLayout = parent.layout if parent != null and parent.has_method("get") else null
	var wall_height := maxf(maxf(_height_at_cell_in_layout(inside, p_layout), _height_at_cell_in_layout(outside, p_layout)), door_size.y + 0.5)
	var side_width := maxf((tile_size - door_size.x) * 0.5, 0.0)
	if side_width <= 0.01:
		return
	var width_axis := Vector3(0, 0, 1) if dir.x != 0 else Vector3(1, 0, 0)
	var side_size := _door_surround_size(side_width, wall_height, dir, parent)
	var side_offset := door_size.x * 0.5 + side_width * 0.5
	_spawn_door_wall_box(base_name + "LeftJamb", panel_pos - width_axis * side_offset + Vector3(0, wall_height * 0.5, 0), side_size, result, parent)
	_spawn_door_wall_box(base_name + "RightJamb", panel_pos + width_axis * side_offset + Vector3(0, wall_height * 0.5, 0), side_size, result, parent)
	var lintel_height := maxf(wall_height - door_size.y, 0.0)
	if lintel_height > 0.05:
		var lintel_size := _door_surround_size(door_size.x, lintel_height, dir, parent)
		var lintel_pos := panel_pos + Vector3(0, door_size.y + lintel_height * 0.5, 0)
		_spawn_door_wall_box(base_name + "Lintel", lintel_pos, lintel_size, result, parent)

func _door_surround_size(width: float, height: float, dir: Vector2i, parent: Node3D) -> Vector3:
	# 迁自 procedural._door_surround_size（rendering_cfg 通过 parent 引用读）
	var thickness: float = 0.2
	if parent != null and "_rendering_cfg" in parent:
		thickness = parent._rendering_cfg.door_surround_thickness
	if dir.x != 0:
		return Vector3(thickness, height, width)
	return Vector3(width, height, thickness)

func _height_at_cell_in_layout(cell: Vector2i, layout: DungeonLayout) -> float:
	# 迁自 procedural._height_at_cell
	if cell.y < 0 or cell.y >= layout.heights.size():
		return 3.0
	if cell.x < 0 or cell.x >= layout.heights[cell.y].size():
		return 3.0
	return maxf(float(layout.heights[cell.y][cell.x]), 3.0)

# ── door wall box（B3 第二版步2：迁自 procedural._spawn_door_wall_box） ──
## 产 MeshInstance3D + BoxShape3D 门包围结构，挂 build_result.doors_root。
## streaming 注册转调 parent.register_streamed_visual_node（保路径不破）。
func _spawn_door_wall_box(name: String, pos: Vector3, size: Vector3, result: DungeonBuildResult, parent: Node3D) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = name
	mesh.set_meta("door_surround", true)
	mesh.set_meta("topdown_kind", "terrain_feature")
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = pos
	mesh.material_override = _make_terrain_mat("WALL", Vector2(maxf(size.x, size.z), size.y))
	if result.doors_root != null:
		result.doors_root.add_child(mesh)
	if parent != null and parent.has_method("register_streamed_visual_node"):
		parent.register_streamed_visual_node(mesh)
	# 碰撞体（StaticBody3D + BoxShape3D）挂 collision_root
	if result.collision_root != null:
		var body := StaticBody3D.new()
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		col.shape = shape
		body.add_child(col)
		body.position = pos
		result.collision_root.add_child(body)
		if parent != null and parent.has_method("register_streamed_physics_node"):
			parent.register_streamed_physics_node(body)
	return mesh


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
