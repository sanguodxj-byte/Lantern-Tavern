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
const HEIGHT_CONFIG := preload("res://scenes/expedition/dungeon_generation_config.gd")
const PILLAR_PREFAB := preload("res://scenes/props/dungeon/pillar.tscn")
const TORCH_PREFAB := preload("res://scenes/props/torch/torch.tscn")
const IRON_BAR_GRATE_PREFAB := preload("res://scenes/props/dungeon/decor/iron_bar_grate.tscn")
const FLOOR_CANDELABRUM_PREFAB := preload("res://scenes/props/dungeon/decor/floor_candelabrum.tscn")
const SCENE_OBJECT_SCRIPT := preload("res://scenes/props/scene_object.gd")
const SCENE_OBJECT_LAYER := 64
const DungeonRuntimeConfig := preload("res://scenes/expedition/dungeon_runtime_config.gd")
const DungeonSpawnFootprint := preload("res://scenes/expedition/dungeon_spawn_footprint.gd")
const VOXEL_LIGHTING := preload("res://globals/visual/voxel_lighting_adapter.gd")
const DECOR_VISIBILITY_RANGE_END := 60.0
const TORCH_VISIBILITY_RANGE_END := 35.0
const TORCH_ROOM_ANCHOR_COUNT := 2
const TORCH_RANDOM_SPAWN_PROBABILITY := 0.05
const TORCH_ZONES := [0, 2, 3]
const TERRAIN_WALL_BASE_FILL := 0.24
const TORCH_VISUAL_TOP_LOCAL_Y := 1.3
const TORCH_CEILING_CLEARANCE := 0.1
const TORCH_MIN_ROOT_HEIGHT_ABOVE_FLOOR := 0.8
const HAZARD_NAV_FOOTPRINT_M := {
	"spikes": 2.25,
	"acid": 2.25,
	"flame_vent": 1.5,
}

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
	# 阶段 9 条 1 步2：地形 Transform 收集迁入 builder（整数层墙体连通组件 + floor/wall/ceiling/transition），
	# 产出填 build_result.floor_transforms/ceiling_transforms/ceiling_transition_transforms_by_size/
	# wall_transforms_by_height/wall_h_map。
	# MultiMesh 批渲染 + merged collisions 暂留 procedural（步3-4 再迁），改读 build_result.* 而非旧类字段。
	_build_terrain(layout, result)
	_build_multi_meshes(layout, result)
	_build_collisions(layout, result)
	_build_wall_occluders(layout, result)
	_build_downstairs_portal(layout, result)
	_build_door_panels(layout, result, parent)
	_build_door_transitions(layout, result)
	_build_hazards(layout, result)
	_build_chests(layout, result)
	_build_extraction_portal(layout, result)
	_build_room_focuses(layout, result)
	_build_room_compositions(layout, result)
	_build_room_wall_architecture(layout, result)
	_build_planned_decor(layout, result, parent)
	_build_decor_and_torches(layout, result, parent)
	_build_batched_decor_multi_meshes(layout, result, parent)
	_build_navigation_mesh(layout, result, parent)
	return result

## 仅碰撞构建（架构审查 P0-2）：专用服务器权威地牢只需要静态墙体裁决——
## 不生成任何可见几何/门/装饰/导航/光照。与 build() 共用同一 _build_terrain
## 收集管线（floor/wall/ceiling Transform + wall_h_map），保证与客户端 layout
## 指纹/碰撞几何一致，使服务器 move_and_slide 真实阻挡穿墙。
func build_collision_only(layout: DungeonLayout, parent: Node3D) -> DungeonBuildResult:
	var result := DungeonBuildResult.new()
	if layout.is_empty() or parent == null or not is_instance_valid(parent):
		return result
	result.collision_root = _new_root("CollisionRoot", parent)
	_build_terrain(layout, result)
	_build_collisions(layout, result)
	return result

# ── terrain Transform 收集（阶段 9 条 1 步2） ─────────────────────
## 收集 floor/wall/ceiling/height-transition Transform 到 build_result，并按墙体连通组件预计算整数层 wall_h_map。
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
	var dungeon_offset := Vector3(offset_x, 0, offset_z)
	# 一个连通墙体只允许一个整数高度。局部传播会在厚墙或闭合外墙中留下
	# 高度台阶，因此先收集 4 邻接组件，再把相邻可行走格的最高层写回整组。
	result.wall_h_map = _build_wall_height_map(layout, grid, grid_width, grid_height)
	result.ceiling_transition_transforms_by_size = _build_ceiling_transition_map(
		layout, grid, grid_width, grid_height, dungeon_offset, _collect_door_edge_keys(layout)
	)
	# ── floor/wall/ceiling Transform 收集 ──
	# 必须与 MultiMesh/碰撞使用同一 0.1m 厚度，否则高度交界会留下半厚度错位。
	for y in range(grid_height):
		for x in range(grid_width):
			var cell_type: int = int(grid[y][x])
			var cell_pos := dungeon_offset + Vector3(x * tile_size, 0, y * tile_size)
			# floor 只覆盖可行走格。墙格虽然有视觉地板 transform 的历史产物，
			# 但不能进入导航源，否则导航多边形会落在墙体/角落内部。
			if _is_walkable_navigation_cell(cell_type):
				var ft := Transform3D()
				ft.origin = cell_pos - Vector3(0, 0.05, 0)
				result.floor_transforms.append(ft)
			# wall
			if cell_type == 2:
				var wall_height: float = float(result.wall_h_map.get(Vector2i(x, y), HEIGHT_CONFIG.MIN_CEILING_HEIGHT_METERS))
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
				var ceiling_height: float = _height_at_cell_in_layout(Vector2i(x, y), layout)
				var ct := Transform3D()
				ct.origin = cell_pos + Vector3(0, ceiling_height + CEILING_THICKNESS * 0.5, 0)
				result.ceiling_transforms.append(ct)

func _build_ceiling_transition_map(layout: DungeonLayout, grid: Array, grid_width: int,
		grid_height: int, offset: Vector3, door_edges: Dictionary) -> Dictionary:
	# 每对相邻可走格只检查一次，避免高度差收边重复生成两次。
	# 天花板盒体以 H + CEILING_THICKNESS / 2 为中心，实际占据 H..H+t；
	# 收边必须从低天花板的上表面开始，到高天花板的下表面结束。
	# 若从 raw H 开始，会与低天花板发生正体积重叠并产生 z-fighting。
	var transitions_by_size: Dictionary = {}
	for y in range(grid_height):
		for x in range(grid_width):
			var current_cell := Vector2i(x, y)
			if not _is_walkable_navigation_cell(int(grid[y][x])):
				continue
			var current_height := _height_at_cell_in_layout(current_cell, layout)
			var cell_pos := offset + Vector3(x * layout.tile_size, 0, y * layout.tile_size)
			for direction in [Vector2i(1, 0), Vector2i(0, 1)]:
				var neighbor: Vector2i = current_cell + direction
				if neighbor.x < 0 or neighbor.x >= grid_width or neighbor.y < 0 or neighbor.y >= grid_height:
					continue
				if not _is_walkable_navigation_cell(int(grid[neighbor.y][neighbor.x])):
					continue
				# 门洞自己的门垛/门楣负责填满此边界，避免和通用高度收边重叠。
				if door_edges.has(_door_edge_key(current_cell, neighbor)):
					continue
				var neighbor_height := _height_at_cell_in_layout(neighbor, layout)
				if is_equal_approx(current_height, neighbor_height):
					continue
				var lower_height := minf(current_height, neighbor_height)
				var higher_height := maxf(current_height, neighbor_height)
				var transition_bottom := lower_height + CEILING_THICKNESS
				var transition_height := higher_height - transition_bottom
				if transition_height <= 0.0:
					continue
				var transition_size := Vector3(
					DOOR_SURROUND_THICKNESS if direction.x != 0 else layout.tile_size,
					transition_height,
					layout.tile_size if direction.x != 0 else DOOR_SURROUND_THICKNESS
				)
				var transition := Transform3D()
				transition.origin = cell_pos + Vector3(float(direction.x), 0, float(direction.y)) * (layout.tile_size * 0.5)
				transition.origin.y = transition_bottom + transition_height * 0.5
				var key := _transition_segment_key(transition_size)
				if not transitions_by_size.has(key):
					transitions_by_size[key] = {"size": transition_size, "transforms": []}
				(transitions_by_size[key]["transforms"] as Array).append(transition)
	return transitions_by_size

func _collect_door_edge_keys(layout: DungeonLayout) -> Dictionary:
	var door_edges := {}
	for spec in _collect_layout_door_specs(layout):
		var inside: Vector2i = spec["inside"]
		var outside: Vector2i = spec["outside"]
		door_edges[_door_edge_key(inside, outside)] = true
	return door_edges

func _wall_segment_key(size: Vector3) -> String:
	return "%d,%d,%d" % [int(size.x), int(size.y), int(size.z)]

func _transition_segment_key(size: Vector3) -> String:
	return "%.3f,%.3f,%.3f" % [size.x, size.y, size.z]

func _build_wall_height_map(layout: DungeonLayout, grid: Array, grid_width: int, grid_height: int) -> Dictionary:
	var wall_h_map: Dictionary = {}
	var visited: Dictionary = {}
	var directions := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0)]
	for start_y in range(grid_height):
		for start_x in range(grid_width):
			var start := Vector2i(start_x, start_y)
			if int(grid[start_y][start_x]) != 2 or visited.has(start):
				continue
			var component: Array[Vector2i] = []
			var queue: Array[Vector2i] = [start]
			visited[start] = true
			var component_height := HEIGHT_CONFIG.MIN_CEILING_HEIGHT_METERS
			while not queue.is_empty():
				var cell: Vector2i = queue.pop_front()
				component.append(cell)
				for direction in directions:
					var neighbor: Vector2i = cell + direction
					if neighbor.x < 0 or neighbor.x >= grid_width or neighbor.y < 0 or neighbor.y >= grid_height:
						continue
					if int(grid[neighbor.y][neighbor.x]) == 2:
						if not visited.has(neighbor):
							visited[neighbor] = true
							queue.append(neighbor)
					elif _is_walkable_navigation_cell(int(grid[neighbor.y][neighbor.x])):
						component_height = maxf(component_height, _height_at_cell_in_layout(neighbor, layout))
			for cell in component:
				wall_h_map[cell] = HEIGHT_CONFIG.quantize_height(component_height)
	return wall_h_map

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
	# 3. 高度差收边：填满相邻 3/4/5m 天花板之间的竖向交界。
	for transition_key in result.ceiling_transition_transforms_by_size:
		var transition_group: Dictionary = result.ceiling_transition_transforms_by_size[transition_key]
		var transition_transforms: Array = transition_group.get("transforms", [])
		if transition_transforms.is_empty():
			continue
		var transition_size: Vector3 = transition_group.get("size", Vector3(DOOR_SURROUND_THICKNESS, 1.0, tile_size))
		var transition_mat := _make_terrain_mat("LINTEL", Vector2(maxf(transition_size.x, transition_size.z), transition_size.y))
		_build_chunked_multi_meshes(layout, result, "CeilingTransitionMultiMesh_%s" % transition_key.replace(",", "_"),
			transition_transforms, transition_size, transition_mat)
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

