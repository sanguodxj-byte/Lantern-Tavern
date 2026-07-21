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
const PILLAR_PREFAB := preload("res://scenes/props/structures/pillar.tscn")
const TORCH_PREFAB := preload("res://scenes/props/torch/torch.tscn")
const SCENE_OBJECT_SCRIPT := preload("res://scenes/props/scene_object.gd")
const SCENE_OBJECT_LAYER := 64
const DungeonRuntimeConfig := preload("res://scenes/expedition/dungeon_runtime_config.gd")
const DECOR_VISIBILITY_RANGE_END := 60.0
const TORCH_VISIBILITY_RANGE_END := 35.0

# 同一路径的批处理装饰只需实例化一次模板：bounds 用于碰撞占位，parts 用于最终 MultiMesh 合批。
# 该缓存属于单次 builder 生命周期，避免跨地牢持有旧场景资源。
var _batched_decor_cache: Dictionary = {}

## P-A：导航烘焙是否异步执行（后台线程，消除进场最长单帧 stall）。
## 默认 false = 保留同步烘焙（当前生产已知可用、敌人寻路正常）。
## 改为 true 前必须在「有窗口」构建下做冒烟测试：确认敌人能正常寻路追击。
## 原因：headless 下导航烘焙文档不稳定（偶发 native crash / 异步完成回调在 --script 下不触发），
## 本环境无法窗口化验证异步烘焙是否会把多边形正确回填进 NavigationRegion3D，故先保守默认关闭。
const ENABLE_ASYNC_NAVMESH_BAKE := false

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
	_build_decor_and_torches(layout, result, parent)
	_build_batched_decor_multi_meshes(layout, result, parent)
	_build_navigation_mesh(layout, result, parent)
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
	_build_chunked_multi_meshes(layout, result, "FloorMultiMesh", result.floor_transforms,
		Vector3(tile_size, 0.1, tile_size), floor_mat)
	# 2. 天花板
	var ceiling_mat := _make_terrain_mat("CEILING", Vector2(tile_size, tile_size))
	_build_chunked_multi_meshes(layout, result, "CeilingMultiMesh", result.ceiling_transforms,
		Vector3(tile_size, CEILING_THICKNESS, tile_size), ceiling_mat)
	# 3. 墙面（按尺寸分组）
	for wall_key in result.wall_transforms_by_height:
		var group: Dictionary = result.wall_transforms_by_height[wall_key]
		var transforms: Array = group.get("transforms", [])
		if transforms.is_empty():
			continue
		var size: Vector3 = group.get("size", Vector3(tile_size, 3.0, DOOR_SURROUND_THICKNESS))
		var mat := _make_terrain_mat("WALL", Vector2(maxf(size.x, size.z), size.y))
		_build_chunked_multi_meshes(layout, result, "WallMultiMesh_%s" % wall_key.replace(",", "_"),
			transforms, size, mat)

func _build_chunked_multi_meshes(layout: DungeonLayout, result: DungeonBuildResult, base_name: String,
		transforms: Array, mesh_size: Vector3, material: Material) -> void:
	if transforms.is_empty():
		return
	var chunks := _group_transforms_by_stream_chunk(transforms, layout.tile_size)
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
		# int() 对负数向 0 截断；地牢以原点居中后，大量出生格位于负坐标，
		# 必须向下取整才能和 DungeonStreamingController 的 chunk 计算一致。
		var chunk := Vector2i(floori(tr.origin.x / chunk_size), floori(tr.origin.z / chunk_size))
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
	_build_merged_collision_group(layout, result, "FloorCollisions", result.floor_transforms,
		Vector3(tile_size, 0.1, tile_size))
	_build_merged_collision_group(layout, result, "CeilingCollisions", result.ceiling_transforms,
		Vector3(tile_size, CEILING_THICKNESS, tile_size))
	for wall_key in result.wall_transforms_by_height:
		var group: Dictionary = result.wall_transforms_by_height[wall_key]
		var transforms: Array = group.get("transforms", [])
		if transforms.is_empty():
			continue
		var size: Vector3 = group.get("size", Vector3(tile_size, 3.0, DOOR_SURROUND_THICKNESS))
		_build_merged_collision_group(layout, result, "WallCollisions_%s" % wall_key.replace(",", "_"),
			transforms, size)

func _build_merged_collision_group(layout: DungeonLayout, result: DungeonBuildResult, base_name: String,
		transforms: Array, box_size: Vector3) -> void:
	if transforms.is_empty():
		return
	var by_chunk := _group_transforms_by_stream_chunk(transforms, layout.tile_size)
	var physics := _physics_setup()
	for chunk in by_chunk.keys():
		var chunk_transforms: Array = by_chunk[chunk]
		var body := StaticBody3D.new()
		body.name = "%s_%d_%d" % [base_name, chunk.x, chunk.y]
		# 合并碰撞体的 shape 顶点使用地牢局部世界坐标，因此 body 本身留在根原点。
		# 显式保存几何所属 chunk，避免 streaming 按 body 原点把所有地板登记到 (0, 0)。
		body.set_meta("stream_physics_chunk", chunk)
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

