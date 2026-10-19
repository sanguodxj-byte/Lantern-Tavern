@tool
class_name ExtractionPortal
extends StaticBody3D
## @tool：编辑器内也构建视觉（_build_visual 只读操作），便于编辑器视口直接
## 预览与 MCP 视口截图验收；运行时行为不受影响（物理/计时仅在游戏内触发）。

## 体素风撤离传送门。
## 用 BoxMesh 组合搭建（石质底座 + 四角发光符文柱 + 顶部方形光环 + 顶光）。
## collision_layer = LAYER_SCENE_OBJECT(64)，使玩家 SelectRaycast(mask=72) 可命中。
##
## 撤离机制（2026-08-06 用户裁定：逃离塔科夫式自动撤离，取代按住引导）：
##   * 玩家踏入撤离区域【自动】开始撤离倒计时——无需交互、无需按住；
##   * 区域内可自由移动与战斗，倒计时不受影响（受击不取消）；
##   * 离开撤离区域 → 该玩家倒计时重置（重新进入重新计时）；
##   * 倒计时结束 → 发出 extraction_requested（结算离场由调用方处理）；
##   * per-player 独立计时：多名玩家同时在场各自倒计时，互不影响。
## 术语见 docs/术语表.md「撤离引导」。

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
@export var interaction_verb := "进入区域自动撤离"
@export var normal_extraction_duration := 1.5
@export var heavy_extraction_duration := 2.0

var _stone_mat: ShaderMaterial
var _rune_mat: ShaderMaterial
var _portal_core: MeshInstance3D = null
var _portal_light: OmniLight3D = null
## per-player 撤离倒计时状态：player_id -> {"duration": float, "elapsed": float}
## （2026-08-06：per-peer 独立计时，多玩家互不影响；替代旧单 _active_player 引导状态）。
var _extract_state: Dictionary = {}
## 已完成撤离的玩家（per-player 完成保护，替代旧全局 _completed）。
var _completed_players: Dictionary = {}


func _ready() -> void:
	collision_layer = LAYER_SCENE_OBJECT
	collision_mask = 0
	set_meta("topdown_kind", "extraction")
	_ensure_materials()
	_build_visual()
	_add_pillar_collision()
	_add_trigger_area()


func _exit_tree() -> void:
	_extract_state.clear()
	_completed_players.clear()


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
	# 中心发光地砖是撤离区域的视觉锚点。
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
	if player == null or _completed_players.has(player.get_instance_id()):
		return
	# 2026-08-06（用户裁定）：踏入区域即自动开始撤离倒计时（无需交互）。
	if _extract_state.has(player.get_instance_id()):
		return
	var duration := get_required_duration()
	_extract_state[player.get_instance_id()] = {
		"player": player, "duration": duration, "elapsed": 0.0,
	}
	_set_visual_progress(0.0)
	extraction_started.emit(player, duration)
	extraction_progress.emit(player, 0.0, duration)


func _on_body_exited(body: Node3D) -> void:
	var player := body as Player
	if player == null:
		return
	# 离开区域 → 该玩家倒计时重置（重新进入重新计时）。
	if _extract_state.erase(player.get_instance_id()):
		extraction_cancelled.emit(player, "left_area")
	_update_visual_progress()


func interact(_actor: Node = null) -> void:
	# 2026-08-06（用户裁定）：撤离不再需要交互——踏入区域自动倒计时。
	# 保留空实现以兼容旧调用方（Player 交互提示仍显示区域信息）。
	pass


func _physics_process(delta: float) -> void:
	advance_extraction(delta)


## 推进所有在场玩家的撤离倒计时（per-player 独立）。
func advance_extraction(delta: float) -> void:
	if delta <= 0.0 or _extract_state.is_empty():
		return
	var completed: Array = []
	for key in _extract_state.keys():
		var st: Dictionary = _extract_state[key]
		var player: Player = st.get("player")
		if player == null or not is_instance_valid(player):
			completed.append(key)
			continue
		var duration: float = float(st.get("duration", 1.5))
		st["elapsed"] = minf(float(st.get("elapsed", 0.0)) + delta, duration)
		var progress := clampf(float(st["elapsed"]) / maxf(duration, 0.001), 0.0, 1.0)
		extraction_progress.emit(player, progress, maxf(0.0, duration - float(st["elapsed"])))
		if progress >= 1.0:
			completed.append(key)
	for key in completed:
		var st: Dictionary = _extract_state.get(key, {})
		_extract_state.erase(key)
		var player: Player = st.get("player")
		if player != null and is_instance_valid(player):
			complete_extraction(player)
	_update_visual_progress()


func complete_extraction(player: Player) -> void:
	# per-player 完成保护：同一玩家只结算一次，其他玩家可独立完成。
	var pid := player.get_instance_id()
	if _completed_players.has(pid):
		return
	_completed_players[pid] = true
	_set_visual_progress(1.0)
	extraction_requested.emit(player)


## 玩家所需撤离时长（按当前负重：容量 70% 以上用 heavy 档）。
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


## 是否有玩家正在撤离倒计时中。
func is_extracting() -> bool:
	return not _extract_state.is_empty()


## 指定玩家的撤离进度（0..1）；无参时返回在场最高进度（兼容旧调用）。
func get_extraction_progress(player: Player = null) -> float:
	if player == null:
		var max_progress := 0.0
		for st in _extract_state.values():
			var duration: float = float(st.get("duration", 1.5))
			max_progress = maxf(max_progress, clampf(float(st.get("elapsed", 0.0)) / maxf(duration, 0.001), 0.0, 1.0))
		return max_progress
	var st: Dictionary = _extract_state.get(player.get_instance_id(), {})
	if st.is_empty():
		return 0.0
	var dur: float = float(st.get("duration", 1.5))
	return clampf(float(st.get("elapsed", 0.0)) / maxf(dur, 0.001), 0.0, 1.0)


## 取消指定玩家倒计时（默认取消全部）。兼容旧调用方/工具。
func cancel_extraction(reason: String = "manual", player: Player = null) -> void:
	if player != null:
		if _extract_state.erase(player.get_instance_id()):
			extraction_cancelled.emit(player, reason)
		return
	for key in _extract_state.keys():
		var st: Dictionary = _extract_state[key]
		_extract_state.erase(key)
		var p: Player = st.get("player")
		if p != null and is_instance_valid(p):
			extraction_cancelled.emit(p, reason)
	_update_visual_progress()


func _update_visual_progress() -> void:
	var max_progress := 0.0
	for st in _extract_state.values():
		var duration: float = float(st.get("duration", 1.5))
		max_progress = maxf(max_progress, clampf(float(st.get("elapsed", 0.0)) / maxf(duration, 0.001), 0.0, 1.0))
	_set_visual_progress(max_progress)


func _set_visual_progress(progress: float) -> void:
	var value := clampf(progress, 0.0, 1.0)
	if _rune_mat != null:
		_rune_mat.set_shader_parameter("emission_strength", RUNE_EMISSION_IDLE + value * RUNE_EMISSION_ACTIVE_BOOST)
	if _portal_core != null:
		var pulse := 1.0 + value * 0.35
		_portal_core.scale = Vector3(pulse, pulse, pulse)
	if _portal_light != null:
		_portal_light.light_energy = PORTAL_LIGHT_IDLE + value * PORTAL_LIGHT_ACTIVE_BOOST