func _make_terrain_mat(tile_name: String, tile_repeat: Vector2,
		surface_profile: Dictionary = {}) -> ShaderMaterial:
	var profile := surface_profile.duplicate()
	# 墙面纹理的暗部需要保留石砖层次；地板仍使用通用较低填充，避免火把附近过曝。
	if not profile.has("voxel_base_fill") and ["WALL", "LINTEL", "DOOR", "BOSS_DOOR", "DOOR_SIDE", "DOOR_TOP"].has(tile_name):
		profile["voxel_base_fill"] = TERRAIN_WALL_BASE_FILL
	return TERRAIN_CFG.make_terrain_mat(tile_name, tile_repeat, profile)

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
	for transition_key in result.ceiling_transition_transforms_by_size:
		var transition_group: Dictionary = result.ceiling_transition_transforms_by_size[transition_key]
		var transition_transforms: Array = transition_group.get("transforms", [])
		if transition_transforms.is_empty():
			continue
		var transition_size: Vector3 = transition_group.get("size", Vector3(DOOR_SURROUND_THICKNESS, 1.0, tile_size))
		_build_merged_collision_group(layout, result, "CeilingTransitionCollisions_%s" % transition_key.replace(",", "_"),
			transition_transforms, transition_size)
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
	for chunk in by_chunk.keys():
		var chunk_transforms: Array = by_chunk[chunk]
		var body := StaticBody3D.new()
		body.name = "%s_%d_%d" % [base_name, chunk.x, chunk.y]
		# 合并碰撞体的 shape 顶点使用地牢局部世界坐标，因此 body 本身留在根原点。
		# 显式保存几何所属 chunk，避免 streaming 按 body 原点把所有地板登记到 (0, 0)。
		body.set_meta("stream_physics_chunk", chunk)
		body.collision_layer = PhysicsSetup.LAYER_ENVIRONMENT
		body.collision_mask = PhysicsSetup.MASK_ENVIRONMENT
		var col := CollisionShape3D.new()
		col.name = "MergedCollision"
		var shape := ConcavePolygonShape3D.new()
		# Merged terrain boxes are closed solid volumes. Players approach walls
		# from the walkable side, which can be the back side of their triangle
		# winding; without this flag a concave mesh can allow partial penetration.
		shape.backface_collision = true
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
	for transition_key in result.ceiling_transition_transforms_by_size:
		var transition_group: Dictionary = result.ceiling_transition_transforms_by_size[transition_key]
		var transition_size: Vector3 = transition_group.get("size", Vector3(DOOR_SURROUND_THICKNESS, 1.0, layout.tile_size))
		for t in transition_group.get("transforms", []):
			var transition_transform := t as Transform3D
			var transition_chunk := Vector2i(
				floori(transition_transform.origin.x / chunk_size),
				floori(transition_transform.origin.z / chunk_size)
			)
			if not boxes_by_chunk.has(transition_chunk):
				boxes_by_chunk[transition_chunk] = []
			(boxes_by_chunk[transition_chunk] as Array).append({
				"transform": transition_transform,
				"size": transition_size + Vector3(0.06, 0.06, 0.06),
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
	var best_pos := offset + Vector3(stairs_center.x * tile_size, layout.floor_height_at(stairs_center), stairs_center.y * tile_size)
	var root := Node3D.new()
	root.name = "DownstairsPortal"
	root.set_meta("topdown_kind", "stairs")
	root.position = best_pos
	result.interaction_root.add_child(root)
	result.streamed_visual_nodes.append(root)
	# 4 级下楼台阶。保留独立节点，便于俯视图标记和材质回归测试。
	var step_mat := TERRAIN_CFG.make_terrain_mat("BARONY_THRESHOLD", Vector2.ONE, {
		"world_aligned_uv": true,
		"meters_per_tile": 0.75,
		"albedo_tint": Color(0.88, 0.82, 0.74),
		"roughness": 0.94,
		"voxel_base_fill": 0.12,
	})
	var void_mat := TERRAIN_CFG.make_terrain_mat("BARONY_BOSS_SLAB", Vector2.ONE, {
		"world_aligned_uv": true,
		"meters_per_tile": 0.75,
		"albedo_tint": Color(0.18, 0.15, 0.14),
		"roughness": 0.98,
		"voxel_base_fill": 0.08,
	})
	var landing := MeshInstance3D.new()
	landing.name = "DownstairsLanding"
	landing.set_meta("topdown_kind", "stairs")
	var landing_mesh := BoxMesh.new()
	landing_mesh.size = Vector3(2.2, 0.12, 0.48)
	landing.mesh = landing_mesh
	landing.material_override = step_mat
	landing.position = Vector3(0, 0.06, -0.92)
	root.add_child(landing)
	for i in range(4):
		var step := MeshInstance3D.new()
		step.name = "DownstairsStep%d" % (i + 1)
		step.set_meta("topdown_kind", "stairs")
		var box := BoxMesh.new()
		box.size = Vector3(1.8, 0.14, 0.36)
		step.mesh = box
		step.material_override = step_mat
		step.position = Vector3(0, 0.04 + i * 0.035, -0.54 + i * 0.36)
		root.add_child(step)
	# 侧墙把台阶轮廓收成一个明确的下行井口，内侧与台阶边缘面接触。
	for side in [-1, 1]:
		var side_wall := MeshInstance3D.new()
		side_wall.name = "DownstairsSideWall%s" % ("L" if side < 0 else "R")
		side_wall.set_meta("topdown_kind", "stairs")
		var side_box := BoxMesh.new()
		side_box.size = Vector3(0.18, 0.48, 1.9)
		side_wall.mesh = side_box
		side_wall.material_override = step_mat
		side_wall.position = Vector3(side * 0.99, 0.24, 0.0)
		root.add_child(side_wall)
	var void_mesh := MeshInstance3D.new()
	void_mesh.name = "DownstairsVoid"
	void_mesh.set_meta("topdown_kind", "stairs")
	var void_box := BoxMesh.new()
	void_box.size = Vector3(1.78, 0.025, 0.36)
	void_mesh.mesh = void_box
	void_mesh.material_override = void_mat
	void_mesh.position = Vector3(0, 0.015, 0.72)
	root.add_child(void_mesh)
	# Area3D 节点也 instantiate（信号接线留 runtime）
	var area := Area3D.new()
	area.name = "DownstairsArea"
	area.set_meta("topdown_kind", "stairs")
	area.set_meta("interaction_type", "next_floor")
	area.collision_layer = PhysicsSetup.LAYER_TRIGGER
	area.collision_mask = PhysicsSetup.LAYER_PLAYER
	area.monitoring = true
	area.monitorable = true
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
	var door_specs := _collect_layout_door_specs(layout)
	var index := 0
	for door_spec in door_specs:
		_spawn_door_panel(door_spec, offset, tile_size, index, result, parent, layout)
		index += 1

func _build_door_transitions(layout: DungeonLayout, result: DungeonBuildResult) -> void:
	if result == null or result.doors_root == null:
		return
	var index := 0
	for spec in _collect_layout_door_specs(layout):
		var inside: Vector2i = spec["inside"]
		var outside: Vector2i = spec["outside"]
		var direction: Vector2i = spec["dir"]
		var root := Node3D.new()
		root.name = "DoorTransition_%03d" % index
		root.position = _cell_to_world(inside, layout)
		root.set_meta("topdown_kind", "door_transition")
		root.set_meta("inside_cell", inside)
		root.set_meta("outside_cell", outside)
		root.set_meta("door_transition", true)
		result.doors_root.add_child(root)
		var inside_offset := Vector3.ZERO
		var outside_offset := Vector3(float(direction.x) * layout.tile_size, 0.0, float(direction.y) * layout.tile_size)
		_add_door_transition_panel(root, "InsideFloor", inside_offset, _composition_material("bridge", layout.tile_size))
		_add_door_transition_panel(root, "OutsideFloor", outside_offset, _composition_material("platform", layout.tile_size))
		var light := OmniLight3D.new()
		light.name = "DoorAxisLight"
		light.light_color = Color(0.22, 0.70, 0.92)
		light.light_energy = 0.35
		light.omni_range = 4.0
		light.shadow_enabled = false
		light.position = Vector3(float(direction.x) * 1.0, 0.8, float(direction.y) * 1.0)
		root.add_child(light)
		result.streamed_visual_nodes.append(root)
		index += 1

func _add_door_transition_panel(root: Node3D, name: String, offset: Vector3, material: Material) -> void:
	var panel := MeshInstance3D.new()
	panel.name = name
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.2, 0.035, 2.2)
	panel.mesh = mesh
	panel.position = offset + Vector3(0.0, 0.025, 0.0)
	panel.material_override = material
	root.add_child(panel)

# ── door panel（B3 第二版步3：迁自 procedural._spawn_door_panel） ──
## 产 DungeonDoor Node3D + 墙包围结构，挂 doors_root。信号接线转调 parent._on_door_pressure_action。
func _spawn_door_panel(spec: Dictionary, offset: Vector3, tile_size: float, index: int, result: DungeonBuildResult, parent: Node3D, layout: DungeonLayout) -> void:
	var inside: Vector2i = spec["inside"]
	var outside: Vector2i = spec["outside"]
	var dir: Vector2i = spec["dir"]
	var boss := bool(spec["boss"])
	var door_size := DungeonDoor.size_for_kind(DungeonDoor.KIND_BOSS if boss else DungeonDoor.KIND_STANDARD)
	var cell_pos := offset + Vector3(inside.x * tile_size, 0.0, inside.y * tile_size)
	var panel_pos := cell_pos + Vector3(float(dir.x), 0.0, float(dir.y)) * (tile_size * 0.5)
	var door := DUNGEON_DOOR_SCRIPT.new() as DungeonDoor
	door.name = ("BossDoor_%03d" if boss else "Door_%03d") % index
	door.position = panel_pos
	door.set_meta("inside_cell", inside)
	door.set_meta("outside_cell", outside)
	door.set_meta("door_size_m", door_size)
	_spawn_door_wall_surround(door.name + "Surround", panel_pos, inside, outside, dir, boss, tile_size, result, parent, layout)
	door.configure(
		DungeonDoor.KIND_BOSS if boss else DungeonDoor.KIND_STANDARD,
		dir,
		_make_terrain_mat("BOSS_DOOR" if boss else "DOOR", Vector2(1.0, 1.0)),
		_make_terrain_mat("DOOR_SIDE", Vector2(DungeonDoor.THICKNESS, door_size.y)),
		# 顶面按 1m 体素纹理单元重复；boss 门的 2m 宽度由 tile_span
		# 表达，不能把宽度再折半写入 repeat，否则普通门会得到 0.5m 的采样比例。
		_make_terrain_mat("DOOR_TOP", Vector2(1.0, DungeonDoor.THICKNESS))
	)
	if result.doors_root != null:
		result.doors_root.add_child(door)
	# Builder 先于 StreamingController 创建，必须写入 BuildResult；调用宿主注册会静默丢失。
	result.streamed_physics_nodes.append(door)
	if parent != null and parent.has_method("_on_door_pressure_action"):
		door.pressure_action.connect(parent._on_door_pressure_action)

# ── door wall surround（B3 第二版步3：迁自 procedural._spawn_door_wall_surround） ──
func _spawn_door_wall_surround(base_name: String, panel_pos: Vector3, inside: Vector2i, outside: Vector2i, dir: Vector2i, boss: bool, tile_size: float, result: DungeonBuildResult, parent: Node3D, layout: DungeonLayout) -> void:
	var door_size := DungeonDoor.size_for_kind(DungeonDoor.KIND_BOSS if boss else DungeonDoor.KIND_STANDARD)
	if door_size.x >= tile_size:
		push_error("[DungeonSceneBuilder] door width must fit one tile: width=%f tile=%f" % [door_size.x, tile_size])
		return
	# The navmesh and enemy collision envelope are built for the largest enemy.
	# A 2m visual doorway otherwise leaves a valid A* route that physically traps
	# huge enemies under the lintel.
	var max_enemy_height := PhysicsSetup.get_character_capsule_height("huge")
	var door_clearance := maxf(door_size.y, max_enemy_height)
	var wall_height := maxf(
		maxf(_height_at_cell_in_layout(inside, layout), _height_at_cell_in_layout(outside, layout)),
		door_clearance)
	var side_width := DungeonDoor.side_wall_width(tile_size, DungeonDoor.KIND_BOSS if boss else DungeonDoor.KIND_STANDARD)
	if side_width <= 0.01:
		return
	var width_axis := Vector3(0, 0, 1) if dir.x != 0 else Vector3(1, 0, 0)
	var side_size := _door_surround_size(side_width, wall_height, dir, _rendering_thickness(parent))
	var side_offset := door_size.x * 0.5 + side_width * 0.5
	_spawn_door_wall_box(base_name + "LeftJamb", panel_pos - width_axis * side_offset + Vector3(0, wall_height * 0.5, 0), side_size, result, parent)
	_spawn_door_wall_box(base_name + "RightJamb", panel_pos + width_axis * side_offset + Vector3(0, wall_height * 0.5, 0), side_size, result, parent)
	# 最低 2m 层高与 2m 门高重合时仍保留一条薄门楣，避免门洞失去
	# 完整的左右门垛 + 门楣语义；它落在天花板厚度/墙体交界内，不改变通行高度。
	var lintel_height := maxf(wall_height - door_clearance, 0.05)
	if lintel_height > 0.0:
		var lintel_size := _door_surround_size(door_size.x, lintel_height, dir, _rendering_thickness(parent))
		var lintel_pos := panel_pos + Vector3(0, door_clearance + lintel_height * 0.5, 0)
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
		return HEIGHT_CONFIG.MIN_CEILING_HEIGHT_METERS
	if cell.x < 0 or cell.x >= layout.heights[cell.y].size():
		return HEIGHT_CONFIG.MIN_CEILING_HEIGHT_METERS
	return HEIGHT_CONFIG.quantize_height(float(layout.heights[cell.y][cell.x]))

# ── door 工具链（B3 第二版步4：迁自 procedural） ──
func _collect_room_door_specs(layout: DungeonLayout, room: Rect2i, allow_open_support: bool = false) -> Array:
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
					if _is_inside_another_room(layout, outside, room):
						continue
					if allow_open_support or _is_door_location_supported(grid, cell, dir):
						candidates.append({"inside": cell, "outside": outside, "dir": dir})
	var collapsed := _collapse_door_specs_by_contiguous_entry(candidates)
	var supported: Array = []
	for spec in collapsed:
		if allow_open_support or _is_door_location_supported(grid, spec["inside"], spec["dir"]):
			supported.append(spec)
	return supported

func _collect_layout_door_specs(layout: DungeonLayout) -> Array[Dictionary]:
	if not layout.door_specs.is_empty():
		return layout.door_specs
	var by_edge: Dictionary = {}
	for room in layout.rooms:
		var room_specs := _collect_room_door_specs(layout, room)
		# Boss set-piece/merged-room corridors can erase both side walls at the
		# intended entrance. Preserve the boss gate by relaxing only that room's
		# support check when its strict candidate list is empty.
		if room_specs.is_empty() and layout.room_roles.has("boss") and room == layout.room_roles["boss"]:
			room_specs = _collect_room_door_specs(layout, room, true)
		for spec in room_specs:
			var inside: Vector2i = spec["inside"]
			var outside: Vector2i = spec["outside"]
			var key := _door_edge_key(inside, outside)
			var leads_to_boss := _is_boss_room_cell(layout, inside) or _is_boss_room_cell(layout, outside)
			if by_edge.has(key):
				var existing: Dictionary = by_edge[key]
				existing["boss"] = bool(existing.get("boss", false)) or leads_to_boss
				by_edge[key] = existing
			else:
				var door_spec: Dictionary = spec.duplicate()
				door_spec["boss"] = leads_to_boss
				by_edge[key] = door_spec
	var result: Array[Dictionary] = []
	for key in by_edge.keys():
		result.append(by_edge[key])
	layout.door_specs = result.duplicate(true)
	return layout.door_specs

func _is_inside_another_room(layout: DungeonLayout, cell: Vector2i, room: Rect2i) -> bool:
	for other_room in layout.rooms:
		if other_room == room:
			continue
		if other_room.has_point(cell):
			return true
	return false

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
	if grid == null or grid.is_empty() or dir == Vector2i.ZERO:
		return false
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
	# 门洞必须由两侧墙体共同支撑；单侧开口会把门框悬在房间边缘，
	# 也会让门周围的遮挡/碰撞与地形断开。
	return has_wall_1 and has_wall_2

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
	mesh.set_meta("voxel_grid_size_m", size)
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
		body.set_meta("door_surround", true)
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
		instance.position = _cell_to_world(cell, layout)
		instance.set_meta("hazard_anchor", true)
		instance.set_meta("topdown_kind", "hazard")
		instance.set_meta("hazard_cell", cell)
		instance.set_meta("hazard_type", String(anchor["hazard_type"]))
		instance.set_meta("placement_role", "terrain_damage_anchor")
		instance.set_meta("kick_lane_dir", anchor.get("direction", Vector2i.ZERO))
		_configure_hazard_placement(instance, String(anchor["hazard_type"]), anchor)
		instance.position.y = layout.floor_height_at(cell)
		var room_index := int(anchor.get("room_index", -1))
		if room_index >= 0 and room_index < layout.rooms.size():
			instance.set_meta("hazard_room", layout.rooms[room_index])
		result.hazards_root.add_child(instance)
		result.streamed_visual_nodes.append(instance)
		result.streamed_physics_nodes.append(instance)
		_build_hazard_warning(layout, result, cell, String(anchor["hazard_type"]))

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
	for chest_index in range(layout.chest_spawn_specs.size()):
		var spec: Dictionary = layout.chest_spawn_specs[chest_index]
		var chest_type: String = spec["chest_type"]
		var prefab := _chest_prefab_for(chest_type)
		if prefab == null:
			continue
		var instance := prefab.instantiate() as Node3D
		if instance == null:
			continue
		var cell: Vector2i = spec["cell"]
		instance.position = _cell_to_world(cell, layout, "chest", chest_index)
		if not _reserve_spawn_footprint(result, instance.position,
				DungeonSpawnFootprint.half_extents_for("chest", chest_type), "chest:%s" % chest_type):
			instance.queue_free()
			continue
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

func _build_room_focuses(layout: DungeonLayout, result: DungeonBuildResult) -> void:
	if result == null or result.decor_root == null:
		return
	for index in range(layout.room_focus_specs.size()):
		var spec: Dictionary = layout.room_focus_specs[index]
		var cell: Vector2i = spec.get("cell", Vector2i(-1, -1))
		if not layout.is_floor_cell(cell):
			continue
		var focus_kind := String(spec.get("focus_kind", "waystone"))
		var root := Node3D.new()
		root.name = "RoomFocus_%03d_%s" % [index, focus_kind]
		root.position = _cell_to_world(cell, layout)
		if not _reserve_spawn_footprint(result, root.position,
				DungeonSpawnFootprint.half_extents_for("focus", focus_kind), "focus:%s" % focus_kind):
			root.queue_free()
			continue
		root.set_meta("topdown_kind", "terrain_feature")
		root.set_meta("room_focus", true)
		root.set_meta("focus_kind", focus_kind)
		root.set_meta("focus_cell", cell)
		result.decor_root.add_child(root)
		_build_focus_geometry(root, focus_kind)
		result.streamed_visual_nodes.append(root)

func _build_focus_geometry(root: Node3D, focus_kind: String) -> void:
	var accent := Color(0.78, 0.31, 0.16)
	var secondary := Color(0.33, 0.42, 0.48)
	match focus_kind:
		"boss_altar":
			accent = Color(0.90, 0.18, 0.08)
			secondary = Color(0.36, 0.12, 0.10)
			_add_focus_cylinder(root, "BossAltar", 0.95, 0.24, 0.12, _focus_material(secondary))
			_add_focus_cylinder(root, "BossCore", 0.34, 0.42, 0.22, _focus_material(accent, true))
			_add_focus_light(root, accent, 0.8, 5.5)
			for offset in [Vector3(-0.70, 0.08, -0.70), Vector3(0.70, 0.08, -0.70), Vector3(-0.70, 0.08, 0.70), Vector3(0.70, 0.08, 0.70)]:
				_add_focus_box(root, "BossRune", Vector3(0.28, 0.08, 0.28), offset, _focus_material(accent, true))
		"stairs_shrine":
			accent = Color(0.12, 0.72, 0.78)
			_add_focus_cylinder(root, "StairsShrine", 0.88, 0.16, 0.08, _focus_material(secondary))
			for offset in [Vector3(-0.72, 0.10, 0.0), Vector3(0.72, 0.10, 0.0), Vector3(0.0, 0.10, -0.72), Vector3(0.0, 0.10, 0.72)]:
				_add_focus_box(root, "StairsRune", Vector3(0.30, 0.10, 0.30), offset, _focus_material(accent, true))
			_add_focus_light(root, accent, 0.45, 4.0)
		"ritual_circle":
			accent = Color(0.68, 0.20, 0.76)
			_add_focus_cylinder(root, "RitualCenter", 0.30, 0.18, 0.09, _focus_material(accent, true))
			for offset in [Vector3(-0.82, 0.06, 0.0), Vector3(0.82, 0.06, 0.0), Vector3(0.0, 0.06, -0.82), Vector3(0.0, 0.06, 0.82)]:
				_add_focus_box(root, "RitualMark", Vector3(0.24, 0.06, 0.52), offset, _focus_material(accent, true))
			_add_focus_light(root, accent, 0.32, 3.5)
		"resource_cluster":
			accent = Color(0.28, 0.78, 0.40)
			for item in [[-0.48, 0.18, -0.20, 0.24], [0.0, 0.24, 0.12, 0.32], [0.48, 0.15, -0.08, 0.20]]:
				_add_focus_cylinder(root, "ResourceShard", 0.20, float(item[1]), float(item[0]), _focus_material(accent, true), Vector3(float(item[2]), 0.0, float(item[3])))
		"guard_post":
			accent = Color(0.72, 0.46, 0.18)
			_add_focus_box(root, "GuardCrossbar", Vector3(1.45, 0.18, 0.22), Vector3(0.0, 0.10, 0.0), _focus_material(secondary))
			_add_focus_cylinder(root, "GuardPost", 0.20, 0.70, 0.16, _focus_material(accent), Vector3(-0.58, 0.35, 0.0))
			_add_focus_cylinder(root, "GuardPost", 0.20, 0.70, 0.16, _focus_material(accent), Vector3(0.58, 0.35, 0.0))
		"battle_cross":
			accent = Color(0.72, 0.24, 0.12)
			for offset in [Vector3(-0.55, 0.10, -0.55), Vector3(0.55, 0.10, 0.55)]:
				_add_focus_box(root, "BattleMarker", Vector3(0.72, 0.18, 0.24), offset, _focus_material(accent, true))
		"treasure_niche":
			accent = Color(0.88, 0.62, 0.18)
			_add_focus_cylinder(root, "TreasureStand", 0.52, 0.16, 0.08, _focus_material(secondary))
			_add_focus_box(root, "TreasureMark", Vector3(0.42, 0.12, 0.42), Vector3(0.0, 0.14, 0.0), _focus_material(accent, true))
		"cliff_overlook":
			accent = Color(0.76, 0.34, 0.14)
			secondary = Color(0.24, 0.30, 0.34)
			_add_focus_box(root, "CliffMarker", Vector3(1.25, 0.16, 0.32), Vector3(0.0, 0.10, 0.0), _focus_material(secondary, false, "BARONY_WALL"))
			_add_focus_box(root, "CliffMarkerEdge", Vector3(0.32, 0.28, 0.52), Vector3(-0.48, 0.20, 0.0), _focus_material(accent, true))
			_add_focus_box(root, "CliffMarkerEdge", Vector3(0.32, 0.28, 0.52), Vector3(0.48, 0.20, 0.0), _focus_material(accent, true))
		"waystone":
			accent = Color(0.36, 0.56, 0.68)
			_add_focus_cylinder(root, "Waystone", 0.28, 0.55, 0.18, _focus_material(accent, true))

func _focus_material(color: Color, light_source: bool = false, tile_name: String = "") -> ShaderMaterial:
	var resolved_tile := tile_name
	if resolved_tile.is_empty():
		resolved_tile = "PORTAL" if light_source else "BARONY_PLATFORM"
	return TERRAIN_CFG.make_terrain_mat(resolved_tile, Vector2.ONE, {
		"world_aligned_uv": true,
		"meters_per_tile": 0.5,
		"albedo_tint": color,
		# Procedural focus geometry is not a light source. Nearby OmniLight3D nodes
		# provide illumination; the mesh itself stays ordinary lit PBR.
		"emission_strength": 0.0,
		"roughness": 0.88 if light_source else 0.94,
		"voxel_base_fill": 0.09 if light_source else 0.12,
	})

func _add_focus_box(root: Node3D, name: String, size: Vector3, offset: Vector3, material: Material) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = name
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.position = offset
	mesh_instance.material_override = material
	root.add_child(mesh_instance)

func _add_focus_cylinder(root: Node3D, name: String, radius: float, height: float, yaw: float, material: Material, offset: Vector3 = Vector3.ZERO) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius * 0.86
	mesh.height = height
	mesh.radial_segments = 8
	mesh_instance.mesh = mesh
	mesh_instance.position = offset
	mesh_instance.rotation.y = yaw
	mesh_instance.material_override = material
	root.add_child(mesh_instance)

func _add_focus_light(root: Node3D, color: Color, energy: float, range_value: float) -> void:
	var light := OmniLight3D.new()
	light.name = "FocusLight"
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_value
	light.shadow_enabled = false
	light.position.y = 0.8
	root.add_child(light)

func _build_room_compositions(layout: DungeonLayout, result: DungeonBuildResult) -> void:
	if result == null or result.decor_root == null:
		return
	for spec in layout.room_composition_specs:
		var room_index := int(spec.get("room_index", -1))
		var kind := String(spec.get("composition_kind", "battle"))
		for cell in spec.get("cover_cells", []):
			var cover_cell: Vector2i = cell
			var cover_pos := _cell_to_world(cover_cell, layout) + Vector3(0.0, 0.4, 0.0)
			_add_composition_box(result, "RoomCover_%d_%s" % [room_index, str(cover_cell)], cover_pos,
				Vector3(1.45, 0.8, 1.45), _composition_material("cover", layout.tile_size), "cover", PhysicsSetup.LAYER_SCENE_OBJECT)
		if kind == "cliff":
			_build_cliff_geometry(layout, result, room_index, spec)
		else:
			for cell in spec.get("platform_cells", []):
				var platform_cell: Vector2i = cell
				var platform_height := float(spec.get("elevation_m", 1.0))
				var platform_pos := _cell_to_world(platform_cell, layout) + Vector3(0.0, -layout.floor_height_at(platform_cell) + platform_height * 0.5, 0.0)
				_add_composition_box(result, "Platform_%d_%s" % [room_index, str(platform_cell)], platform_pos,
					Vector3(layout.tile_size, platform_height, layout.tile_size), _composition_material("platform", layout.tile_size), "platform", PhysicsSetup.LAYER_ENVIRONMENT)
		for cell in spec.get("bridge_cells", []):
			var bridge_cell: Vector2i = cell
			var bridge_height := float(spec.get("elevation_m", 1.0))
			var bridge_pos := _cell_to_world(bridge_cell, layout) + Vector3(0.0, -layout.floor_height_at(bridge_cell) + bridge_height * 0.5, 0.0)
			_add_composition_box(result, "Bridge_%d_%s" % [room_index, str(bridge_cell)], bridge_pos,
				Vector3(layout.tile_size, bridge_height, layout.tile_size * 0.72), _composition_material("bridge", layout.tile_size), "bridge", PhysicsSetup.LAYER_ENVIRONMENT)
		for ramp_spec in spec.get("ramp_specs", []):
			_build_ramp(layout, result, room_index, ramp_spec, float(spec.get("elevation_m", 1.0)))
		if kind != "cliff":
			for edge in spec.get("boundary_edges", []):
				_build_elevation_boundary(layout, result, room_index, edge, float(spec.get("elevation_m", 1.0)))


func _build_cliff_geometry(layout: DungeonLayout, result: DungeonBuildResult, room_index: int, spec: Dictionary) -> void:
	var cliff_height := float(spec.get("elevation_m", 1.0))
	for cell_value in spec.get("cliff_cells", spec.get("platform_cells", [])):
		var cliff_cell: Vector2i = cell_value
		var base_position := _cell_to_world(cliff_cell, layout) - Vector3(0.0, layout.floor_height_at(cliff_cell), 0.0)
		var top_position := base_position + Vector3(0.0, cliff_height * 0.5, 0.0)
		_add_composition_box(result, "CliffTop_%d_%s" % [room_index, str(cliff_cell)], top_position,
			Vector3(layout.tile_size, cliff_height, layout.tile_size),
			_composition_material("cliff_top", layout.tile_size), "platform", PhysicsSetup.LAYER_ENVIRONMENT)
	for edge in spec.get("cliff_edges", spec.get("boundary_edges", [])):
		_build_cliff_boundary(layout, result, room_index, edge, cliff_height)


func _build_cliff_boundary(layout: DungeonLayout, result: DungeonBuildResult, room_index: int, edge: Dictionary, elevation: float) -> void:
	var cell: Vector2i = edge.get("cell", Vector2i(-1, -1))
	var direction: Vector2i = edge.get("dir", Vector2i.ZERO)
	if cell.x < 0 or direction == Vector2i.ZERO:
		return
	var depth := 0.18
	var base_position := _cell_to_world(cell, layout) - Vector3(0.0, layout.floor_height_at(cell), 0.0)
	var outward := Vector3(float(direction.x), 0.0, float(direction.y))
	var center := base_position + outward * (layout.tile_size * 0.5 + depth * 0.5) + Vector3(0.0, elevation * 0.5, 0.0)
	var size := Vector3(depth, elevation, layout.tile_size) if direction.x != 0 else Vector3(layout.tile_size, elevation, depth)
	_add_composition_box(result, "CliffFace_%d_%s_%s" % [room_index, str(cell), str(direction)], center,
		size, _composition_material("cliff_face", layout.tile_size), "boundary", PhysicsSetup.LAYER_ENVIRONMENT)

func _add_composition_box(result: DungeonBuildResult, name: String, pos: Vector3, size: Vector3,
		material: Material, topdown_kind: String, collision_layer: int) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = name
	mesh_instance.set_meta("topdown_kind", topdown_kind)
	mesh_instance.set_meta("composition_geometry", true)
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.position = pos
	mesh_instance.material_override = material
	result.decor_root.add_child(mesh_instance)
	result.streamed_visual_nodes.append(mesh_instance)
	var body := StaticBody3D.new()
	body.name = name + "Collision"
	body.set_meta("composition_kind", topdown_kind)
	body.collision_layer = collision_layer
	body.collision_mask = PhysicsSetup.MASK_ENVIRONMENT
	body.position = pos
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	result.collision_root.add_child(body)
	result.streamed_physics_nodes.append(body)

func _build_elevation_boundary(layout: DungeonLayout, result: DungeonBuildResult, room_index: int, edge: Dictionary, elevation: float) -> void:
	var cell: Vector2i = edge.get("cell", Vector2i(-1, -1))
	var direction: Vector2i = edge.get("dir", Vector2i.ZERO)
	if cell.x < 0 or direction == Vector2i.ZERO:
		return
	var center := _cell_to_world(cell, layout) + Vector3(float(direction.x) * layout.tile_size * 0.5, 0.45, float(direction.y) * layout.tile_size * 0.5)
	var size := Vector3(0.18, 0.9, layout.tile_size) if direction.x != 0 else Vector3(layout.tile_size, 0.9, 0.18)
	_add_composition_box(result, "ElevationBoundary_%d_%s_%s" % [room_index, str(cell), str(direction)], center,
		size, _composition_material("boundary", layout.tile_size), "boundary", PhysicsSetup.LAYER_ENVIRONMENT)

func _composition_material(kind: String, tile_size: float) -> Material:
	var tile_name := "WALL"
	match kind:
		"platform":
			tile_name = "BARONY_PLATFORM"
		"bridge":
			tile_name = "BARONY_FLOOR"
		"boundary":
			tile_name = "BARONY_WALL"
		"cliff_top":
			tile_name = "BARONY_PLATFORM"
		"cliff_face":
			tile_name = "BARONY_WALL"
		"cover":
			tile_name = "BARONY_WALL"
	var profile := {
		"world_aligned_uv": true,
		"meters_per_tile": 1.0,
		"roughness": 0.94,
		"voxel_base_fill": 0.12,
	}
	if kind == "cliff_top":
		profile["albedo_tint"] = Color(0.42, 0.48, 0.48)
		profile["voxel_base_fill"] = 0.14
	elif kind == "cliff_face":
		profile["albedo_tint"] = Color(0.27, 0.30, 0.32)
		profile["voxel_base_fill"] = 0.10
	return DungeonTerrainConfig.make_terrain_mat(tile_name, Vector2(tile_size, tile_size), profile)

func _build_room_wall_architecture(layout: DungeonLayout, result: DungeonBuildResult) -> void:
	if layout == null or result == null or result.decor_root == null or layout.zone != 0:
		return
	var door_cells: Dictionary = {}
	for door_spec in _collect_layout_door_specs(layout):
		door_cells[door_spec.get("inside", Vector2i(-1, -1))] = true
		door_cells[door_spec.get("outside", Vector2i(-1, -1))] = true
	var stone_material := _composition_material("boundary", layout.tile_size)
	for room_index in range(layout.rooms.size()):
		var candidates := _collect_room_wall_bay_candidates(layout, layout.rooms[room_index], door_cells)
		if candidates.is_empty():
			continue
		var bay_count := mini(3, maxi(1, int(candidates.size() / 4)))
		for bay_index in range(bay_count):
			var candidate_index := mini(candidates.size() - 1,
				int(floor((float(bay_index) + 0.5) * float(candidates.size()) / float(bay_count))))
			var candidate: Dictionary = candidates[candidate_index]
			_add_room_wall_bay(layout, result, room_index, bay_index,
				candidate["cell"], candidate["direction"], stone_material)
		var light_candidate: Dictionary = candidates[int(floor(float(candidates.size()) * 0.5))]
		_add_room_edge_candelabrum(layout, result, room_index,
			light_candidate["cell"], light_candidate["direction"])

func _collect_room_wall_bay_candidates(layout: DungeonLayout, room: Rect2i, door_cells: Dictionary) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var claimed_cells: Dictionary = {}
	for y in range(room.position.y, room.end.y):
		for x in range(room.position.x, room.end.x):
			var cell := Vector2i(x, y)
			if claimed_cells.has(cell) or door_cells.has(cell) or not layout.is_floor_cell(cell):
				continue
			for direction in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
				if not _is_grid_wall(layout.grid, x + direction.x, y + direction.y):
					continue
				candidates.append({"cell": cell, "direction": direction})
				claimed_cells[cell] = true
				break
	return candidates

func _add_room_wall_bay(layout: DungeonLayout, result: DungeonBuildResult, room_index: int,
		bay_index: int, cell: Vector2i, wall_direction: Vector2i, stone_material: Material) -> void:
	var root := Node3D.new()
	root.name = "WallBay_%d_%d" % [room_index, bay_index]
	root.set_meta("topdown_kind", "wall_architecture")
	root.set_meta("wall_architecture", true)
	root.set_meta("wall_cell", cell)
	root.set_meta("wall_direction", wall_direction)
	result.decor_root.add_child(root)
	var floor_position := _cell_to_world(cell, layout)
	var wall_plane := floor_position + Vector3(float(wall_direction.x), 0.0, float(wall_direction.y)) * layout.tile_size * 0.5
	root.position = wall_plane
	var tangent := Vector3(float(-wall_direction.y), 0.0, float(wall_direction.x))
	var inward := -Vector3(float(wall_direction.x), 0.0, float(wall_direction.y))
	var depth_axis_x := wall_direction.x != 0
	var structure_height := minf(3.0, maxf(2.65, _height_at_cell_in_layout(cell, layout)))
	var base_height := 0.28
	var capital_height := 0.30
	var crown_height := 0.34
	var shaft_top := structure_height - capital_height - crown_height
	var shaft_height := shaft_top - base_height
	for side_value in [-1.0, 1.0]:
		var side: float = float(side_value)
		var tangent_offset: Vector3 = tangent * 1.02 * side
		_add_wall_bay_box(root, "Base", inward * 0.23 + tangent_offset + Vector3.UP * (base_height * 0.5),
			_wall_bay_size(0.50, base_height, 0.46, depth_axis_x), stone_material)
		_add_wall_bay_box(root, "Shaft", inward * 0.16 + tangent_offset + Vector3.UP * (base_height + shaft_height * 0.5),
			_wall_bay_size(0.38, shaft_height, 0.32, depth_axis_x), stone_material)
		_add_wall_bay_box(root, "Capital", inward * 0.25 + tangent_offset + Vector3.UP * (shaft_top + capital_height * 0.5),
			_wall_bay_size(0.56, capital_height, 0.50, depth_axis_x), stone_material)
	_add_wall_bay_box(root, "Crown", inward * 0.21 + Vector3.UP * (structure_height - crown_height * 0.5),
		_wall_bay_size(2.60, crown_height, 0.42, depth_axis_x), stone_material)
	_add_wall_bay_grate(root, inward, wall_direction, structure_height)
	result.streamed_visual_nodes.append(root)

func _wall_bay_size(tangent_width: float, height: float, depth: float, depth_axis_x: bool) -> Vector3:
	return Vector3(depth, height, tangent_width) if depth_axis_x else Vector3(tangent_width, height, depth)

func _add_wall_bay_box(root: Node3D, part_name: String, position: Vector3, size: Vector3, material: Material) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "%s_%d" % [part_name, root.get_child_count()]
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.position = position
	mesh_instance.material_override = material
	root.add_child(mesh_instance)

func _add_wall_bay_grate(root: Node3D, inward: Vector3,
		wall_direction: Vector2i, structure_height: float) -> void:
	var grate := IRON_BAR_GRATE_PREFAB.instantiate() as Node3D
	if grate == null:
		return
	grate.name = "RecessGrate"
	grate.scale.x = 0.72
	grate.position = inward * 0.11 + Vector3.UP * maxf(0.28, structure_height - 2.66)
	if wall_direction == Vector2i(0, -1):
		grate.rotation.y = PI
	elif wall_direction == Vector2i(1, 0):
		grate.rotation.y = PI / 2.0
	elif wall_direction == Vector2i(-1, 0):
		grate.rotation.y = -PI / 2.0
	var body := grate.get_node_or_null("SceneObjectBody")
	if body != null:
		grate.remove_child(body)
		body.free()
	root.add_child(grate)

func _add_room_edge_candelabrum(layout: DungeonLayout, result: DungeonBuildResult,
		room_index: int, wall_cell: Vector2i, wall_direction: Vector2i) -> void:
	var candelabrum := FLOOR_CANDELABRUM_PREFAB.instantiate() as Node3D
	if candelabrum == null:
		return
	candelabrum.name = "RoomCandelabrum_%d" % room_index
	candelabrum.set_meta("room_light_anchor", true)
	candelabrum.set_meta("room_index", room_index)
	candelabrum.set_meta("wall_cell", wall_cell)
	var inward := -Vector3(float(wall_direction.x), 0.0, float(wall_direction.y))
	candelabrum.position = _cell_to_world(wall_cell, layout) + inward * 0.42
	VOXEL_LIGHTING.apply_to_tree(candelabrum, true)
	result.decor_root.add_child(candelabrum)
	_configure_scene_object(candelabrum)
	_apply_distance_culling(candelabrum, TORCH_VISIBILITY_RANGE_END)
	result.streamed_physics_nodes.append(candelabrum)

func _build_ramp(layout: DungeonLayout, result: DungeonBuildResult, room_index: int, ramp_spec: Dictionary, elevation: float) -> void:
	var cell: Vector2i = ramp_spec.get("cell", Vector2i(-1, -1))
	var direction: Vector2i = ramp_spec.get("dir", Vector2i(0, 1))
	if cell.x < 0:
		return
	var root := MeshInstance3D.new()
	root.name = "Ramp_%d_%s" % [room_index, str(cell)]
	root.set_meta("topdown_kind", "ramp")
	root.set_meta("ramp_cell", cell)
	root.set_meta("ramp_direction", direction)
	root.mesh = _make_ramp_mesh(layout.tile_size, elevation)
	root.position = _cell_to_world(cell, layout)
	root.rotation.y = atan2(float(direction.x), float(direction.y))
	root.material_override = _composition_material("bridge", layout.tile_size)
	result.decor_root.add_child(root)
	result.streamed_visual_nodes.append(root)
	var body := StaticBody3D.new()
	body.name = root.name + "Collision"
	body.collision_layer = PhysicsSetup.LAYER_ENVIRONMENT
	body.collision_mask = PhysicsSetup.MASK_ENVIRONMENT
	body.position = root.position
	body.rotation.y = root.rotation.y
	var collision := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(_ramp_faces(layout.tile_size, elevation))
	collision.shape = shape
	body.add_child(collision)
	result.collision_root.add_child(body)
	result.streamed_physics_nodes.append(body)

func _make_ramp_mesh(tile_size: float, elevation: float) -> ArrayMesh:
	var vertices := _ramp_vertices(tile_size, elevation)
	var indices := _ramp_indices()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in indices:
		surface.add_vertex(vertices[index])
	surface.generate_normals()
	return surface.commit()

func _ramp_vertices(tile_size: float, elevation: float) -> PackedVector3Array:
	var half := tile_size * 0.5
	return PackedVector3Array([
		Vector3(-half, 0.0, -half), Vector3(half, 0.0, -half),
		Vector3(half, 0.0, half), Vector3(-half, 0.0, half),
		Vector3(-half, elevation, half), Vector3(half, elevation, half),
	])

func _ramp_indices() -> PackedInt32Array:
	return PackedInt32Array([
		0, 2, 3, 0, 1, 2,
		1, 5, 2,
		3, 2, 5, 3, 5, 4,
		0, 3, 4,
		0, 4, 5, 0, 5, 1,
	])

func _ramp_faces(tile_size: float, elevation: float) -> PackedVector3Array:
	var vertices := _ramp_vertices(tile_size, elevation)
	var indices := _ramp_indices()
	var faces := PackedVector3Array()
	for index in indices:
		faces.append(vertices[index])
	return faces

func _build_hazard_warning(layout: DungeonLayout, result: DungeonBuildResult, cell: Vector2i, hazard_type: String) -> void:
	if result == null or result.decor_root == null or not layout.is_floor_cell(cell):
		return
	var root := Node3D.new()
	root.name = "HazardWarning_%s_%s" % [hazard_type, str(cell)]
	root.position = _cell_to_world(cell, layout)
	root.set_meta("topdown_kind", "hazard_warning")
	root.set_meta("hazard_warning_for", hazard_type)
	var warning_material := _focus_material(Color(1.0, 0.38, 0.16), true, "BARONY_THRESHOLD")
	var plate := MeshInstance3D.new()
	plate.name = "WarningPlate"
	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(layout.tile_size * 0.78, 0.035, layout.tile_size * 0.78)
	plate.mesh = plate_mesh
	plate.position.y = 0.04
	plate.material_override = warning_material
	root.add_child(plate)
	for index in range(2):
		var crack := MeshInstance3D.new()
		crack.name = "WarningCrack%d" % index
		var crack_mesh := BoxMesh.new()
		crack_mesh.size = Vector3(layout.tile_size * 0.62, 0.045, 0.07)
		crack.mesh = crack_mesh
		crack.position = Vector3(0.0, 0.07, -0.45 + index * 0.9)
		crack.rotation.y = 0.32 if index == 0 else -0.32
		crack.material_override = _focus_material(Color(0.52, 0.12, 0.06), true, "BARONY_BROKEN_WALL")
		root.add_child(crack)
	var light := OmniLight3D.new()
	light.name = "WarningLight"
	light.light_color = Color(1.0, 0.18, 0.06)
	light.light_energy = 0.12
	light.omni_range = 2.2
	light.shadow_enabled = false
	light.position.y = 0.32
	root.add_child(light)
	var tween := light.create_tween().set_loops()
	tween.tween_property(light, "light_energy", 0.55, 0.45)
	tween.tween_property(light, "light_energy", 0.12, 0.75)
	result.decor_root.add_child(root)
	result.streamed_visual_nodes.append(root)

# ── extraction portal prefab 映射 ───────────────────────────────
## 撤离传送门 instantiate。信号接线（extraction_requested.connect）属 runtime 阶段 9 聃畴，
## builder 只 instantiate 节点 + set_meta，不接信号。
func _build_extraction_portal(layout: DungeonLayout, result: DungeonBuildResult) -> void:
	if layout.is_key_cell_missing(layout.extraction_cell):
		return  # extraction 是 0.2 概率 role，未命中不放
	var instance := EXTRACTION_PORTAL_PREFAB.instantiate() as Node3D
	if instance == null:
		return
	instance.position = _cell_to_world(layout.extraction_cell, layout)
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

## 格坐标 → 以地牢中心为原点的世界坐标。
## 地形、敌人和玩家都使用同一 OFFSET；prefab 不能落在未居中的格坐标系中。
func _cell_to_world(cell: Vector2i, layout: DungeonLayout, category: String = "", variant_index: int = 0) -> Vector3:
	return layout.cell_to_world(cell, 0.0, category, variant_index)

func _configure_hazard_placement(instance: Node3D, hazard_type: String, anchor: Dictionary) -> void:
	match hazard_type:
		"spikes":
			# 体素尖刺模型已为纵向（Y 轴朝上）；地牢锚点采用地面式陷阱，避免把碰撞体悬在墙角。
			instance.set_meta("spike_mount", "floor")
			instance.position.y = 0.0
			var direction: Vector2i = anchor.get("direction", Vector2i(0, 1))
			if direction != Vector2i.ZERO:
				instance.rotation.y = atan2(float(direction.x), float(direction.y))
		"acid":
			instance.set_meta("acid_ground_only", true)
			instance.set_meta("acid_pit", true)
			instance.rotation = Vector3.ZERO
			instance.position.y = 0.0

func _is_walkable_navigation_cell(cell_type: int) -> bool:
	# 与 WFC/BSP 的可达性定义保持一致；PILLAR 仍保留地板，后续由其实际碰撞体阻挡。
	return cell_type in [1, 3, 4, 5]


# ── navigation mesh（迁自 procedural._build_navigation_mesh） ──
func _build_navigation_mesh(layout: DungeonLayout, result: DungeonBuildResult, parent: Node3D) -> void:
	if result == null or result.floor_transforms.is_empty() or parent == null:
		return
	# headless/gdUnit 下 bake 偶发 native crash；生产有窗口时再烘焙
	if DisplayServer.get_name() == "headless":
		return
	# 与默认 NavigationMap cell 对齐，避免 cell_height mismatch。
	# 限制输入规模，避免超大地牢在烘焙时造成单帧尖峰。
	var region := NavigationRegion3D.new()
	region.name = "DungeonNavigationRegion"
	var nav_mesh := NavigationMesh.new()
	# 导航网格按最大敌人包络烘焙；运行时小型敌人仍由 NavigationAgent3D 的实际半径避障。
	nav_mesh.agent_radius = PhysicsSetup.get_character_capsule_radius("huge") + PhysicsSetup.CHARACTER_COLLISION_MARGIN
	nav_mesh.agent_height = PhysicsSetup.get_character_capsule_height("huge")
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.25
	region.navigation_mesh = nav_mesh
	parent.add_child(region)
	var source_geometry_data := NavigationMeshSourceGeometryData3D.new()
	var floor_size := Vector3(layout.tile_size, 0.1, layout.tile_size)
	var floor_faces := PackedVector3Array()
	var navigation_excluded_cells := _collect_navigation_excluded_cells(layout)
	var raised_cells := _collect_raised_cells(layout)
	var max_floor_samples := 2048
	var floor_count := mini(result.floor_transforms.size(), max_floor_samples)
	for i in range(floor_count):
		var t: Transform3D = result.floor_transforms[i]
		var floor_cell := _world_to_cell(t.origin, layout)
		if raised_cells.has(floor_cell) or navigation_excluded_cells.has(floor_cell):
			continue
		_append_floor_top_face(floor_faces, t.origin, floor_size)
	for raised in raised_cells.keys():
		var raised_cell: Vector2i = raised
		if navigation_excluded_cells.has(raised_cell):
			continue
		var raised_pos := _cell_to_world(raised_cell, layout)
		_append_floor_top_face(floor_faces, raised_pos, floor_size)
	for composition in layout.room_composition_specs:
		for ramp_spec in composition.get("ramp_specs", []):
			var ramp_cell: Vector2i = ramp_spec.get("cell", Vector2i(-1, -1))
			if ramp_cell.x < 0 or navigation_excluded_cells.has(ramp_cell):
				continue
			_append_ramp_top_face(floor_faces, _cell_to_world(ramp_cell, layout), layout.tile_size,
				float(composition.get("elevation_m", 1.0)), ramp_spec.get("dir", Vector2i(0, 1)))
	if floor_faces.is_empty():
		return
	source_geometry_data.add_faces(floor_faces, Transform3D.IDENTITY)
	_build_elevation_navigation_links(layout, parent)
	var wall_faces := _build_navigation_obstacle_faces(layout, result)
	if not wall_faces.is_empty():
		source_geometry_data.add_faces(wall_faces, Transform3D.IDENTITY)
	# 地板定义可行走区域，墙体盒面定义不可穿越的垂直障碍。
	# P-A：导航烘焙改异步可消除进场最长单帧 stall（ENABLE_ASYNC_NAVMESH_BAKE）。
	# 异步在后台线程填充 nav_mesh；完成前 NavigationAgent3D 查询返回空路径、自然等待，不影响寻路正确性。
	# 默认关闭（见 ENABLE_ASYNC_NAVMESH_BAKE 注释），开启前需窗口化冒烟测试确认敌人可寻路。
	# 异步方法名含 "bake_from_source_geometry_data" 前缀，perf 测试仍通过；缺失时回退同步分支。
	if ENABLE_ASYNC_NAVMESH_BAKE and NavigationServer3D.has_method("bake_from_source_geometry_data_async"):
		NavigationServer3D.bake_from_source_geometry_data_async(nav_mesh, source_geometry_data, Callable())
	else:
		NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source_geometry_data, Callable())