## 墙体遮挡体按 streaming chunk 合并，避免每面墙一个 OccluderInstance3D 节点。
func _build_wall_occluders(layout: DungeonLayout, result: DungeonBuildResult) -> void:
	if not ProjectSettings.get_setting("rendering/occlusion_culling/use_occlusion_culling", false):
		return
	if result == null or result.terrain_root == null:
		return
	var container := Node3D.new()
	container.name = "WallOccluders"
	result.terrain_root.add_child(container)
	var boxes_by_chunk: Dictionary = {}
	var chunk_size := float(STREAM_CHUNK_SIZE_CELLS) * layout.tile_size
	for wall_key in result.wall_transforms_by_height:
		var group: Dictionary = result.wall_transforms_by_height[wall_key]
		var transforms: Array = group.get("transforms", [])
		if transforms.is_empty():
			continue
		var size: Vector3 = group.get("size", Vector3(layout.tile_size, 3.0, DOOR_SURROUND_THICKNESS))
		for t in transforms:
			var transform := t as Transform3D
			var chunk := Vector2i(
				floori(transform.origin.x / chunk_size),
				floori(transform.origin.z / chunk_size)
			)
			if not boxes_by_chunk.has(chunk):
				boxes_by_chunk[chunk] = []
			(boxes_by_chunk[chunk] as Array).append({
				"transform": transform,
				"size": size + Vector3(0.06, 0.06, 0.06),
			})
	for chunk in boxes_by_chunk.keys():
		var vertices := PackedVector3Array()
		var indices := PackedInt32Array()
		for spec in boxes_by_chunk[chunk]:
			_append_occluder_box(vertices, indices, spec["transform"], spec["size"])
		var array_occluder := ArrayOccluder3D.new()
		array_occluder.set_arrays(vertices, indices)
		var instance := OccluderInstance3D.new()
		instance.name = "WallOccluder_%d_%d" % [chunk.x, chunk.y]
		instance.occluder = array_occluder
		instance.visible = false
		instance.set_meta("stream_terrain_chunk", chunk)
		container.add_child(instance)
		if not result.terrain_chunks.has(chunk):
			result.terrain_chunks[chunk] = []
		(result.terrain_chunks[chunk] as Array).append(instance)

func _append_occluder_box(vertices: PackedVector3Array, indices: PackedInt32Array,
		transform: Transform3D, size: Vector3) -> void:
	var half := size * 0.5
	var base := vertices.size()
	for corner in [
		Vector3(-half.x, -half.y, -half.z), Vector3(half.x, -half.y, -half.z),
		Vector3(half.x, half.y, -half.z), Vector3(-half.x, half.y, -half.z),
		Vector3(-half.x, -half.y, half.z), Vector3(half.x, -half.y, half.z),
		Vector3(half.x, half.y, half.z), Vector3(-half.x, half.y, half.z),
	]:
		vertices.append(transform * corner)
	for index in [
		0, 1, 2, 0, 2, 3,
		4, 7, 6, 4, 6, 5,
		0, 3, 7, 0, 7, 4,
		1, 5, 6, 1, 6, 2,
		0, 4, 5, 0, 5, 1,
		3, 2, 6, 3, 6, 7,
	]:
		indices.append(base + index)

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
	# B3 第二版步4：真迁拼装逻辑——收集 door specs + 逐 instantiate DungeonDoor + 墝包围
	var tile_size: float = layout.tile_size
	var offset_x: float = -(float(layout.width) * tile_size) / 2.0
	var offset_z: float = -(float(layout.height) * tile_size) / 2.0
	var offset: Vector3 = Vector3(offset_x, 0, offset_z)
	var door_specs := {}
	for room in layout.rooms:
		for spec in _collect_room_door_specs(layout, room):
			var inside: Vector2i = spec["inside"]
			var outside: Vector2i = spec["outside"]
			var key := _door_edge_key(inside, outside)
			var leads_to_boss := _is_boss_room_cell(layout, inside) or _is_boss_room_cell(layout, outside)
			if door_specs.has(key):
				var existing: Dictionary = door_specs[key]
				existing["boss"] = bool(existing["boss"]) or leads_to_boss
				door_specs[key] = existing
			else:
				var door_spec: Dictionary = spec.duplicate()
				door_spec["boss"] = leads_to_boss
				door_specs[key] = door_spec
	var index := 0
	for key in door_specs.keys():
		_spawn_door_panel(door_specs[key], offset, tile_size, index, result, parent, layout)
		index += 1

