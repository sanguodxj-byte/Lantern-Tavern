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
# 动态体（敌人等）视觉激活半径（米）：物理在 24m 停用后，视觉仍保持到该半径，
# 让敌人自带的 billboard/imposter 纸片 LOD（ENEMY_VISIBILITY_RANGE_END=36m）接管远距渲染，
# 避免跨 chunk 边界从无到有地"凭空出现"。与 enemy.gd 的 LOD 远裁剪对齐。
const STREAM_DYNAMIC_VISUAL_ACTIVATION_DISTANCE := 36.0
# 动态体视觉扫描 chunk 半径：须覆盖 _dynamic_visual_activation_distance()（36m）在
# 玩家位于 chunk 边缘时仍能被扫描到（chunk=24m，半径 2 即 ±48m）。
const STREAM_DYNAMIC_VISUAL_CHUNK_RADIUS := 2

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
var _forced_hunt_enemies: Dictionary = {}     # enemy_instance_id -> CharacterBody3D（事件驱动缓存）
var _streaming_ready := false
var _update_timer := 0.0
var _streaming_state_initialized := false
var _streaming_refresh_count := 0
var _forced_hunt_refresh_requested := false

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
			var body := _collision_object_or_null(entry.get("body"))
			if body == null or not is_instance_valid(body):
				continue
			var chunk: Vector2i = body.get_meta("stream_physics_chunk", Vector2i.ZERO)
			_set_physics_body_active(body, _should_activate_physics_body(body, chunk, _last_player_chunk))

## 敌人的全图暗蚀追击状态由 Enemy.set_dark_erosion_hunt 事件驱动通知。
## 这样玩家停留在同一 chunk 时，streaming tick 不再扫描整个物理注册表。
func notify_forced_hunt_changed(enemy: CharacterBody3D, active: bool) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var enemy_id := enemy.get_instance_id()
	if active:
		_forced_hunt_enemies[enemy_id] = enemy
	else:
		_forced_hunt_enemies.erase(enemy_id)
	_forced_hunt_refresh_requested = true

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
	# 动态注册的地牢灯也必须遵守环境光源无镜面规范，不能依赖 runtime 初始扫描。
	light.light_specular = 0.0
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
	var has_forced_hunt := _has_forced_hunt_enemies()
	if not force and player_chunk == _last_player_chunk \
			and not has_forced_hunt and not _forced_hunt_refresh_requested:
		return
	_forced_hunt_refresh_requested = false
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
	_forced_hunt_enemies.clear()
	_forced_hunt_refresh_requested = false
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
	_prune_invalid_physics_bodies()
	var active := {}
	for chunk in _iter_chunks(player_chunk, STREAM_PHYSICS_CHUNK_RADIUS):
		active[chunk] = true
	var forced_hunt_chunks := _collect_forced_hunt_physics_chunks()
	for chunk in forced_hunt_chunks.keys():
		active[chunk] = true
	# 新激活的 chunk：激活其中所有物理体
	for chunk in active.keys():
		if _last_active_physics_chunks.has(chunk):
			continue
		var bodies: Array = _physics_chunks.get(chunk, [])
		for body_variant in bodies:
			var body := _collision_object_or_null(body_variant)
			if body != null:
				var forced_environment := forced_hunt_chunks.has(chunk) and not _is_dynamic_stream_body(body)
				_set_physics_body_active(body, forced_environment \
					or _should_activate_physics_body(body, chunk, player_chunk))
	# 仅停用刚离开半径的 chunk。注册时节点已经默认停用，因此无需扫描全地图。
	# 动态体不在此处无条件隐藏：追逐跨界但仍在距离阈值内的敌人由下方 reconcile 按
	# 实时位置重新激活，这里只处理确实应停用的静态体/远距动态体。
	for chunk in _last_active_physics_chunks.keys():
		if active.has(chunk):
			continue
		var bodies: Array = _physics_chunks.get(chunk, [])
		for body_variant in bodies:
			var body := _collision_object_or_null(body_variant)
			if body != null:
				_set_physics_body_active(body, _should_activate_physics_body(body, chunk, player_chunk))
	# 3x3 静态碰撞仍保留，但动态体只允许当前 chunk 激活。玩家跨 chunk 时，
	# 旧的 3x3 交集不会经过上面的进入/离开分支，因此必须在局部 union 内重算动态体。
	# 另把视觉半径（radius 2）的 chunk 并入扫描集合：reconcile 只处理动态体，
	# 保证 24–36m 纸片带（含玩家在 chunk 边缘时）的动态体可见性始终正确。
	var reconcile_chunks := active.duplicate()
	for chunk in _last_active_physics_chunks.keys():
		reconcile_chunks[chunk] = true
	for chunk in _iter_chunks(player_chunk, STREAM_DYNAMIC_VISUAL_CHUNK_RADIUS):
		reconcile_chunks[chunk] = true
	var rehome_list: Array = []
	for chunk in reconcile_chunks.keys():
		var reconcile_bodies: Array = _physics_chunks.get(chunk, [])
		for body_variant in reconcile_bodies:
			var reconcile_body := _collision_object_or_null(body_variant)
			if reconcile_body != null and _is_dynamic_stream_body(reconcile_body):
				_set_physics_body_active(reconcile_body, _should_activate_physics_body(reconcile_body, chunk, player_chunk))
				if bool(reconcile_body.get_meta("stream_physics_active", false)):
					rehome_list.append(reconcile_body)
	# 追逐跨 chunk 的动态体：激活后按其实时位置重新归位到当前 chunk，
	# 否则其注册 chunk 一旦离开 union 就再也不会被扫描，激活状态会永久泄漏。
	for body in rehome_list:
		_rehome_dynamic_body(body)
	_last_active_physics_chunks = active
	# 强制追击敌人可能未被注册为 streamed physics（例如迟到的运行时实体），
	# 但仍必须保持 CharacterBody3D 的 AI 物理处理；这里只遍历事件缓存，不扫全地图。
	_prune_invalid_forced_hunt_enemies()
	for enemy_variant in _forced_hunt_enemies.values():
		var enemy := enemy_variant as CharacterBody3D
		if enemy == null or not is_instance_valid(enemy):
			continue
		_set_physics_body_active(enemy, true)
		enemy.set_meta("stream_forced_hunt_active", true)