func _build_navigation_obstacle_faces(layout: DungeonLayout, result: DungeonBuildResult, max_samples: int = 4096) -> PackedVector3Array:
	var faces := PackedVector3Array()
	if layout == null or result == null:
		return faces
	var sample_count := 0
	for wall_key in result.wall_transforms_by_height:
		if sample_count >= max_samples:
			break
		var group: Dictionary = result.wall_transforms_by_height[wall_key]
		var size: Vector3 = group.get("size", Vector3(3.0, 3.0, 3.0))
		for transform_value in group.get("transforms", []):
			if sample_count >= max_samples:
				break
			var transform := transform_value as Transform3D
			_append_box_faces(faces, transform.origin, size)
			sample_count += 1
	# 柱体格保留地板以维持房间连通性，但柱体自身必须作为局部障碍进入导航源，
	# 否则路径会穿过柱心，再由 CharacterBody3D 被挤到墙角/柱边。
	var grid: Array = layout.grid
	var offset := Vector3(
		-(float(layout.width) * layout.tile_size) / 2.0,
		0.0,
		-(float(layout.height) * layout.tile_size) / 2.0,
	)
	for y in range(grid.size()):
		for x in range(grid[y].size()):
			if sample_count >= max_samples:
				return faces
			if int(grid[y][x]) != 5:
				continue
			var pillar_height := _height_at_cell_in_layout(Vector2i(x, y), layout)
			var pillar_center := offset + Vector3(x * layout.tile_size, pillar_height * 0.5, y * layout.tile_size)
			_append_box_faces(faces, pillar_center, Vector3(0.75, pillar_height, 0.75))
			sample_count += 1
	# Hazard prefabs also contain runtime obstacles, but those are not guaranteed to
	# affect the baked map. Add a static footprint so hunt paths avoid damage areas
	# even when avoidance/RVO is disabled at full dark erosion.
	for anchor in layout.hazard_anchors:
		if sample_count >= max_samples:
			return faces
		var cell: Vector2i = anchor.get("anchor_cell", Vector2i(-1, -1))
		if not layout.is_floor_cell(cell):
			continue
		var hazard_height := 2.0
		var hazard_center := offset + Vector3(
			cell.x * layout.tile_size,
			hazard_height * 0.5,
			cell.y * layout.tile_size
		)
		# Match the actual trap footprint. Blocking a full 3m cell plus 2m of
		# clearance turns an edge hazard into a 5m wall and can disconnect a room.
		var footprint := _hazard_navigation_footprint(String(anchor.get("hazard_type", "")), layout.tile_size)
		_append_box_faces(faces, hazard_center, Vector3(footprint, hazard_height, footprint))
		sample_count += 1
	# 关闭门是导航上的真实阻挡；打开/破坏后，DungeonDoor 启用两侧的 NavigationLink3D。
	if result.doors_root != null:
		for child in result.doors_root.get_children():
			if sample_count >= max_samples:
				return faces
			var door := child as DungeonDoor
			if door == null or door.is_open or door.is_broken:
				continue
			var collision := door.get_node_or_null("CollisionShape3D") as CollisionShape3D
			var box := collision.shape as BoxShape3D if collision != null else null
			if box == null:
				continue
			var center := door.global_transform * collision.position
			_append_box_faces(faces, center, box.size)
			sample_count += 1
	# Door surrounds are separate StaticBody3D nodes under collision_root. They are
	# not represented by wall_transforms, so omitting them lets paths pass through
	# the jamb/lintel while CharacterBody3D is still blocked by physics.
	sample_count = _append_navigation_box_obstacles_from_root(
		faces, result.collision_root, "door_surround", true, sample_count, max_samples)
	# Chests build their visual collision in _ready() (including the ChestVisual
	# VoxelProp child). Include every BoxShape in the chest subtree so the baked
	# map matches the runtime collision that can stop a pursuing enemy.
	sample_count = _append_navigation_box_obstacles_from_root(
		faces, result.interaction_root, "topdown_kind", "chest", sample_count, max_samples)
	# Decor prefabs may create their StaticBody3D at runtime or through the
	# batched-decor path without a semantic meta tag. Any such collider still
	# participates in CharacterBody3D physics and must be represented in navmesh.
	sample_count = _append_navigation_box_obstacles_from_root(
		faces, result.decor_root, "", null, sample_count, max_samples)
	sample_count = _append_navigation_composition_obstacles(
		faces, result.collision_root, sample_count, max_samples)
	return faces