# ── door panel（B3 第二版步3：迁自 procedural._spawn_door_panel） ──
## 产 DungeonDoor Node3D + 墙包围结构，挂 doors_root。信号接线转调 parent._on_door_pressure_action。
func _spawn_door_panel(spec: Dictionary, offset: Vector3, tile_size: float, index: int, result: DungeonBuildResult, parent: Node3D, layout: DungeonLayout) -> void:
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
	_spawn_door_wall_surround(door.name + "Surround", panel_pos, inside, outside, dir, boss, tile_size, result, parent, layout)
	door.configure(
		DungeonDoor.KIND_BOSS if boss else DungeonDoor.KIND_STANDARD,
		dir,
		_make_terrain_mat("BOSS_DOOR" if boss else "DOOR", Vector2(1.0, 1.0)),
		_make_terrain_mat("DOOR_SIDE", Vector2(DungeonDoor.THICKNESS, BOSS_DOOR_SIZE_METERS.y if boss else STANDARD_DOOR_SIZE_METERS.y)),
		_make_terrain_mat("DOOR_TOP", Vector2(BOSS_DOOR_SIZE_METERS.x * 0.5 if boss else STANDARD_DOOR_SIZE_METERS.x, DungeonDoor.THICKNESS))
	)
	if result.doors_root != null:
		result.doors_root.add_child(door)
	# Builder 先于 StreamingController 创建，必须写入 BuildResult；调用宿主注册会静默丢失。
	result.streamed_physics_nodes.append(door)
	if parent != null and parent.has_method("_on_door_pressure_action"):
		door.pressure_action.connect(parent._on_door_pressure_action)

# ── door wall surround（B3 第二版步3：迁自 procedural._spawn_door_wall_surround） ──
func _spawn_door_wall_surround(base_name: String, panel_pos: Vector3, inside: Vector2i, outside: Vector2i, dir: Vector2i, boss: bool, tile_size: float, result: DungeonBuildResult, parent: Node3D, layout: DungeonLayout) -> void:
	var door_size := BOSS_DOOR_SIZE_METERS if boss else STANDARD_DOOR_SIZE_METERS
	var wall_height := maxf(maxf(_height_at_cell_in_layout(inside, layout), _height_at_cell_in_layout(outside, layout)), door_size.y + 0.5)
	var side_width := maxf((tile_size - door_size.x) * 0.5, 0.0)
	if side_width <= 0.01:
		return
	var width_axis := Vector3(0, 0, 1) if dir.x != 0 else Vector3(1, 0, 0)
	var side_size := _door_surround_size(side_width, wall_height, dir, _rendering_thickness(parent))
	var side_offset := door_size.x * 0.5 + side_width * 0.5
	_spawn_door_wall_box(base_name + "LeftJamb", panel_pos - width_axis * side_offset + Vector3(0, wall_height * 0.5, 0), side_size, result, parent)
	_spawn_door_wall_box(base_name + "RightJamb", panel_pos + width_axis * side_offset + Vector3(0, wall_height * 0.5, 0), side_size, result, parent)
	var lintel_height := maxf(wall_height - door_size.y, 0.0)
	if lintel_height > 0.05:
		var lintel_size := _door_surround_size(door_size.x, lintel_height, dir, _rendering_thickness(parent))
		var lintel_pos := panel_pos + Vector3(0, door_size.y + lintel_height * 0.5, 0)
		_spawn_door_wall_box(base_name + "Lintel", lintel_pos, lintel_size, result, parent)

func _door_surround_size(width: float, height: float, dir: Vector2i, thickness: float) -> Vector3:
	# 迁自 procedural._door_surround_size（thickness 由调用方传，避反向依赖 parent._rendering_cfg）
	if dir.x != 0:
		return Vector3(thickness, height, width)
	return Vector3(width, height, thickness)

## 读 parent._rendering_cfg.door_surround_thickness（容错：parent 无此字段则用默认 0.2）
func _rendering_thickness(parent: Node3D) -> float:
	if parent != null and "_rendering_cfg" in parent:
		return parent._rendering_cfg.door_surround_thickness
	return 0.2

func _height_at_cell_in_layout(cell: Vector2i, layout: DungeonLayout) -> float:
	# 迁自 procedural._height_at_cell
	if cell.y < 0 or cell.y >= layout.heights.size():
		return 3.0
	if cell.x < 0 or cell.x >= layout.heights[cell.y].size():
		return 3.0
	return maxf(float(layout.heights[cell.y][cell.x]), 3.0)