## 满暗蚀敌人移动时，玩家所在 chunk 不变也必须刷新其脚下环境碰撞。
## 只遍历强制追击缓存，物理注册表规模不会放大这条路径的开销。
func _collect_forced_hunt_physics_chunks() -> Dictionary:
	var chunks := {}
	_prune_invalid_forced_hunt_enemies()
	for enemy_variant in _forced_hunt_enemies.values():
		var enemy := enemy_variant as CharacterBody3D
		if enemy == null or not is_instance_valid(enemy):
			continue
		var enemy_chunk := _world_to_chunk(enemy.global_position)
		for chunk in _iter_chunks(enemy_chunk, STREAM_PHYSICS_CHUNK_RADIUS):
			chunks[chunk] = true
	return chunks

func _prune_invalid_forced_hunt_enemies() -> void:
	var stale_ids: Array[int] = []
	for enemy_id in _forced_hunt_enemies.keys():
		var enemy := _forced_hunt_enemies.get(enemy_id) as CharacterBody3D
		if enemy == null or not is_instance_valid(enemy) or not _is_forced_hunt_enemy(enemy):
			stale_ids.append(int(enemy_id))
	for enemy_id in stale_ids:
		_forced_hunt_enemies.erase(enemy_id)

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
	if not is_instance_valid(body):
		return
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
	if _is_forced_hunt_enemy(body):
		_forced_hunt_enemies[body.get_instance_id()] = body
	_set_physics_body_active(body, false)

func _should_activate_physics_body(body: CollisionObject3D, chunk: Vector2i, player_chunk: Vector2i) -> bool:
	if _is_forced_hunt_enemy(body):
		return true
	if _is_dynamic_stream_body(body):
		# 动态体（敌人/掉落/触发器）按与玩家的实时距离激活（阈值=一个 chunk 尺寸，24m），
		# 而非注册 chunk 是否与玩家 chunk 相同：跨 chunk 边界仅 1m 的敌人不应因注册
		# chunk 不同被整根隐藏，追逐跨界敌人也按当前位置保持激活。
		var activation_dist := _dynamic_activation_distance()
		return _node_position(body).distance_to(_player_position()) <= activation_dist
	return _is_chunk_within_radius(chunk, player_chunk, STREAM_PHYSICS_CHUNK_RADIUS)

func _dynamic_activation_distance() -> float:
	var tile_size: float = _layout.tile_size if _layout != null else 3.0
	return float(STREAM_CHUNK_SIZE_CELLS) * tile_size

## 动态体是否仍应在物理休眠时保持可见：距玩家在视觉激活半径内（36m，纸片 LOD 带）。
## 强制追击敌人（暗蚀满时全图追击）始终可见，避免追击者整根消失。
func _should_keep_dynamic_body_visible(body: CollisionObject3D) -> bool:
	if _is_forced_hunt_enemy(body):
		return true
	return _node_position(body).distance_to(_player_position()) <= STREAM_DYNAMIC_VISUAL_ACTIVATION_DISTANCE