func _append_navigation_composition_obstacles(faces: PackedVector3Array, root: Node,
		sample_count: int, max_samples: int) -> int:
	if root == null or not is_instance_valid(root):
		return sample_count
	for body_node in root.find_children("*", "StaticBody3D", true, false):
		var kind := String(body_node.get_meta("composition_kind", ""))
		if kind not in ["cover", "boundary"]:
			continue
		for collision_node in body_node.find_children("*", "CollisionShape3D", true, false):
			if sample_count >= max_samples:
				return sample_count
			var collision := collision_node as CollisionShape3D
			var box := collision.shape as BoxShape3D if collision != null else null
			if box == null:
				continue
			_append_box_faces_from_transform(faces, collision.global_transform, box.size)
			sample_count += 1
	return sample_count

func _collect_raised_cells(layout: DungeonLayout) -> Dictionary:
	var result := {}
	for composition in layout.room_composition_specs:
		# 悬崖平台是视觉/物理地形，但不是敌人的可行走目标；其顶面由
		# _collect_navigation_excluded_cells() 统一剔除，避免高台寻路自杀。
		if String(composition.get("composition_kind", "")) == "cliff":
			continue
		for cell in composition.get("platform_cells", []):
			result[cell] = true
		for cell in composition.get("bridge_cells", []):
			result[cell] = true
	return result

