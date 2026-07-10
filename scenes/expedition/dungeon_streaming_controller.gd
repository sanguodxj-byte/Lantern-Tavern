## DungeonStreamingController — 视觉/物理/灯光/terrain chunk 流式激活（阶段 8）。
#
# 职责：按玩家 chunk 位置增量激活/停用节点，管理视觉、物理、terrain chunk。
# 严格遵守（重构方案八）：输入只依赖 layout（边界+tile_size）+ build_result（节点注册表）
# +玩家位置+chunk 配置。**不读** procedural_dungeon.gd 的 _grid/_rooms/_streamed_* 内部字段，
# 不读 WFC/BSP 如何生成、陷阱为何放置、敌人如何选择。
extends Node
class_name DungeonStreamingController

# chunk 配置（与 procedural_dungeon.gd 现存 const 对齐，迁移期锚）
const STREAM_CHUNK_SIZE_CELLS := 8
const STREAM_LIGHT_CHUNK_RADIUS := 2
const STREAM_PHYSICS_CHUNK_RADIUS := 1
const STREAM_VISUAL_CHUNK_RADIUS := 1
const STREAM_TERRAIN_CHUNK_RADIUS := 1
const STREAM_UPDATE_INTERVAL := 0.25
const DUNGEON_VISIBLE_LOCAL_LIGHT_BUDGET := 12

var _layout: DungeonLayout = null
var _build_result: DungeonBuildResult = null
var _player: Node3D = null

# 注册表（controller 自维护，不反向依赖 procedural 内部）
var _visual_chunks: Dictionary = {}        # Vector2i chunk -> Array[Node3D]
var _physics_chunks: Dictionary = {}       # Vector2i chunk -> Array[PhysicsBody3D]
var _terrain_chunks: Dictionary = {}       # Vector2i chunk -> Array[Node3D]
var _light_chunks: Dictionary = {}         # Vector2i chunk -> Array[Light3D]
var _last_player_chunk := Vector2i(999999, 999999)
var _last_active_physics_chunks: Dictionary = {}
var _streaming_ready := false
var _update_timer := 0.0

## 配置 controller。layout 提供边界与 tile_size；build_result 提供已注册节点。
func configure(layout: DungeonLayout, build_result: DungeonBuildResult) -> void:
	_layout = layout
	_build_result = build_result
	# 从 build_result 收导已注册节点（视觉/物理/terrain）
	if build_result != null:
		for node in build_result.streamed_visual_nodes:
			register_visual_node(node)
		for node in build_result.streamed_physics_nodes:
			register_physics_node(node)
		for chunk in build_result.terrain_chunks.keys():
			for node in build_result.terrain_chunks[chunk]:
				register_terrain_chunk(chunk, node)
	_streaming_ready = true

## 设置玩家引用（用于每帧取 global_position）
func set_player(player: Node3D) -> void:
	_player = player

## 注册一个视觉节点（按其位置归 chunk）。重复注册不重复处理。
func register_visual_node(node: Node3D) -> void:
	if node == null or node.get_meta("stream_visual_registered", false):
		return
	var chunk := _world_to_chunk(_node_position(node))
	node.set_meta("stream_visual_registered", true)
	node.set_meta("stream_visual_chunk", chunk)
	if not _visual_chunks.has(chunk):
		_visual_chunks[chunk] = []
	_visual_chunks[chunk].append(node)
	node.visible = false
	if _streaming_ready:
		update_streaming(true)

## 注册一个物理节点（收集其下所有 PhysicsBody3D）。
func register_physics_node(node: Node) -> void:
	if node == null:
		return
	var bodies: Array[Dictionary] = []
	_collect_physics_bodies(node, bodies)
	for entry in bodies:
		_register_one_physics_body(entry["body"], entry["visual_root"])
	if _streaming_ready and not bodies.is_empty():
		update_streaming(true)

## 注册一个 terrain chunk 节点。
func register_terrain_chunk(chunk: Vector2i, node: Node3D) -> void:
	if not _terrain_chunks.has(chunk):
		_terrain_chunks[chunk] = []
	_terrain_chunks[chunk].append(node)

## 注册一个环境灯光节点。
func register_light(light: Light3D) -> void:
	if light == null:
		return
	var chunk := _world_to_chunk(light.global_position if light.is_inside_tree() else light.position)
	if not _light_chunks.has(chunk):
		_light_chunks[chunk] = []
	_light_chunks[chunk].append(light)
	light.visible = false