# ── door 工具链（B3 第二版步4：迁自 procedural） ──
func _collect_room_door_specs(layout: DungeonLayout, room: Rect2i) -> Array:
	var candidates: Array = []
	var grid: Array = layout.grid
	for y in range(room.position.y, room.position.y + room.size.y):
		for x in range(room.position.x, room.position.x + room.size.x):
			if not _is_walkable_hazard_cell(grid, x, y):
				continue
			var cell := Vector2i(x, y)
			if not _is_on_room_edge(cell, room):
				continue
			for dir in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0)]:
				var outside: Vector2i = cell + dir
				if room.has_point(outside):
					continue
				if _is_walkable_hazard_cell(grid, outside.x, outside.y):
					if _is_door_location_supported(grid, cell, dir):
						candidates.append({"inside": cell, "outside": outside, "dir": dir})
	return _collapse_door_specs_by_contiguous_entry(candidates)

func _collapse_door_specs_by_contiguous_entry(candidates: Array) -> Array:
	var groups := {}
	for spec in candidates:
		var inside: Vector2i = spec["inside"]
		var dir: Vector2i = spec["dir"]
		var axis_value := inside.x if dir.x != 0 else inside.y
		var run_value := inside.y if dir.x != 0 else inside.x
		var key := "%d,%d:%d" % [dir.x, dir.y, axis_value]
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append({"sort": run_value, "spec": spec})
	var collapsed: Array = []
	for key in groups.keys():
		var entries: Array = groups[key]
		entries.sort_custom(func(a, b): return int(a["sort"]) < int(b["sort"]))
		var run: Array = []
		var previous := -999999
		for entry in entries:
			var value := int(entry["sort"])
			if not run.is_empty() and value != previous + 1:
				collapsed.append(_pick_middle_door_spec(run))
				run = []
			run.append(entry["spec"])
			previous = value
		if not run.is_empty():
			collapsed.append(_pick_middle_door_spec(run))
	return collapsed

func _pick_middle_door_spec(run: Array) -> Dictionary:
	if run.is_empty():
		return {}
	var index := int(run.size() / 2)
	return (run[index] as Dictionary).duplicate()

func _is_walkable_hazard_cell(grid: Array, x: int, y: int) -> bool:
	if y < 0 or y >= grid.size():
		return false
	if x < 0 or x >= grid[y].size():
		return false
	var cell_type: int = int(grid[y][x])
	return cell_type != 0 and cell_type != 2

func _is_on_room_edge(cell: Vector2i, room: Rect2i) -> bool:
	return cell.x == room.position.x or cell.y == room.position.y or cell.x == room.position.x + room.size.x - 1 or cell.y == room.position.y + room.size.y - 1

func _is_door_location_supported(grid: Array, cell: Vector2i, dir: Vector2i) -> bool:
	var side_dir_1: Vector2i
	var side_dir_2: Vector2i
	if dir.x != 0:
		side_dir_1 = Vector2i(0, -1)
		side_dir_2 = Vector2i(0, 1)
	else:
		side_dir_1 = Vector2i(-1, 0)
		side_dir_2 = Vector2i(1, 0)
	var inside_side_1 := cell + side_dir_1
	var inside_side_2 := cell + side_dir_2
	var has_wall_1 := _is_grid_wall(grid, inside_side_1.x, inside_side_1.y)
	var has_wall_2 := _is_grid_wall(grid, inside_side_2.x, inside_side_2.y)
	return has_wall_1 or has_wall_2

func _is_grid_wall(grid: Array, x: int, y: int) -> bool:
	if y < 0 or y >= grid.size():
		return true
	if x < 0 or x >= grid[y].size():
		return true
	return int(grid[y][x]) == 2

func _door_edge_key(a: Vector2i, b: Vector2i) -> String:
	if a.x < b.x or (a.x == b.x and a.y <= b.y):
		return "%d,%d:%d,%d" % [a.x, a.y, b.x, b.y]
	return "%d,%d:%d,%d" % [b.x, b.y, a.x, a.y]

func _is_boss_room_cell(layout: DungeonLayout, cell: Vector2i) -> bool:
	return layout.room_roles.has("boss") and (layout.room_roles["boss"] as Rect2i).has_point(cell)

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
	result.streamed_visual_nodes.append(mesh)
	# 碰撞体（StaticBody3D + BoxShape3D）挂 collision_root
	if result.collision_root != null:
		var body := StaticBody3D.new()
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		col.shape = shape
		body.add_child(col)
		body.name = name + "Collision"
		body.position = pos
		result.collision_root.add_child(body)
		result.streamed_physics_nodes.append(body)
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
		instance.set_meta("placement_role", "terrain_damage_anchor")
		instance.set_meta("kick_lane_dir", anchor.get("direction", Vector2i.ZERO))
		var room_index := int(anchor.get("room_index", -1))
		if room_index >= 0 and room_index < layout.rooms.size():
			instance.set_meta("hazard_room", layout.rooms[room_index])
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
		# zone 决定材料掉落池（原 procedural._spawn_prefab 注入）
		if "zone" in instance:
			instance.zone = layout.zone
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