## 返回不能作为敌人导航目标的危险地形格。
## 陷阱必须从地板源移除；悬崖顶面和斜坡也必须移除，避免怪物主动走入
## 会造成坠落/伤害的地形。保留物理/视觉几何和陷阱 footprint 障碍用于碰撞。
func _collect_navigation_excluded_cells(layout: DungeonLayout) -> Dictionary:
	var result := {}
	if layout == null:
		return result
	for anchor in layout.hazard_anchors:
		var hazard_cell: Vector2i = anchor.get("anchor_cell", Vector2i(-1, -1))
		if layout.is_floor_cell(hazard_cell):
			result[hazard_cell] = true
	for composition in layout.room_composition_specs:
		if String(composition.get("composition_kind", "")) != "cliff":
			continue
		for cell_value in composition.get("cliff_cells", composition.get("platform_cells", [])):
			var cliff_cell: Vector2i = cell_value
			if layout.is_floor_cell(cliff_cell):
				result[cliff_cell] = true
		for ramp_spec in composition.get("ramp_specs", []):
			var ramp_cell: Vector2i = ramp_spec.get("cell", Vector2i(-1, -1))
			if layout.is_floor_cell(ramp_cell):
				result[ramp_cell] = true
	return result

func _world_to_cell(world_pos: Vector3, layout: DungeonLayout) -> Vector2i:
	var offset_x := -(float(layout.width) * layout.tile_size) / 2.0
	var offset_z := -(float(layout.height) * layout.tile_size) / 2.0
	return Vector2i(
		roundi((world_pos.x - offset_x) / layout.tile_size),
		roundi((world_pos.z - offset_z) / layout.tile_size))