## 每帧驱动（调用方在 _process 调用，或 controller 自身是 Node 时由 _process 触发）。
## 增量：仅玩家跨 chunk 时重算；force 强制全重算。
func update_streaming(force: bool = false) -> void:
	if _layout == null or _layout.is_empty():
		return
	var player_pos := _player_position()
	var player_chunk := _world_to_chunk(player_pos)
	if not force and player_chunk == _last_player_chunk:
		return
	_last_player_chunk = player_chunk
	if force:
		_last_active_physics_chunks = {}
	_update_lights(player_chunk, player_pos)
	_update_physics(player_chunk)
	_update_visuals(player_chunk)
	_update_terrain(player_chunk)

## Node 自带 _process：按 STREAM_UPDATE_INTERVAL 节流自动更新。
func _process(delta: float) -> void:
	_update_timer += delta
	if _update_timer < STREAM_UPDATE_INTERVAL:
		return
	_update_timer = 0.0
	update_streaming(false)

## 清空所有注册。调用方负责释放节点本身。
func clear() -> void:
	_visual_chunks.clear()
	_physics_chunks.clear()
	_terrain_chunks.clear()
	_light_chunks.clear()
	_last_player_chunk = Vector2i(999999, 999999)
	_last_active_physics_chunks.clear()
	_streaming_ready = false
	_layout = null
	_build_result = null
	_player = null


# ── 内部：4 类 chunk 更新（从 procedural_dungeon.gd 迁出，去 _grid/_rooms 依赖）──────
func _update_lights(player_chunk: Vector2i, player_pos: Vector3) -> void:
	for chunk in _light_chunks.keys():
		for light in _light_chunks[chunk]:
			if is_instance_valid(light):
				light.visible = false
	var ranked: Array[Dictionary] = []
	for chunk in _iter_chunks(player_chunk, STREAM_LIGHT_CHUNK_RADIUS):
		var lights: Array = _light_chunks.get(chunk, [])
		for light in lights:
			if light != null and is_instance_valid(light):
				ranked.append({"light": light, "distance": light.global_position.distance_squared_to(player_pos)})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["distance"]) < float(b["distance"])
	)
	for i in range(mini(ranked.size(), DUNGEON_VISIBLE_LOCAL_LIGHT_BUDGET)):
		var light := ranked[i]["light"] as Light3D
		if light != null:
			light.visible = true

func _update_physics(player_chunk: Vector2i) -> void:
	var active := {}
	for chunk in _iter_chunks(player_chunk, STREAM_PHYSICS_CHUNK_RADIUS):
		active[chunk] = true
	# 新激活的 chunk：激活其中所有物理体
	for chunk in active.keys():
		if _last_active_physics_chunks.has(chunk):
			continue
		var bodies: Array = _physics_chunks.get(chunk, [])
		for body in bodies:
			if body != null and is_instance_valid(body):
				_set_physics_body_active(body, true)
	# 失活处理：遍历所有已注册 chunk，非 active 的全停用。
	# 不能只遍历 _last_active_physics_chunks.keys()——force 路径会清空它，导致远离失活被跳过。
	for chunk in _physics_chunks.keys():
		if active.has(chunk):
			continue
		var bodies: Array = _physics_chunks[chunk]
		for body in bodies:
			if body != null and is_instance_valid(body):
				_set_physics_body_active(body, false)
	_last_active_physics_chunks = active

func _update_visuals(player_chunk: Vector2i) -> void:
	if _visual_chunks.is_empty():
		return
	var active := {}
	for chunk in _iter_chunks(player_chunk, STREAM_VISUAL_CHUNK_RADIUS):
		active[chunk] = true
	for chunk in _visual_chunks.keys():
		var visible := active.has(chunk)
		var nodes: Array = _visual_chunks[chunk]
		for node in nodes:
			if node != null and is_instance_valid(node):
				node.visible = visible

func _update_terrain(player_chunk: Vector2i) -> void:
	if _terrain_chunks.is_empty():
		return
	var active := {}
	for chunk in _iter_chunks(player_chunk, STREAM_TERRAIN_CHUNK_RADIUS):
		active[chunk] = true
	for chunk in _terrain_chunks.keys():
		var visible := active.has(chunk)
		var nodes: Array = _terrain_chunks[chunk]
		for node in nodes:
			if node != null and is_instance_valid(node):
				node.visible = visible

