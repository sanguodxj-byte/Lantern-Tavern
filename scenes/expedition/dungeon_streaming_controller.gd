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
var _physics_chunks: Dictionary = {}       # Vector2i chunk -> Array[CollisionObject3D]
var _terrain_chunks: Dictionary = {}       # Vector2i chunk -> Array[Node3D]
var _light_chunks: Dictionary = {}         # Vector2i chunk -> Array[Light3D]
var _last_player_chunk := Vector2i(999999, 999999)
var _last_active_physics_chunks: Dictionary = {}
var _last_active_visual_chunks: Dictionary = {}
var _last_active_terrain_chunks: Dictionary = {}
var _active_light_set: Dictionary = {}        # light_instance_id -> Light3D（当前已激活灯）
var _streaming_ready := false
var _update_timer := 0.0
var _streaming_state_initialized := false
var _streaming_refresh_count := 0

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
	# 玩家在地牢 _ready() 中刚生成时，下一次节流 tick 尚未到达；立即激活出生
	# chunk 的物理体，避免 CharacterBody3D 在首帧没有地面碰撞而掉出地图。
	if _streaming_ready:
		update_streaming(true)

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
	# 默认隐藏即暂停其下粒子/音频，避免隐藏火把仍在烧粒子/播音频。
	_apply_visual_side_effects(node, true)
	if _streaming_ready and _streaming_state_initialized:
		_set_visual_node_active(node, _is_chunk_within_radius(chunk, _last_player_chunk, STREAM_VISUAL_CHUNK_RADIUS))

## 注册一个物理节点（收集其下所有 PhysicsBody3D）。
func register_physics_node(node: Node) -> void:
	if node == null:
		return
	var bodies: Array[Dictionary] = []
	_collect_physics_bodies(node, bodies)
	for entry in bodies:
		_register_one_physics_body(entry["body"], entry["visual_root"])
	if _streaming_ready and _streaming_state_initialized:
		for entry in bodies:
			var body := entry["body"] as CollisionObject3D
			if body == null or not is_instance_valid(body):
				continue
			var chunk: Vector2i = body.get_meta("stream_physics_chunk", Vector2i.ZERO)
			_set_physics_body_active(body, _is_chunk_within_radius(chunk, _last_player_chunk, STREAM_PHYSICS_CHUNK_RADIUS))

## 注册一个 terrain chunk 节点。
func register_terrain_chunk(chunk: Vector2i, node: Node3D) -> void:
	if not _terrain_chunks.has(chunk):
		_terrain_chunks[chunk] = []
	_terrain_chunks[chunk].append(node)
	node.visible = false
	if _streaming_ready and _streaming_state_initialized:
		node.visible = _is_chunk_within_radius(chunk, _last_player_chunk, STREAM_TERRAIN_CHUNK_RADIUS)

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
	_streaming_refresh_count += 1
	_last_player_chunk = player_chunk
	_update_lights(player_chunk, player_pos, force)
	_update_physics(player_chunk)
	_update_visuals(player_chunk)
	_update_terrain(player_chunk)
	_streaming_state_initialized = true

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
	_last_active_visual_chunks.clear()
	_last_active_terrain_chunks.clear()
	_active_light_set.clear()
	_streaming_ready = false
	_streaming_state_initialized = false
	_streaming_refresh_count = 0
	_update_timer = 0.0
	_layout = null
	_build_result = null
	_player = null


# ── 内部：4 类 chunk 更新（从 procedural_dungeon.gd 迁出，去 _grid/_rooms 依赖）──────
func _update_lights(player_chunk: Vector2i, player_pos: Vector3, _force: bool) -> void:
	# force 只要求重新排名；保留旧集合才能做增量差分，避免全部灯先灭再亮。
	var ranked: Array[Dictionary] = []
	for chunk in _iter_chunks(player_chunk, STREAM_LIGHT_CHUNK_RADIUS):
		var lights: Array = _light_chunks.get(chunk, [])
		for light in lights:
			if light != null and is_instance_valid(light):
				ranked.append({"light": light, "distance": light.global_position.distance_squared_to(player_pos)})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["distance"]) < float(b["distance"])
	)
	var new_active: Dictionary = {}
	for i in range(mini(ranked.size(), DUNGEON_VISIBLE_LOCAL_LIGHT_BUDGET)):
		var light := ranked[i]["light"] as Light3D
		if light != null:
			new_active[light.get_instance_id()] = light
	# 增量：仅关闭离开预算/半径的旧灯，仅打开新进入预算的灯（不再全表 hide-all）。
	for lid in _active_light_set.keys():
		if not new_active.has(lid):
			var light: Light3D = _active_light_set[lid]
			if is_instance_valid(light):
				light.visible = false
	for lid in new_active.keys():
		if not _active_light_set.has(lid):
			var light: Light3D = new_active[lid]
			if is_instance_valid(light):
				light.visible = true
	_active_light_set = new_active

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
	# 仅停用刚离开半径的 chunk。注册时节点已经默认停用，因此无需扫描全地图。
	for chunk in _last_active_physics_chunks.keys():
		if active.has(chunk):
			continue
		var bodies: Array = _physics_chunks.get(chunk, [])
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
	# 新激活 chunk：仅对之前未激活的设置可见（并恢复粒子/音频）。
	for chunk in active.keys():
		if _last_active_visual_chunks.has(chunk):
			continue
		var nodes: Array = _visual_chunks.get(chunk, [])
		for node in nodes:
			if node != null and is_instance_valid(node):
				_set_visual_node_active(node, true)
	# 失活 chunk：仅对之前激活的设置不可见（并暂停粒子/音频）。
	for chunk in _last_active_visual_chunks.keys():
		if active.has(chunk):
			continue
		var nodes: Array = _visual_chunks.get(chunk, [])
		for node in nodes:
			if node != null and is_instance_valid(node):
				_set_visual_node_active(node, false)
	_last_active_visual_chunks = active

