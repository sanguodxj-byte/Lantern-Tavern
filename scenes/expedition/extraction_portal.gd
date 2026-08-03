class_name ExtractionPortal
extends StaticBody3D

## 体素风撤离传送门。
## 用 BoxMesh 组合搭建（石质底座 + 四角发光符文柱 + 顶部方形光环 + 顶光），
## 取代原先的扁平 CylinderMesh 圆盘。collision_layer = LAYER_SCENE_OBJECT(64)，
## 使玩家 SelectRaycast(mask=72) 可命中并在准星悬停时显示交互提示。
## 玩家进入中心区域后按 [E] 开始撤离引导。引导完成前不会结算撤离；
## 再次交互、离开区域或受到伤害都会取消，避免战斗中无风险秒退。

signal extraction_requested(player: Player)
signal extraction_started(player: Player, duration: float)
signal extraction_progress(player: Player, progress: float, remaining: float)
signal extraction_cancelled(player: Player, reason: String)

const LAYER_SCENE_OBJECT := 64
const HEAVY_LOAD_THRESHOLD := 0.7
const TERRAIN_CFG := preload("res://scenes/expedition/dungeon_terrain_config.gd")
const PILLAR_CENTER := 0.72
const PILLAR_SIZE := Vector3(0.22, 1.27, 0.22)
const PILLAR_Y := 0.795
const TOP_BEAM_Y := 1.49
const TOP_BEAM_LENGTH := 1.22
const RUNE_EMISSION_IDLE := 0.22
const RUNE_EMISSION_ACTIVE_BOOST := 0.68
const PORTAL_LIGHT_IDLE := 0.9
const PORTAL_LIGHT_ACTIVE_BOOST := 0.9

@export var interaction_name := "撤离点"
@export var interaction_verb := "开始撤离引导"
@export var normal_extraction_duration := 1.5
@export var heavy_extraction_duration := 2.0

var _stone_mat: ShaderMaterial
var _rune_mat: ShaderMaterial
var _portal_core: MeshInstance3D = null
var _portal_light: OmniLight3D = null
var _players_in_area: Array[Player] = []
var _active_player: Player = null
var _active_duration := 0.0
var _elapsed := 0.0
var _start_position := Vector3.ZERO
var _previous_movement_input_enabled := true
var _completed := false


func _ready() -> void:
	collision_layer = LAYER_SCENE_OBJECT
	collision_mask = 0
	set_meta("topdown_kind", "extraction")
	_ensure_materials()
	_build_visual()
	_add_pillar_collision()
	_add_trigger_area()
	if GameEvents != null and not GameEvents.player_hurt.is_connected(_on_player_hurt):
		GameEvents.player_hurt.connect(_on_player_hurt)


func _exit_tree() -> void:
	_restore_player_movement()
	_active_player = null
	_players_in_area.clear()


func _ensure_materials() -> void:
	if _stone_mat != null:
		return
	_stone_mat = TERRAIN_CFG.make_terrain_mat("BARONY_PLATFORM", Vector2.ONE, {
		"world_aligned_uv": true,
		"meters_per_tile": 0.75,
		"albedo_tint": Color(0.90, 0.86, 0.78),
		"roughness": 0.95,
		"voxel_base_fill": 0.12,
	})
	_rune_mat = TERRAIN_CFG.make_terrain_mat("PORTAL", Vector2.ONE, {
		"world_aligned_uv": true,
		"meters_per_tile": 0.5,
		"albedo_tint": Color(0.42, 1.0, 0.82),
		"emission_tint": Color(0.0, 0.82, 0.62),
		"emission_strength": RUNE_EMISSION_IDLE,
		"roughness": 0.88,
		"voxel_base_fill": 0.08,
	})