# ── 物理体启停（从 procedural_dungeon.gd 迁出）────────────────────
func _collect_physics_bodies(node: Node, result: Array, visual_root: Node = null) -> void:
	if visual_root == null:
		visual_root = node
	if node is CharacterBody3D:
		result.append({"body": node, "visual_root": visual_root})
		return
	if node is RigidBody3D:
		result.append({"body": node, "visual_root": visual_root})
		return
	if node is StaticBody3D:
		result.append({"body": node, "visual_root": visual_root})
		return
	for child in node.get_children():
		_collect_physics_bodies(child, result, visual_root)

func _register_one_physics_body(body: PhysicsBody3D, visual_root: Node = null) -> void:
	if body.get_meta("stream_physics_registered", false):
		return
	var stream_position := _node_position(body)
	if visual_root is Node3D:
		stream_position = _node_position(visual_root as Node3D)
	var chunk := _world_to_chunk(stream_position)
	body.set_meta("stream_physics_registered", true)
	body.set_meta("stream_physics_chunk", chunk)
	body.set_meta("stream_collision_layer", body.collision_layer)
	body.set_meta("stream_collision_mask", body.collision_mask)
	if visual_root is Node3D:
		body.set_meta("stream_visual_root_id", (visual_root as Node3D).get_instance_id())
	if body is RigidBody3D:
		(body as RigidBody3D).freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	if not _physics_chunks.has(chunk):
		_physics_chunks[chunk] = []
	_physics_chunks[chunk].append(body)
	_set_physics_body_active(body, false)

func _set_physics_body_active(body: PhysicsBody3D, active: bool) -> void:
	# 不早返回：远离后再次设 false 必须强制 layer=0，否则激活残留的 layer 不会清。
	# （早返回会跳过 layer=0 设置，导致停用的 body 仍持碰撞。）
	body.set_meta("stream_physics_active", active)
	body.visible = active
	_set_visual_root_active(body, active)
	body.collision_layer = int(body.get_meta("stream_collision_layer", body.collision_layer)) if active else 0
	body.collision_mask = int(body.get_meta("stream_collision_mask", body.collision_mask)) if active else 0
	if body is RigidBody3D:
		var rigid := body as RigidBody3D
		rigid.freeze = not active
		rigid.sleeping = not active
		if active:
			rigid.sleeping = false
		else:
			rigid.linear_velocity = Vector3.ZERO
			rigid.angular_velocity = Vector3.ZERO
	elif body is CharacterBody3D and not active:
		(body as CharacterBody3D).velocity = Vector3.ZERO
	if body is CharacterBody3D:
		_set_character_callbacks(body as CharacterBody3D, active)

func _set_visual_root_active(body: PhysicsBody3D, active: bool) -> void:
	var root_id := int(body.get_meta("stream_visual_root_id", 0))
	if root_id == 0:
		return
	var root := instance_from_id(root_id) as Node3D
	if root == null or not is_instance_valid(root):
		return
	root.visible = active

func _set_character_callbacks(body: CharacterBody3D, active: bool) -> void:
	body.set_process(active)
	body.set_physics_process(active)
	for child in body.get_children():
		_set_node_callbacks_recursive(child, active)

func _set_node_callbacks_recursive(node: Node, active: bool) -> void:
	node.set_process(active)
	node.set_physics_process(active)
	for child in node.get_children():
		_set_node_callbacks_recursive(child, active)

# ── 工具：chunk 计算（去 procedural 的 TILE_SIZE 依赖，用 layout.tile_size）──────────
func _world_to_chunk(pos: Vector3) -> Vector2i:
	var tile_size: float = _layout.tile_size if _layout != null else 3.0
	var chunk_size := float(STREAM_CHUNK_SIZE_CELLS) * tile_size
	return Vector2i(int(floor(pos.x / chunk_size)), int(floor(pos.z / chunk_size)))

func _iter_chunks(center: Vector2i, radius: int) -> Array:
	var chunks: Array = []
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			chunks.append(Vector2i(x, y))
	return chunks

func _node_position(node: Node3D) -> Vector3:
	return node.global_position if node.is_inside_tree() else node.position

func _player_position() -> Vector3:
	if _player != null and is_instance_valid(_player):
		return _player.global_position
	# 无玩家时用 layout 中心近似（与 procedural 的 player_spawn_pos fallback 一致）
	if _layout != null and not _layout.is_empty():
		var half_w: float = float(_layout.width) * _layout.tile_size / 2.0
		var half_h: float = float(_layout.height) * _layout.tile_size / 2.0
		return Vector3(-half_w, 0.0, -half_h)
	return Vector3.ZERO