# ── navigation mesh（迁自 procedural._build_navigation_mesh） ──
func _build_navigation_mesh(layout: DungeonLayout, result: DungeonBuildResult, parent: Node3D) -> void:
	if result == null or result.floor_transforms.is_empty() or parent == null:
		return
	# headless/gdUnit 下 bake 偶发 native crash；生产有窗口时再烘焙
	if DisplayServer.get_name() == "headless":
		return
	# 与默认 NavigationMap cell 对齐，避免 cell_height mismatch。
	# headless 下超大 obstruction bake 偶发 native crash，故限制规模并仅用地板面片。
	var region := NavigationRegion3D.new()
	region.name = "DungeonNavigationRegion"
	var nav_mesh := NavigationMesh.new()
	nav_mesh.agent_radius = PhysicsSetup.HUMANOID_COLLISION_RADIUS
	nav_mesh.agent_height = PhysicsSetup.HUMANOID_COLLISION_HEIGHT
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.25
	region.navigation_mesh = nav_mesh
	parent.add_child(region)
	var source_geometry_data := NavigationMeshSourceGeometryData3D.new()
	var floor_size := Vector3(layout.tile_size, 0.1, layout.tile_size)
	var floor_faces := PackedVector3Array()
	var max_floor_samples := 2048
	var floor_count := mini(result.floor_transforms.size(), max_floor_samples)
	for i in range(floor_count):
		var t: Transform3D = result.floor_transforms[i]
		_append_floor_top_face(floor_faces, t.origin, floor_size)
	if floor_faces.is_empty():
		return
	source_geometry_data.add_faces(floor_faces, Transform3D.IDENTITY)
	# 仅用地板可行走面；墙体 obstruction 在 headless 路径不稳定，生产可后续再开。
	# P-A：导航烘焙改异步可消除进场最长单帧 stall（ENABLE_ASYNC_NAVMESH_BAKE）。
	# 异步在后台线程填充 nav_mesh；完成前 NavigationAgent3D 查询返回空路径、自然等待，不影响寻路正确性。
	# 默认关闭（见 ENABLE_ASYNC_NAVMESH_BAKE 注释），开启前需窗口化冒烟测试确认敌人可寻路。
	# 异步方法名含 "bake_from_source_geometry_data" 前缀，perf 测试仍通过；缺失时回退同步分支。
	if ENABLE_ASYNC_NAVMESH_BAKE and NavigationServer3D.has_method("bake_from_source_geometry_data_async"):
		NavigationServer3D.bake_from_source_geometry_data_async(nav_mesh, source_geometry_data, Callable())
	else:
		NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source_geometry_data, Callable())

func _append_floor_top_face(faces: PackedVector3Array, center: Vector3, size: Vector3) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var p010 := center + Vector3(-hx, hy, -hz)
	var p110 := center + Vector3( hx, hy, -hz)
	var p111 := center + Vector3( hx, hy,  hz)
	var p011 := center + Vector3(-hx, hy,  hz)
	faces.append_array([p010, p110, p111, p010, p111, p011])