func _is_dynamic_stream_body(body: CollisionObject3D) -> bool:
	return body is CharacterBody3D or body is RigidBody3D or body is Area3D

## 将动态体从其注册 chunk 桶重新归位到实时位置所在 chunk，并更新 meta。
## 仅用于活跃动态体（避免追逐跨界后注册 chunk 残留导致激活状态泄漏）。
func _rehome_dynamic_body(body: CollisionObject3D) -> void:
	if not is_instance_valid(body):
		return
	var current_chunk := _world_to_chunk(_node_position(body))
	var registered_chunk: Vector2i = body.get_meta("stream_physics_chunk", current_chunk)
	if current_chunk == registered_chunk:
		return
	var bucket: Array = _physics_chunks.get(registered_chunk, [])
	bucket.erase(body)
	body.set_meta("stream_physics_chunk", current_chunk)
	if not _physics_chunks.has(current_chunk):
		_physics_chunks[current_chunk] = []
	if not _physics_chunks[current_chunk].has(body):
		_physics_chunks[current_chunk].append(body)

func _set_physics_body_active(body: CollisionObject3D, active: bool) -> void:
	if not is_instance_valid(body):
		return
	# 可见性从物理激活解耦：动态体（敌人等）物理在 24m 停用后，只要仍在视觉半径
	# （36m，与 enemy.gd 的 billboard/imposter LOD 对齐）内就保持可见，让远距纸片
	# LOD 接管渲染，避免玩家跨 chunk 时敌人从无到有"凭空出现"。静态体仍按 chunk。
	var visible := active
	var keep_visual_process := false
	if not active and _is_dynamic_stream_body(body):
		visible = _should_keep_dynamic_body_visible(body)
		keep_visual_process = visible
	# 不早返回：远离后再次设 false 必须强制 layer=0，否则激活残留的 layer 不会清。
	# （早返回会跳过 layer=0 设置，导致停用的 body 仍持碰撞。）
	body.set_meta("stream_physics_active", active)
	body.visible = visible
	if body is CharacterBody3D and body.has_method("set_streaming_physics_active"):
		(body as CharacterBody3D).set_streaming_physics_active(active)
	_set_visual_root_active(body, visible)
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
		_set_character_callbacks(body as CharacterBody3D, active, keep_visual_process)
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

func _set_character_callbacks(body: CharacterBody3D, active: bool, keep_visual_process: bool = false) -> void:
	# 可见但物理休眠的动态体（24–36m 纸片 LOD 带）：保留 _process 让 enemy.gd 的
	# _update_render_optimization 继续运行（billboard/imposter 切换、动画暂停），
	# 但停掉 _physics_process 与子节点，避免远距敌人仍跑 AI 寻路。
	body.set_process(active or keep_visual_process)
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

func _is_forced_hunt_enemy(body: CollisionObject3D) -> bool:
	if not is_instance_valid(body):
		return false
	return body is CharacterBody3D \
		and body.is_in_group("enemies") \
		and bool(body.get_meta("dark_erosion_hunt", false))

func _has_forced_hunt_enemies() -> bool:
	_prune_invalid_physics_bodies()
	_prune_invalid_forced_hunt_enemies()
	return not _forced_hunt_enemies.is_empty()

func _node_position(node: Node3D) -> Vector3:
	if not is_instance_valid(node):
		return Vector3.ZERO
	return node.global_position if node.is_inside_tree() else node.position

func _collision_object_or_null(value: Variant) -> CollisionObject3D:
	# is_instance_valid must run before `as`: a queued/free'd Godot object can
	# still remain in a registry until the next streaming refresh.
	if not is_instance_valid(value):
		return null
	if not (value is CollisionObject3D):
		return null
	return value as CollisionObject3D

func _prune_invalid_physics_bodies() -> void:
	for chunk in _physics_chunks.keys():
		var valid_bodies: Array = []
		for body_variant in _physics_chunks.get(chunk, []):
			var body := _collision_object_or_null(body_variant)
			if body != null:
				valid_bodies.append(body)
		_physics_chunks[chunk] = valid_bodies

func _player_position() -> Vector3:
	if _player != null and is_instance_valid(_player):
		return _player.global_position if _player.is_inside_tree() else _player.position
	# 无玩家时用 layout 中心近似（与 procedural 的 player_spawn_pos fallback 一致）
	if _layout != null and not _layout.is_empty():
		var half_w: float = float(_layout.width) * _layout.tile_size / 2.0
		var half_h: float = float(_layout.height) * _layout.tile_size / 2.0
		return Vector3(-half_w, 0.0, -half_h)
	return Vector3.ZERO