func _append_ramp_top_face(faces: PackedVector3Array, center: Vector3, tile_size: float,
		elevation: float, direction: Vector2i) -> void:
	var half := tile_size * 0.5
	var yaw := atan2(float(direction.x), float(direction.y))
	var basis := Basis(Vector3.UP, yaw)
	var p0 := center + basis * Vector3(-half, 0.0, -half)
	var p1 := center + basis * Vector3(half, 0.0, -half)
	var p2 := center + basis * Vector3(half, elevation, half)
	var p3 := center + basis * Vector3(-half, elevation, half)
	faces.append_array([p0, p1, p2, p0, p2, p3])

func _build_elevation_navigation_links(layout: DungeonLayout, parent: Node3D) -> void:
	for composition_index in range(layout.room_composition_specs.size()):
		var composition: Dictionary = layout.room_composition_specs[composition_index]
		if String(composition.get("composition_kind", "")) == "cliff":
			continue
		for ramp_index in range(composition.get("ramp_specs", []).size()):
			var ramp_spec: Dictionary = composition["ramp_specs"][ramp_index]
			var cell: Vector2i = ramp_spec.get("cell", Vector2i(-1, -1))
			var direction: Vector2i = ramp_spec.get("dir", Vector2i(0, 1))
			if cell.x < 0:
				continue
			var link := NavigationLink3D.new()
			link.name = "ElevationLink_%d_%d" % [composition_index, ramp_index]
			link.bidirectional = true
			link.enabled = true
			var center := _cell_to_world(cell, layout)
			link.start_position = center - Vector3(float(direction.x), 0.0, float(direction.y)) * layout.tile_size * 0.42
			link.end_position = center + Vector3(float(direction.x), float(composition.get("elevation_m", 1.0)), float(direction.y)) * layout.tile_size * 0.42
			parent.add_child(link)