# ── decor scatter + torch + pillar（迁自 procedural._build_terrain_geometry 装饰段） ──
func _build_decor_and_torches(layout: DungeonLayout, result: DungeonBuildResult, parent: Node3D) -> void:
	if layout.is_empty() or result == null or parent == null:
		return
	var runtime_cfg := DungeonRuntimeConfig.default()
	var grid: Array = layout.grid
	var grid_width: int = grid[0].size() if grid.size() > 0 else 0
	var grid_height: int = grid.size()
	var tile_size: float = layout.tile_size
	var offset_x: float = -(float(grid_width) * tile_size) / 2.0
	var offset_z: float = -(float(grid_height) * tile_size) / 2.0
	var OFFSET := Vector3(offset_x, 0, offset_z)
	var preferred_spawn_cell := layout.player_spawn_cell
	var has_preferred_spawn := preferred_spawn_cell.x >= 0 and preferred_spawn_cell.y >= 0
	if not has_preferred_spawn and layout.room_roles.has("start"):
		preferred_spawn_cell = _rect_center_cell(layout.room_roles["start"])
		has_preferred_spawn = true
	var player_spawned := false
	var torch_zones := [0, 2, 3]
	var zone := layout.zone
	for y in range(grid.size()):
		for x in range(grid[y].size()):
			var cell_type: int = int(grid[y][x])
			var cell_pos := OFFSET + Vector3(x * tile_size, 0, y * tile_size)
			match cell_type:
				5:
					var room_h: float = float(layout.heights[y][x]) if y < layout.heights.size() and x < layout.heights[y].size() else 3.0
					var pillar_t := Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, room_h / 3.0, 1.0)), cell_pos)
					if not _spawn_batched_decor(result, parent, runtime_cfg, PILLAR_PREFAB.resource_path, pillar_t):
						var pillar := PILLAR_PREFAB.instantiate()
						pillar.position = cell_pos
						pillar.scale.y = room_h / 3.0
						if result.decor_root != null:
							result.decor_root.add_child(pillar)
						else:
							parent.add_child(pillar)
						_ensure_collision_on_instance(pillar)
						_configure_scene_object(pillar)
						result.streamed_physics_nodes.append(pillar)
				3:
					_spawn_random_decor(result, parent, runtime_cfg, cell_pos)
				_:
					pass
			if cell_type != 2 and cell_type != 0:
				if not player_spawned and cell_type == 1 and (not has_preferred_spawn or Vector2i(x, y) == preferred_spawn_cell):
					player_spawned = true
				elif player_spawned and not _is_start_room_cell(layout, Vector2i(x, y)):
					if zone in torch_zones:
						var directions := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0)]
						var torch_spawned := false
						for dir in directions:
							var nx = x + dir.x
							var ny = y + dir.y
							if nx >= 0 and nx < grid_width and ny >= 0 and ny < grid_height:
								if int(grid[ny][nx]) == 2:
									if randf() < 0.12:
										var h: float = float(result.wall_h_map.get(Vector2i(nx, ny), 3.0))
										_spawn_torch_on_wall(result, parent, cell_pos, dir, h, tile_size)
										torch_spawned = true
										break
						if not torch_spawned and randf() < 0.035:
							var scatter = Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))
							_spawn_random_decor(result, parent, runtime_cfg, cell_pos + scatter)
					elif randf() < 0.055:
						var scatter2 = Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))
						_spawn_random_decor(result, parent, runtime_cfg, cell_pos + scatter2)

func _is_start_room_cell(layout: DungeonLayout, cell: Vector2i) -> bool:
	return layout.room_roles.has("start") and (layout.room_roles["start"] as Rect2i).has_point(cell)

func _spawn_torch_on_wall(result: DungeonBuildResult, parent: Node3D, cell_pos: Vector3, wall_dir: Vector2i, wall_height: float, tile_size: float) -> void:
	var torch := TORCH_PREFAB.instantiate()
	var pos_offset := Vector3(wall_dir.x, 0, wall_dir.y) * (tile_size / 2.0)
	var clip_offset := -Vector3(wall_dir.x, 0, wall_dir.y) * 0.1
	var torch_y := clampf(wall_height * 0.45, 0.8, wall_height - 0.3)
	torch.position = cell_pos + pos_offset + clip_offset + Vector3(0, torch_y, 0)
	if wall_dir == Vector2i(0, -1):
		torch.rotation.y = PI
	elif wall_dir == Vector2i(0, 1):
		torch.rotation.y = 0.0
	elif wall_dir == Vector2i(1, 0):
		torch.rotation.y = PI / 2.0
	elif wall_dir == Vector2i(-1, 0):
		torch.rotation.y = -PI / 2.0
	if result.decor_root != null:
		result.decor_root.add_child(torch)
	else:
		parent.add_child(torch)
	_ensure_collision_on_instance(torch)
	_configure_scene_object(torch)
	result.streamed_physics_nodes.append(torch)
	_apply_distance_culling(torch, TORCH_VISIBILITY_RANGE_END)

func _spawn_random_decor(result: DungeonBuildResult, parent: Node3D, runtime_cfg: DungeonRuntimeConfig, pos: Vector3) -> void:
	var path := _pick_weighted(runtime_cfg.decor_config)
	if path == "":
		return
	if _spawn_batched_decor(result, parent, runtime_cfg, path, Transform3D(Basis.IDENTITY, pos)):
		return
	var prefab = load(path)
	if prefab == null:
		return
	var instance = prefab.instantiate()
	if not (instance is Node3D):
		if instance != null:
			instance.queue_free()
		return
	(instance as Node3D).position = pos
	if result.decor_root != null:
		result.decor_root.add_child(instance)
	else:
		parent.add_child(instance)
	_apply_distance_culling(instance as Node3D)
	_ensure_collision_on_instance(instance)
	_configure_scene_object(instance)
	result.streamed_physics_nodes.append(instance)