func _update_terrain(player_chunk: Vector2i) -> void:
	if _terrain_chunks.is_empty():
		return
	var active := {}
	for chunk in _iter_chunks(player_chunk, STREAM_TERRAIN_CHUNK_RADIUS):
		active[chunk] = true
	for chunk in active.keys():
		if _last_active_terrain_chunks.has(chunk):
			continue
		var nodes: Array = _terrain_chunks.get(chunk, [])
		for node in nodes:
			if node != null and is_instance_valid(node):
				node.visible = true
	for chunk in _last_active_terrain_chunks.keys():
		if active.has(chunk):
			continue
		var nodes: Array = _terrain_chunks.get(chunk, [])
		for node in nodes:
			if node != null and is_instance_valid(node):
				node.visible = false
	_last_active_terrain_chunks = active

## 设置视觉节点可见性，并随可见性暂停/恢复其下的粒子与 3D 音频，
## 避免隐藏的火把仍在烧粒子、播火焰音（灯光预算只控 OmniLight3D，不控粒子/音频）。
func _set_visual_node_active(node: Node3D, active: bool) -> void:
	node.visible = active
	_apply_visual_side_effects(node, not active)

func _apply_visual_side_effects(node: Node, paused: bool) -> void:
	if node is GPUParticles3D:
		(node as GPUParticles3D).emitting = not paused
	elif node is CPUParticles3D:
		(node as CPUParticles3D).emitting = not paused
	elif node is AudioStreamPlayer3D:
		(node as AudioStreamPlayer3D).stream_paused = paused
	for child in node.get_children():
		_apply_visual_side_effects(child, paused)

# ── 物理体启停（从 procedural_dungeon.gd 迁出）────────────────────
func _collect_physics_bodies(node: Node, result: Array, visual_root: Node = null) -> void:
	if visual_root == null:
		visual_root = node
	if node is CharacterBody3D:
		result.append({"body": node, "visual_root": visual_root})
		_collect_nested_areas(node, result, visual_root)
		return
	if node is RigidBody3D:
		result.append({"body": node, "visual_root": visual_root})
		_collect_nested_areas(node, result, visual_root)
		return
	if node is StaticBody3D:
		result.append({"body": node, "visual_root": visual_root})
		_collect_nested_areas(node, result, visual_root)
		_collect_nested_static_bodies(node, result, visual_root)
		return
	if node is Area3D:
		result.append({"body": node, "visual_root": visual_root})
		return
	for child in node.get_children():
		_collect_physics_bodies(child, result, visual_root)

func _collect_nested_areas(node: Node, result: Array, visual_root: Node) -> void:
	for child in node.get_children():
		if child is Area3D:
			result.append({"body": child, "visual_root": visual_root})
		_collect_nested_areas(child, result, visual_root)

func _collect_nested_static_bodies(node: Node, result: Array, visual_root: Node) -> void:
	for child in node.get_children():
		if child is StaticBody3D:
			result.append({"body": child, "visual_root": visual_root})
		_collect_nested_static_bodies(child, result, visual_root)

func _register_one_physics_body(body: CollisionObject3D, visual_root: Node = null) -> void:
	if body.get_meta("stream_physics_registered", false):
		return
	var stream_position := _node_position(body)
	if visual_root is Node3D:
		stream_position = _node_position(visual_root as Node3D)
	var chunk: Vector2i = _world_to_chunk(stream_position)
	if body.has_meta("stream_physics_chunk"):
		var chunk_hint = body.get_meta("stream_physics_chunk")
		if chunk_hint is Vector2i:
			chunk = chunk_hint
	body.set_meta("stream_physics_registered", true)
	body.set_meta("stream_physics_chunk", chunk)
	body.set_meta("stream_collision_layer", body.collision_layer)
	body.set_meta("stream_collision_mask", body.collision_mask)
	if body is Area3D:
		body.set_meta("stream_monitoring", (body as Area3D).monitoring)
		body.set_meta("stream_monitorable", (body as Area3D).monitorable)
	if visual_root is Node3D:
		body.set_meta("stream_visual_root_id", (visual_root as Node3D).get_instance_id())
	if body is RigidBody3D:
		(body as RigidBody3D).freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	if not _physics_chunks.has(chunk):
		_physics_chunks[chunk] = []
	_physics_chunks[chunk].append(body)
	_set_physics_body_active(body, false)

func _set_physics_body_active(body: CollisionObject3D, active: bool) -> void:
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
	elif body is Area3D:
		var area := body as Area3D
		area.monitoring = bool(area.get_meta("stream_monitoring", true)) if active else false
		area.monitorable = bool(area.get_meta("stream_monitorable", true)) if active else false
		_set_node_callbacks_recursive(area, active)

func _set_visual_root_active(body: CollisionObject3D, active: bool) -> void:
	var root_id := int(body.get_meta("stream_visual_root_id", 0))
	if root_id == 0:
		return
	var root := instance_from_id(root_id) as Node3D
	if root == null or not is_instance_valid(root):
		return
	root.visible = active
	# 物理注册节点（如火把：仅注册为 physics 节点，无可视节点）也需随可见性暂停其下
	# 粒子与音频，否则隐藏的火把仍常播火焰音（灯光预算只控 OmniLight3D，不控音频/粒子）。
	_apply_visual_side_effects(root, not active)

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

func _is_chunk_within_radius(chunk: Vector2i, center: Vector2i, radius: int) -> bool:
	return absi(chunk.x - center.x) <= radius and absi(chunk.y - center.y) <= radius

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