func _hazard_navigation_footprint(hazard_type: String, tile_size: float) -> float:
	var configured := float(HAZARD_NAV_FOOTPRINT_M.get(hazard_type, 1.5))
	# Keep an unknown/future hazard inside its cell so it cannot seal adjacent cells.
	return clampf(configured, 1.0, maxf(tile_size - 0.25, 1.0))

func _append_navigation_box_obstacles_from_root(faces: PackedVector3Array, root: Node,
		meta_name: String, meta_value: Variant, sample_count: int, max_samples: int) -> int:
	if root == null or not is_instance_valid(root):
		return sample_count
	for body_node in root.find_children("*", "StaticBody3D", true, false):
		if not meta_name.is_empty() \
				and (not body_node.has_meta(meta_name) or body_node.get_meta(meta_name) != meta_value):
			continue
		for collision_node in body_node.find_children("*", "CollisionShape3D", true, false):
			if sample_count >= max_samples:
				return sample_count
			var collision := collision_node as CollisionShape3D
			var box := collision.shape as BoxShape3D if collision != null else null
			if box == null:
				continue
			_append_box_faces_from_transform(faces, collision.global_transform, box.size)
			sample_count += 1
	return sample_count

func _append_box_faces_from_transform(faces: PackedVector3Array, transform: Transform3D, size: Vector3) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var p000 := transform * Vector3(-hx, -hy, -hz)
	var p100 := transform * Vector3( hx, -hy, -hz)
	var p110 := transform * Vector3( hx,  hy, -hz)
	var p010 := transform * Vector3(-hx,  hy, -hz)
	var p001 := transform * Vector3(-hx, -hy,  hz)
	var p101 := transform * Vector3( hx, -hy,  hz)
	var p111 := transform * Vector3( hx,  hy,  hz)
	var p011 := transform * Vector3(-hx,  hy,  hz)
	faces.append_array([
		p000, p100, p110, p000, p110, p010,
		p001, p011, p111, p001, p111, p101,
		p000, p001, p101, p000, p101, p100,
		p010, p110, p111, p010, p111, p011,
		p000, p010, p011, p000, p011, p001,
		p100, p101, p111, p100, p111, p110,
	])

func _append_floor_top_face(faces: PackedVector3Array, center: Vector3, size: Vector3) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var p010 := center + Vector3(-hx, hy, -hz)
	var p110 := center + Vector3( hx, hy, -hz)
	var p111 := center + Vector3( hx, hy,  hz)
	var p011 := center + Vector3(-hx, hy,  hz)
	faces.append_array([p010, p110, p111, p010, p111, p011])

func _build_planned_decor(layout: DungeonLayout, result: DungeonBuildResult, parent: Node3D) -> void:
	if layout == null or result == null or parent == null:
		return
	var runtime_cfg := DungeonRuntimeConfig.default()
	for index in range(layout.decor_specs.size()):
		var spec: Dictionary = layout.decor_specs[index]
		var kind := String(spec.get("decor_kind", ""))
		var expected_path := runtime_cfg.dungeon_decor_scene_path_for(kind)
		var scene_path := String(spec.get("scene_path", ""))
		if expected_path.is_empty() or scene_path != expected_path \
				or not runtime_cfg.is_dungeon_scene_path_allowed(scene_path):
			continue
		var cell: Vector2i = spec.get("cell", Vector2i(-1, -1))
		if not layout.is_floor_cell(cell):
			continue
		var scene := load(scene_path)
		if not scene is PackedScene:
			continue
		var instance := (scene as PackedScene).instantiate()
		if not instance is Node3D:
			if instance != null: instance.queue_free()
			continue
		var node := instance as Node3D
		node.name = "PlannedDecor_%03d_%s" % [index, kind]
		var placement := String(spec.get("placement", runtime_cfg.dungeon_decor_placement_for(kind)))
		var wall_direction: Vector2i = spec.get("wall_direction", Vector2i.ZERO)
		node.position = _planned_decor_world_position(cell, layout, placement, wall_direction, index)
		if not _reserve_spawn_footprint(result, node.position,
				DungeonSpawnFootprint.half_extents_for_scene_path(scene_path), "planned:%s" % kind):
			instance.queue_free()
			continue
		node.rotation.y = _planned_decor_rotation(spec, placement, wall_direction)
		node.set_meta("decor_kind", kind)
		node.set_meta("planned_decor", true)
		node.set_meta("decor_cell", cell)
		node.set_meta("decor_placement", placement)
		node.set_meta("wall_direction", wall_direction)
		VOXEL_LIGHTING.apply_to_tree(node, true)
		result.decor_root.add_child(node)
		_apply_distance_culling(node)
		_ensure_collision_on_instance(node)
		_configure_scene_object(node)
		result.streamed_visual_nodes.append(node)
		if bool(spec.get("blocks_navigation", false)):
			result.streamed_physics_nodes.append(node)


func _planned_decor_world_position(cell: Vector2i, layout: DungeonLayout, placement: String,
		wall_direction: Vector2i, variant_index: int) -> Vector3:
	var position := _cell_to_world(cell, layout, "decor", variant_index)
	if wall_direction == Vector2i.ZERO:
		return position
	var direction := Vector3(float(wall_direction.x), 0.0, float(wall_direction.y))
	match placement:
		"wall":
			# 墙面装饰根节点压到墙内侧，局部 +Z 面朝墙，避免落在房间几何中心。
			position += direction * maxf(layout.tile_size * 0.5 - 0.16, 0.0)
		"edge":
			# 石块/菌簇靠墙但保留可见轮廓和碰撞间隙。
			position += direction * minf(layout.tile_size * 0.22, 0.48)
	return position


func _planned_decor_rotation(spec: Dictionary, placement: String, wall_direction: Vector2i) -> float:
	if placement == "wall" and wall_direction != Vector2i.ZERO:
		match wall_direction:
			Vector2i(0, -1): return PI
			Vector2i(1, 0): return PI * 0.5
			Vector2i(-1, 0): return -PI * 0.5
			_: return 0.0
	return float(int(spec.get("rotation_quarters", 0)) % 4) * PI * 0.5