func _spawn_batched_decor(result: DungeonBuildResult, parent: Node3D, runtime_cfg: DungeonRuntimeConfig, path: String, transform: Transform3D) -> bool:
	if not runtime_cfg.batched_decor_scenes.has(path):
		return false
	var prefab := load(path)
	if not prefab is PackedScene:
		return false
	var cached_data := _get_batched_decor_cache(path, prefab as PackedScene)
	var local_bounds: AABB = cached_data["bounds"]
	if local_bounds.size == Vector3.ZERO:
		return false
	var world_bounds := transform * local_bounds
	var body := StaticBody3D.new()
	body.name = "%sCollision" % _decor_batch_name(path)
	body.position = world_bounds.position + world_bounds.size * 0.5
	body.collision_layer = SCENE_OBJECT_LAYER
	body.collision_mask = 0
	body.set_script(SCENE_OBJECT_SCRIPT)
	var shape := BoxShape3D.new()
	shape.size = world_bounds.size
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = shape
	body.add_child(collision, true)
	if result.decor_root != null:
		result.decor_root.add_child(body)
	else:
		parent.add_child(body)
	result.streamed_physics_nodes.append(body)
	if not result.batched_decor_transforms.has(path):
		result.batched_decor_transforms[path] = []
	(result.batched_decor_transforms[path] as Array).append(transform)
	return true

func _build_batched_decor_multi_meshes(layout: DungeonLayout, result: DungeonBuildResult, parent: Node3D) -> void:
	if result == null or result.batched_decor_transforms.is_empty():
		return
	var pending_batches: Dictionary = result.batched_decor_transforms.duplicate()
	result.batched_decor_transforms.clear()
	for path in pending_batches.keys():
		var root_transforms: Array = pending_batches[path]
		if root_transforms.is_empty():
			continue
		var prefab := load(String(path))
		if not prefab is PackedScene:
			continue
		var cached_data := _get_batched_decor_cache(String(path), prefab as PackedScene)
		var parts: Array[Dictionary] = []
		for part in cached_data["parts"]:
			parts.append(part)
		for batch in _build_combined_batched_mesh_parts(parts):
			_build_chunked_mesh_multimeshes(
				result,
				parent,
				layout.tile_size,
				"BatchedDecor_%s_%s" % [_decor_batch_name(String(path)), String(batch["name"])],
				root_transforms,
				batch["mesh"] as Mesh,
				batch["material"] as Material
			)

func _build_combined_batched_mesh_parts(parts: Array[Dictionary]) -> Array[Dictionary]:
	var material_batches := {}
	for part in parts:
		var material := part["material"] as Material
		var key := _batched_material_key(material)
		if not material_batches.has(key):
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			material_batches[key] = {
				"name": String(part["name"]),
				"material": material,
				"surface": surface,
			}
		var batch: Dictionary = material_batches[key]
		_append_mesh_to_surface(batch["surface"] as SurfaceTool, part["mesh"] as Mesh, part["transform"] as Transform3D)
	var out: Array[Dictionary] = []
	for batch2 in material_batches.values():
		var mesh := (batch2["surface"] as SurfaceTool).commit()
		if mesh == null:
			continue
		out.append({
			"name": String(batch2["name"]),
			"mesh": mesh,
			"material": batch2["material"],
		})
	return out

func _batched_material_key(material: Material) -> String:
	if material == null:
		return "mat:null"
	return "mat:%d" % material.get_instance_id()

func _append_mesh_to_surface(surface: SurfaceTool, mesh: Mesh, transform: Transform3D) -> void:
	if surface == null or mesh == null or mesh.get_surface_count() == 0:
		return
	var arrays := mesh.surface_get_arrays(0)
	var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var normals := arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
	var uvs := arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array
	var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	var index_count := indices.size() if not indices.is_empty() else vertices.size()
	for i in range(index_count):
		var vertex_index := int(indices[i]) if not indices.is_empty() else i
		if vertex_index < 0 or vertex_index >= vertices.size():
			continue
		if vertex_index < normals.size():
			surface.set_normal((transform.basis * normals[vertex_index]).normalized())
		if vertex_index < uvs.size():
			surface.set_uv(uvs[vertex_index])
		surface.add_vertex(transform * vertices[vertex_index])

func _collect_batched_mesh_parts(root: Node3D, node: Node, out: Array[Dictionary]) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			out.append({
				"name": String(mesh_instance.name),
				"mesh": mesh_instance.mesh,
				"material": mesh_instance.material_override,
				"transform": _node_transform_relative_to(root, mesh_instance),
			})
	for child in node.get_children():
		_collect_batched_mesh_parts(root, child, out)

func _node_transform_relative_to(root: Node3D, node: Node3D) -> Transform3D:
	var relative := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			relative = (current as Node3D).transform * relative
		current = current.get_parent()
	return relative