func _box(node_name: String, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	add_child(m)
	return m


func _build_visual() -> void:
	# 石质底座平台 + 边缘收边
	_box("PortalBase", Vector3(1.7, 0.12, 1.7), Vector3(0, 0.06, 0), _stone_mat)
	_box("PortalBaseRim", Vector3(1.8, 0.04, 1.8), Vector3(0, 0.14, 0), _stone_mat)
	# 中心发光地砖是引导区域的视觉锚点，踏入本身不触发撤离。
	_box("PortalCoreTile", Vector3(1.0, 0.025, 1.0), Vector3(0, 0.1725, 0), _rune_mat)
	# 四角石柱承重，符文仅作为贴合柱面的发光嵌条。
	var corners := [
		Vector3(-PILLAR_CENTER, 0, -PILLAR_CENTER), Vector3(PILLAR_CENTER, 0, -PILLAR_CENTER),
		Vector3(-PILLAR_CENTER, 0, PILLAR_CENTER), Vector3(PILLAR_CENTER, 0, PILLAR_CENTER),
	]
	for corner in corners:
		var cx := int(round(corner.x * 100.0))
		var cz := int(round(corner.z * 100.0))
		_box("StonePillar_%d_%d" % [cx, cz], PILLAR_SIZE, Vector3(corner.x, PILLAR_Y, corner.z), _stone_mat)
		_box("RuneInsetX_%d_%d" % [cx, cz], Vector3(0.04, 0.78, 0.10),
			Vector3(corner.x + signf(corner.x) * 0.13, 0.82, corner.z), _rune_mat)
		_box("RuneInsetZ_%d_%d" % [cx, cz], Vector3(0.10, 0.78, 0.04),
			Vector3(corner.x, 0.82, corner.z + signf(corner.z) * 0.13), _rune_mat)
	# 四根石梁在柱侧面之间以面接触连接，不在角部互相穿插。
	_box("TopBeamNS_a", Vector3(0.22, 0.12, TOP_BEAM_LENGTH), Vector3(-PILLAR_CENTER, TOP_BEAM_Y, 0), _stone_mat)
	_box("TopBeamNS_b", Vector3(0.22, 0.12, TOP_BEAM_LENGTH), Vector3(PILLAR_CENTER, TOP_BEAM_Y, 0), _stone_mat)
	_box("TopBeamEW_a", Vector3(TOP_BEAM_LENGTH, 0.12, 0.22), Vector3(0, TOP_BEAM_Y, -PILLAR_CENTER), _stone_mat)
	_box("TopBeamEW_b", Vector3(TOP_BEAM_LENGTH, 0.12, 0.22), Vector3(0, TOP_BEAM_Y, PILLAR_CENTER), _stone_mat)
	_box("TopRuneNS_a", Vector3(0.06, 0.03, 0.92), Vector3(-PILLAR_CENTER, 1.565, 0), _rune_mat)
	_box("TopRuneNS_b", Vector3(0.06, 0.03, 0.92), Vector3(PILLAR_CENTER, 1.565, 0), _rune_mat)
	_box("TopRuneEW_a", Vector3(0.92, 0.03, 0.06), Vector3(0, 1.565, -PILLAR_CENTER), _rune_mat)
	_box("TopRuneEW_b", Vector3(0.92, 0.03, 0.06), Vector3(0, 1.565, PILLAR_CENTER), _rune_mat)
	# 顶部中心光核
	_portal_core = _box("TopCore", Vector3(0.42, 0.42, 0.42), Vector3(0, TOP_BEAM_Y, 0), _rune_mat)
	# 顶光：青绿色泛光，照亮传送门下方地面
	_portal_light = OmniLight3D.new()
	_portal_light.name = "PortalLight"
	_portal_light.position = Vector3(0, 1.5, 0)
	_portal_light.light_color = Color(0.0, 0.8, 0.6)
	_portal_light.light_energy = PORTAL_LIGHT_IDLE
	_portal_light.light_specular = 0.0
	_portal_light.omni_range = 9.0
	_portal_light.omni_attenuation = 1.2
	add_child(_portal_light)


func _add_pillar_collision() -> void:
	# 仅四角柱子参与碰撞（layer=64）：玩家射线可命中以显示悬停提示，
	# 同时玩家可从柱子间穿入触发 Area3D 撤离，不会被底座挡住。
	var corners := [
		Vector3(-PILLAR_CENTER, 0, -PILLAR_CENTER), Vector3(PILLAR_CENTER, 0, -PILLAR_CENTER),
		Vector3(-PILLAR_CENTER, 0, PILLAR_CENTER), Vector3(PILLAR_CENTER, 0, PILLAR_CENTER),
	]
	for corner in corners:
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = PILLAR_SIZE
		col.shape = shape
		col.position = Vector3(corner.x, PILLAR_Y, corner.z)
		add_child(col)


func _add_trigger_area() -> void:
	var area := Area3D.new()
	area.name = "ExtractionArea"
	area.set_meta("topdown_kind", "extraction")
	area.collision_layer = PhysicsSetup.LAYER_TRIGGER
	area.collision_mask = PhysicsSetup.LAYER_PLAYER
	area.monitoring = true
	area.monitorable = true
	area.position = Vector3(0, 1.0, 0)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.8, 2.4, 1.8)
	col.shape = box
	area.add_child(col)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	add_child(area)


func _on_body_entered(body: Node3D) -> void:
	var player := body as Player
	if player != null and not _players_in_area.has(player):
		_players_in_area.append(player)