# ── decor scatter + torch + pillar（迁自 procedural._build_terrain_geometry 装饰段） ──
func _build_decor_and_torches(layout: DungeonLayout, result: DungeonBuildResult, parent: Node3D) -> void:
	if layout.is_empty() or result == null or parent == null:
		return
	var runtime_cfg := DungeonRuntimeConfig.default()
	var grid: Array = layout.grid
	var grid_width: int = grid[0].size() if grid.size() > 0 else 0
	var grid_height: int = grid.size()
	var tile_size: float = layout.tile_size
	var preferred_spawn_cell := layout.player_spawn_cell
	var has_preferred_spawn := preferred_spawn_cell.x >= 0 and preferred_spawn_cell.y >= 0
	if not has_preferred_spawn and layout.room_roles.has("start"):
		preferred_spawn_cell = _rect_center_cell(layout.room_roles["start"])
		has_preferred_spawn = true
	var player_spawned := false
	var torch_zones: Array = TORCH_ZONES
	var torch_cells: Dictionary = {}
	_spawn_room_torch_anchors(layout, result, parent, torch_cells)
	var zone := layout.zone
	for y in range(grid.size()):
		for x in range(grid[y].size()):
			var cell_type: int = int(grid[y][x])
			var cell := Vector2i(x, y)
			# 与房间锚点共用唯一格坐标转换；手工构造 Y=0 会让随机火把在抬升房间中沉入墙体。
			var cell_pos := _cell_to_world(Vector2i(x, y), layout)
			match cell_type:
				5:
					var room_h: float = _height_at_cell_in_layout(cell, layout)
					var pillar_t := Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, room_h / 3.0, 1.0)), cell_pos)
					if not _spawn_batched_decor(result, parent, runtime_cfg, PILLAR_PREFAB.resource_path, pillar_t):
						if not _reserve_spawn_footprint(result, cell_pos,
								DungeonSpawnFootprint.half_extents_for("decor", "pillar"), "pillar"):
							continue
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
					if not _is_population_reserved_cell(layout, cell) and not torch_cells.has(cell):
						_spawn_random_decor(result, parent, runtime_cfg, cell_pos)
				_:
					pass
			if cell_type != 2 and cell_type != 0:
				if not player_spawned and cell_type == 1 and (not has_preferred_spawn or Vector2i(x, y) == preferred_spawn_cell):
					player_spawned = true
				elif player_spawned and not _is_start_room_cell(layout, cell) \
						and not _is_population_reserved_cell(layout, cell) and not torch_cells.has(cell):
					if zone in torch_zones:
						var directions := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0)]
						var torch_spawned := false
						for dir in directions:
							var nx = x + dir.x
							var ny = y + dir.y
							if nx >= 0 and nx < grid_width and ny >= 0 and ny < grid_height:
								if int(grid[ny][nx]) == 2:
									if not torch_cells.has(Vector2i(x, y)) and randf() < TORCH_RANDOM_SPAWN_PROBABILITY:
										var h: float = float(result.wall_h_map.get(Vector2i(nx, ny), HEIGHT_CONFIG.MIN_CEILING_HEIGHT_METERS))
										_spawn_torch_on_wall(result, parent, cell_pos, dir, h, tile_size)
										torch_cells[Vector2i(x, y)] = true
										torch_spawned = true
										break
						if not torch_spawned and not torch_cells.has(cell) and randf() < 0.035:
							var scatter = Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))
							_spawn_random_decor(result, parent, runtime_cfg, cell_pos + scatter)
					elif randf() < 0.055:
						var scatter2 = Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))
						_spawn_random_decor(result, parent, runtime_cfg, cell_pos + scatter2)

func _spawn_room_torch_anchors(layout: DungeonLayout, result: DungeonBuildResult, parent: Node3D, torch_cells: Dictionary) -> void:
	if layout == null or result == null or parent == null or layout.rooms.is_empty() or not TORCH_ZONES.has(layout.zone):
		return
	_seed_existing_room_light_anchor_cells(layout, result, torch_cells)
	for room in layout.rooms:
		if layout.room_roles.has("start") and room == layout.room_roles["start"]:
			continue
		for _anchor_index in range(TORCH_ROOM_ANCHOR_COUNT):
			var center := Vector2i(room.position.x + room.size.x / 2, room.position.y + room.size.y / 2)
			var best_cell := Vector2i(-1, -1)
			var best_direction := Vector2i.ZERO
			var best_distance := INF
			for y in range(room.position.y, room.position.y + room.size.y):
				for x in range(room.position.x, room.position.x + room.size.x):
					var cell := Vector2i(x, y)
					if torch_cells.has(cell) or _is_population_reserved_cell(layout, cell) \
							or _is_pillar_cell(layout, cell) or not layout.is_floor_cell(cell):
						continue
					for direction in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0)]:
						if not _is_grid_wall(layout.grid, x + direction.x, y + direction.y):
							continue
						var distance := float(abs(x - center.x) + abs(y - center.y))
						if distance < best_distance:
							best_distance = distance
							best_cell = cell
							best_direction = direction
			if best_cell.x < 0:
				break
			var wall_cell := best_cell + best_direction
			var wall_height: float = float(result.wall_h_map.get(wall_cell, HEIGHT_CONFIG.MIN_CEILING_HEIGHT_METERS))
			var cell_pos := _cell_to_world(best_cell, layout)
			_spawn_torch_on_wall(result, parent, cell_pos, best_direction, wall_height, layout.tile_size)
			torch_cells[best_cell] = true

func _seed_existing_room_light_anchor_cells(layout: DungeonLayout, result: DungeonBuildResult, torch_cells: Dictionary) -> void:
	if layout == null or result == null or result.decor_root == null or torch_cells == null:
		return
	for node in result.decor_root.find_children("*", "Node3D", true, false):
		if not node.has_meta("room_light_anchor") or not bool(node.get_meta("room_light_anchor")):
			continue
		var anchor_cell: Variant = node.get_meta("wall_cell", Vector2i(-1, -1))
		if anchor_cell is Vector2i and layout.is_floor_cell(anchor_cell):
			torch_cells[anchor_cell] = true

func _is_start_room_cell(layout: DungeonLayout, cell: Vector2i) -> bool:
	return layout.room_roles.has("start") and (layout.room_roles["start"] as Rect2i).has_point(cell)

func _is_population_reserved_cell(layout: DungeonLayout, cell: Vector2i) -> bool:
	for specs in [layout.enemy_spawn_specs, layout.item_spawn_specs, layout.chest_spawn_specs, layout.decor_specs]:
		for spec in specs:
			if spec.get("cell", Vector2i(-1, -1)) == cell:
				return true
	for anchor in layout.hazard_anchors:
		if anchor.get("anchor_cell", Vector2i(-1, -1)) == cell:
			return true
	for focus in layout.room_focus_specs:
		if focus.get("cell", Vector2i(-1, -1)) == cell:
			return true
	for composition in layout.room_composition_specs:
		for key in ["focus_cell", "cover_cells", "platform_cells", "cliff_cells", "bridge_cells", "door_transition_cells"]:
			var value: Variant = composition.get(key, Vector2i(-1, -1))
			if value is Array:
				if value.has(cell):
					return true
			elif value == cell:
				return true
		for ramp_spec in composition.get("ramp_specs", []):
			if ramp_spec.get("cell", Vector2i(-1, -1)) == cell:
				return true
	return false

func _is_pillar_cell(layout: DungeonLayout, cell: Vector2i) -> bool:
	return cell.y >= 0 and cell.y < layout.grid.size() \
			and cell.x >= 0 and cell.x < layout.grid[cell.y].size() \
			and int(layout.grid[cell.y][cell.x]) == 5

func _spawn_torch_on_wall(result: DungeonBuildResult, parent: Node3D, cell_pos: Vector3, wall_dir: Vector2i, wall_height: float, tile_size: float) -> void:
	var torch := TORCH_PREFAB.instantiate()
	var pos_offset := Vector3(wall_dir.x, 0, wall_dir.y) * (tile_size / 2.0)
	var clip_offset := -Vector3(wall_dir.x, 0, wall_dir.y) * 0.1
	# wall_height 是墙顶的绝对世界高度；安装高度必须以当前可走地面为基准。
	# 同时按火把自身局部顶点保留顶部余量，避免抬升房间修正后反向穿入天花板。
	var wall_clearance := maxf(wall_height - cell_pos.y, 0.0)
	var max_root_height := maxf(wall_clearance - TORCH_VISUAL_TOP_LOCAL_Y - TORCH_CEILING_CLEARANCE, 0.0)
	var min_root_height := minf(TORCH_MIN_ROOT_HEIGHT_ABOVE_FLOOR, max_root_height)
	var root_height := clampf(wall_clearance * 0.45, min_root_height, max_root_height)
	torch.position = cell_pos + pos_offset + clip_offset + Vector3(0, root_height, 0)
	if not _reserve_spawn_footprint(result, torch.position,
			DungeonSpawnFootprint.half_extents_for("torch", "torch"), "torch"):
		torch.queue_free()
		return
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
	if path == "" or not runtime_cfg.is_dungeon_scene_path_allowed(path):
		return
	# 墙挂物和重型锚点必须由 layout 提供墙向/安全格；随机散布只负责轻型地面边缘装饰。
	var placement := runtime_cfg.dungeon_decor_placement_for_path(path)
	if placement == "wall" or placement == "anchor":
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
	var decor_node := instance as Node3D
	if not _reserve_spawn_footprint(result, decor_node.position,
			DungeonSpawnFootprint.half_extents_for_scene_path(path), "random:%s" % path):
		instance.queue_free()
		return
	VOXEL_LIGHTING.apply_to_tree(decor_node, true)
	if result.decor_root != null:
		result.decor_root.add_child(instance)
	else:
		parent.add_child(instance)
	_apply_distance_culling(decor_node)
	_ensure_collision_on_instance(instance)
	_configure_scene_object(instance)
	result.streamed_physics_nodes.append(instance)

func _spawn_batched_decor(result: DungeonBuildResult, parent: Node3D, runtime_cfg: DungeonRuntimeConfig, path: String, transform: Transform3D) -> bool:
	if not runtime_cfg.is_dungeon_scene_path_allowed(path) or not runtime_cfg.batched_decor_scenes.has(path):
		return false
	var prefab := load(path)
	if not prefab is PackedScene:
		return false
	var cached_data := _get_batched_decor_cache(path, prefab as PackedScene)
	var local_bounds: AABB = cached_data["bounds"]
	if local_bounds.size == Vector3.ZERO:
		return false
	var world_bounds := transform * local_bounds
	var footprint_center := world_bounds.position + world_bounds.size * 0.5
	var footprint_half_extents := Vector2(world_bounds.size.x * 0.5, world_bounds.size.z * 0.5)
	if not _can_reserve_spawn_footprint(result, footprint_center, footprint_half_extents):
		# A valid prefab blocked by an existing object is considered consumed;
		# callers must not fall back to another instance at the same location.
		return true
	DungeonSpawnFootprint.register(result.spawn_footprints, footprint_center, footprint_half_extents,
			"batch:%s" % path)
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
			# material_override 优先；若为 null，回退到 surface_override_material(0)，
			# 再回退到 mesh.surface_get_material(0)。
			# apply_to_tree 把适配后的 ShaderMaterial（含同步过的 pixel_lighting_enabled）
			# 写入 surface_override_material，不回退会丢失同步过的材质，导致
			# MultiMeshInstance3D 使用原始 mesh surface material（pixel_lighting_enabled=1.0），
			# 像素着色开关关闭时仍然显示 toon 光照。
			var material: Material = mesh_instance.material_override
			if material == null and mesh_instance.mesh.get_surface_count() > 0:
				material = mesh_instance.get_surface_override_material(0)
				if material == null:
					material = mesh_instance.mesh.surface_get_material(0)
			out.append({
				"name": String(mesh_instance.name),
				"mesh": mesh_instance.mesh,
				"material": material,
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
	VOXEL_LIGHTING.apply_to_tree(template_root, true)
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

func _can_reserve_spawn_footprint(result: DungeonBuildResult, center: Vector3,
		half_extents: Vector2) -> bool:
	if result == null:
		return false
	return DungeonSpawnFootprint.can_place(result.spawn_footprints, center, half_extents)

func _reserve_spawn_footprint(result: DungeonBuildResult, center: Vector3,
		half_extents: Vector2, owner: String) -> bool:
	if not _can_reserve_spawn_footprint(result, center, half_extents):
		return false
	DungeonSpawnFootprint.register(result.spawn_footprints, center, half_extents, owner)
	return true

func _configure_scene_object(node: Node) -> void:
	if node is StaticBody3D:
		(node as StaticBody3D).collision_layer = SCENE_OBJECT_LAYER
		(node as StaticBody3D).collision_mask = 0
		if (node as StaticBody3D).get_script() == null:
			(node as StaticBody3D).set_script(SCENE_OBJECT_SCRIPT)
	for c in node.get_children():
		_configure_scene_object(c)