func _build_chunked_mesh_multimeshes(result: DungeonBuildResult, parent: Node3D, tile_size: float, base_name: String, transforms: Array, mesh: Mesh, material: Material) -> void:
	if transforms.is_empty() or mesh == null:
		return
	var chunks := _group_transforms_by_stream_chunk(transforms, tile_size)
	for chunk in chunks.keys():
		var chunk_transforms: Array = chunks[chunk]
		var mm_instance := MultiMeshInstance3D.new()
		mm_instance.name = "%s_%d_%d" % [base_name, chunk.x, chunk.y]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = chunk_transforms.size()
		for i in range(chunk_transforms.size()):
			mm.set_instance_transform(i, chunk_transforms[i])
		mm_instance.multimesh = mm
		mm_instance.material_override = material
		mm_instance.visible = false
		if result.decor_root != null:
			result.decor_root.add_child(mm_instance)
		else:
			parent.add_child(mm_instance)
		if not result.terrain_chunks.has(chunk):
			result.terrain_chunks[chunk] = []
		(result.terrain_chunks[chunk] as Array).append(mm_instance)
		result.streamed_visual_nodes.append(mm_instance)

func _decor_batch_name(path: String) -> String:
	return path.get_file().get_basename().replace(".", "_").replace("-", "_")

func _get_batched_decor_cache(path: String, prefab: PackedScene) -> Dictionary:
	if _batched_decor_cache.has(path):
		return _batched_decor_cache[path]
	var cached_data := {
		"bounds": AABB(),
		"parts": [],
	}
	if prefab == null:
		_batched_decor_cache[path] = cached_data
		return cached_data
	var template := prefab.instantiate()
	if not template is Node3D:
		if template != null:
			template.free()
		_batched_decor_cache[path] = cached_data
		return cached_data
	var template_root := template as Node3D
	if template_root.has_method("rebuild"):
		template_root.rebuild()
	cached_data["bounds"] = _combined_batched_mesh_aabb(template_root)
	var parts: Array[Dictionary] = []
	_collect_batched_mesh_parts(template_root, template_root, parts)
	cached_data["parts"] = parts
	template_root.free()
	_batched_decor_cache[path] = cached_data
	return cached_data

func _combined_batched_mesh_aabb(root: Node3D) -> AABB:
	var out_aabb := AABB()
	var has_bounds := false
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var aabb := _node_transform_relative_to(root, mesh_instance) * mesh_instance.get_aabb()
		if not has_bounds:
			out_aabb = aabb
			has_bounds = true
		else:
			out_aabb = out_aabb.merge(aabb)
	return out_aabb if has_bounds else AABB()

func _pick_weighted(weights: Dictionary) -> String:
	var total_weight := 0
	for key in weights:
		total_weight += int(weights[key])
	if total_weight <= 0:
		return ""
	var r = randi() % total_weight
	var cumulative_weight := 0
	for key2 in weights:
		cumulative_weight += int(weights[key2])
		if r < cumulative_weight:
			return str(key2)
	return ""

func _apply_distance_culling(node: Node3D, range_end: float = DECOR_VISIBILITY_RANGE_END) -> void:
	if node == null:
		return
	for gi in node.find_children("*", "GeometryInstance3D", true, false):
		var geom := gi as GeometryInstance3D
		geom.visibility_range_end = range_end
		geom.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

func _ensure_collision_on_instance(instance: Node) -> void:
	if instance == null:
		return
	if _has_physics_body(instance):
		return
	if not (instance is Node3D):
		return
	var node3d: Node3D = instance
	var meshes: Array = node3d.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		return
	var combined_aabb: AABB = AABB()
	var has_aabb: bool = false
	for m in meshes:
		var mi: MeshInstance3D = m
		var aabb: AABB = _mesh_aabb_in_node_space(node3d, mi)
		if aabb.size != Vector3.ZERO:
			if not has_aabb:
				combined_aabb = aabb
				has_aabb = true
			else:
				combined_aabb = combined_aabb.merge(aabb)
	if not has_aabb:
		return
	var body := StaticBody3D.new()
	body.name = instance.name + "Body"
	body.collision_layer = SCENE_OBJECT_LAYER
	body.collision_mask = 0
	body.set_script(SCENE_OBJECT_SCRIPT)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = combined_aabb.size
	col.shape = shape
	col.position = combined_aabb.position + combined_aabb.size * 0.5
	body.add_child(col, true)
	node3d.add_child(body, true)

func _has_physics_body(node: Node) -> bool:
	if node is PhysicsBody3D:
		return true
	for child in node.get_children():
		if _has_physics_body(child):
			return true
	return false

func _mesh_aabb_in_node_space(root: Node3D, mesh_instance: MeshInstance3D) -> AABB:
	if mesh_instance.mesh == null:
		return AABB()
	return _node_transform_relative_to(root, mesh_instance) * mesh_instance.get_aabb()

func _configure_scene_object(node: Node) -> void:
	if node is StaticBody3D:
		(node as StaticBody3D).collision_layer = SCENE_OBJECT_LAYER
		(node as StaticBody3D).collision_mask = 0
		if (node as StaticBody3D).get_script() == null:
			(node as StaticBody3D).set_script(SCENE_OBJECT_SCRIPT)
	for c in node.get_children():
		_configure_scene_object(c)