func _on_body_exited(body: Node3D) -> void:
	var player := body as Player
	if player == null:
		return
	_players_in_area.erase(player)
	if player == _active_player:
		cancel_extraction("left_area")


func interact(actor: Node = null) -> void:
	var player_node: Node3D = actor if actor is Player else null
	if player_node == null:
		# P1-5：统一玩家解析（actor 缺省时按单机全局；联机交互由会话权威处理）。
		player_node = GameState.resolve_player_node(0) as Node3D
	var player := player_node as Player
	if player == null or _completed:
		return
	if player == _active_player:
		cancel_extraction("manual")
		return
	if not _players_in_area.has(player):
		extraction_cancelled.emit(player, "not_inside")
		return
	begin_extraction(player)


func begin_extraction(player: Player) -> bool:
	if player == null or _completed or _active_player != null or not _players_in_area.has(player):
		return false
	_active_player = player
	_active_duration = get_required_duration()
	_elapsed = 0.0
	_start_position = _player_position(player)
	_previous_movement_input_enabled = player.movement_input_enabled
	player.movement_input_enabled = false
	player.velocity.x = 0.0
	player.velocity.z = 0.0
	interaction_verb = "取消撤离引导"
	_set_visual_progress(0.0)
	extraction_started.emit(player, _active_duration)
	extraction_progress.emit(player, 0.0, _active_duration)
	return true


func _physics_process(delta: float) -> void:
	advance_extraction(delta)


func advance_extraction(delta: float) -> void:
	if _active_player == null or not is_instance_valid(_active_player) or delta <= 0.0:
		return
	if _player_position(_active_player).distance_squared_to(_start_position) > 0.04:
		cancel_extraction("moved")
		return
	_elapsed = minf(_elapsed + delta, _active_duration)
	var progress := clampf(_elapsed / maxf(_active_duration, 0.001), 0.0, 1.0)
	_set_visual_progress(progress)
	extraction_progress.emit(_active_player, progress, maxf(0.0, _active_duration - _elapsed))
	if progress >= 1.0:
		complete_extraction()


func cancel_extraction(reason: String = "manual") -> void:
	if _active_player == null:
		return
	var player := _active_player
	_restore_player_movement()
	_clear_active_state()
	_set_visual_progress(0.0)
	extraction_cancelled.emit(player, reason)


func complete_extraction() -> void:
	if _active_player == null:
		return
	var player := _active_player
	_completed = true
	_restore_player_movement()
	_clear_active_state()
	_set_visual_progress(1.0)
	extraction_requested.emit(player)


func get_required_duration() -> float:
	var used := 0
	var limit := 0
	if GameState != null:
		used = GameState.get_carried_space_used()
		limit = GameState.get_carried_space_limit()
	return duration_for_load(used, limit, normal_extraction_duration, heavy_extraction_duration)


static func duration_for_load(used: int, limit: int, normal_duration: float = 1.5,
		heavy_duration: float = 2.0) -> float:
	if limit > 0 and float(maxi(used, 0)) / float(limit) >= HEAVY_LOAD_THRESHOLD:
		return maxf(heavy_duration, 0.1)
	return maxf(normal_duration, 0.1)


func is_extracting() -> bool:
	return _active_player != null


func get_extraction_progress() -> float:
	if _active_player == null:
		return 0.0
	return clampf(_elapsed / maxf(_active_duration, 0.001), 0.0, 1.0)


func _on_player_hurt(player: Player) -> void:
	if player != null and player == _active_player:
		cancel_extraction("hurt")


func _restore_player_movement() -> void:
	if _active_player != null and is_instance_valid(_active_player):
		_active_player.movement_input_enabled = _previous_movement_input_enabled


func _player_position(player: Player) -> Vector3:
	return player.global_position if player.is_inside_tree() else player.position


func _clear_active_state() -> void:
	_active_player = null
	_active_duration = 0.0
	_elapsed = 0.0
	interaction_verb = "开始撤离引导"


func _set_visual_progress(progress: float) -> void:
	var value := clampf(progress, 0.0, 1.0)
	if _rune_mat != null:
		_rune_mat.set_shader_parameter("emission_strength", RUNE_EMISSION_IDLE + value * RUNE_EMISSION_ACTIVE_BOOST)
	if _portal_core != null:
		var pulse := 1.0 + value * 0.35
		_portal_core.scale = Vector3(pulse, pulse, pulse)
	if _portal_light != null:
		_portal_light.light_energy = PORTAL_LIGHT_IDLE + value * PORTAL_LIGHT_ACTIVE_BOOST
