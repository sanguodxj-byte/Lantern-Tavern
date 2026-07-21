## DungeonRuntime — 地牢探险运行时模块（评审建议 D 阶段）。
#
# 职责：接管 ProceduralDungeon 的运行时行为——
#   spawn player / spawn enemies / spawn items
#   mount HUD / setup exploration pressure / connect extraction
#   handle overtime / handle extraction
#
# 不负责：生成地图 / 创建墙体 / 计算危险地形 / 管理 chunk / 读取 JSON / 管理酒馆仓库
#
# 严格约束：
#   - 不重新规划布局（layout 已含 spawn specs）
#   - 不创建地形节点（builder 已产 build_result）
#   - 不维护 streaming registry（controller 已接管；可协调一次 update）
#   - 信号接线（extraction_requested / pressure_changed）属本模块范畴
class_name DungeonRuntime
extends Node

const EXPLORATION_PRESSURE_SCRIPT := preload("res://globals/dungeon/exploration_pressure.gd")
const LIGHTING_HELPER := preload("res://scenes/expedition/dungeon_lighting_helper.gd")
const DungeonRenderingConfig := preload("res://scenes/expedition/dungeon_rendering_config.gd")

# 配置（由 ProceduralDungeon._ready 注入）
var layout: DungeonLayout = null
var build_result: DungeonBuildResult = null
var expedition_finished: bool = false

# 宿主仅提供：spawn_player / streaming_controller / decor batch 收尾
var _level: Node = null
var _streaming_controller: Node = null
var _rendering_cfg: DungeonRenderingConfig = DungeonRenderingConfig.default()

# 是否生成敌人/掉落物人口。生产默认 true。
# 供无头集成测试关闭：headless GL Compatibility 下反复实例化 ~30 具蒙皮 rig 敌人会累积
# GPU 资源并触发原生崩溃（signal 11，见 enemy_dying_defer_test 记录，真机正常）。
# 只验证地形/门/光照/材质的全场景测试无需敌人，可置 false 规避该引擎限制。
var spawn_population_enabled: bool = true

# 敌人分帧实例化状态：先取生成计划，再按帧批量实例化，削平进场单帧卡顿与显存峰值尖峰。
const ENEMY_SPAWN_BATCH_PER_FRAME := 4
var _enemy_spawn_plan: Array = []
var _enemy_spawn_root: Node = null
var _enemy_spawn_player: Node = null
var _enemy_spawn_index: int = 0

# Runtime 自有状态（不再写回 _level._private_field）
var expedition_hud: ExpeditionHUD = null
var combat_hud: CombatHUD = null
var exploration_pressure: ExplorationPressure = null

## 配置：注入 layout + build_result + level + streaming_controller + rendering_cfg。
## 显式注入避反向读 _level.streaming_controller/_rendering_cfg（消除浅 Module 反向依赖）。
func configure(p_layout: DungeonLayout, p_build_result: DungeonBuildResult, p_level: Node = null,
		p_streaming_controller: Node = null, p_rendering_cfg: DungeonRenderingConfig = null,
		p_spawn_population: bool = true) -> void:
	layout = p_layout
	build_result = p_build_result
	_level = p_level
	_streaming_controller = p_streaming_controller
	spawn_population_enabled = p_spawn_population
	if p_rendering_cfg != null:
		_rendering_cfg = p_rendering_cfg

## 启动 runtime：spawn player/enemies/items + mount HUD + setup pressure + connect extraction + music。
func start() -> void:
	if _level == null or not is_instance_valid(_level):
		return
	var spawned_player = null
	if _level.has_method("spawn_player"):
		spawned_player = _level.spawn_player()
	# 关键接线：把玩家引用交给 streaming controller。否则其 _player_position() 恒用
	# 地图角落 fallback 坐标决定激活哪些 chunk，玩家周围的 terrain/wall/light chunk
	# 永不激活 → 地牢全黑、无墙体无光源。
	if _streaming_controller != null and is_instance_valid(_streaming_controller) \
			and _streaming_controller.has_method("set_player"):
		_streaming_controller.set_player(spawned_player)
	if spawn_population_enabled:
		spawn_enemies(spawned_player)
		spawn_items()
	stabilize_lighting()
	mount_expedition_hud()
	setup_exploration_pressure()
	wire_extraction_portal_signal()
	if AudioManager:
		AudioManager.start_music()

func mount_expedition_hud() -> void:
	if _level == null or not is_instance_valid(_level):
		return
	var hud_scene = load("res://scenes/ui/expedition_hud.tscn")
	if not hud_scene:
		return
	var hud := hud_scene.instantiate() as ExpeditionHUD
	expedition_hud = hud
	var layer = CanvasLayer.new()
	layer.name = "ExpeditionHUDLayer"
	layer.add_child(hud)
	_level.add_child(layer)
	# 无头环境（gdUnit/CI 或专用服务器）没有可渲染的显示上下文：整套客户端 UI
	# （ui.tscn → pause_menu.tscn 的 blur_overlay 后处理 shader）在 GL Compatibility 无头渲染下
	# 反复创建 shader/viewport，跨多次全场景实例化累积 GPU 资源，最终触发原生崩溃（signal 11），
	# 使整个测试套件在中途挂起。无头下本就无需玩家 UI，跳过这层重 UI 的挂载。
	if _is_running_under_world() or DisplayServer.get_name() == "headless":
		return
	var game_ui = load("res://scenes/ui/ui.tscn")
	if game_ui:
		var ui_instance = game_ui.instantiate()
		_level.add_child(ui_instance)
	var combat_hud_scene = load("res://scenes/ui/combat_hud.tscn")
	if combat_hud_scene:
		combat_hud = combat_hud_scene.instantiate() as CombatHUD
		_level.add_child(combat_hud)

func _is_running_under_world() -> bool:
	if _level == null:
		return false
	var node: Node = _level.get_parent()
	while node != null:
		if node.has_method("transition_to_tavern") and node.has_method("transition_to_dungeon"):
			return true
		node = node.get_parent()
	return false

func setup_exploration_pressure() -> void:
	if _level == null or not is_instance_valid(_level):
		return
	exploration_pressure = EXPLORATION_PRESSURE_SCRIPT.new() as ExplorationPressure
	exploration_pressure.name = "ExplorationPressure"
	exploration_pressure.pressure_changed.connect(on_pressure_changed)
	exploration_pressure.expedition_overtime.connect(on_expedition_overtime)
	_level.add_child(exploration_pressure)
	on_pressure_changed(exploration_pressure.make_snapshot())

func stabilize_lighting() -> void:
	if _level == null or not is_instance_valid(_level):
		return
	var player_node: Node3D = GameState.current_player
	if player_node != null and is_instance_valid(player_node):
		if player_node.has_method("_setup_player_light"):
			player_node._setup_player_light()
	var local_lights: Array[Light3D] = []
	LIGHTING_HELPER.collect_local_lights(_level, local_lights)
	var base_energy: float = _rendering_cfg.player_vision_base_energy
	var base_range: float = _rendering_cfg.player_vision_base_range
	for light in local_lights:
		if LIGHTING_HELPER.is_player_vision_light(light, Player.PLAYER_VISION_LIGHT_NAME):
			LIGHTING_HELPER.configure_player_vision_light(light, base_energy, base_range)
			continue
		if LIGHTING_HELPER.is_hint_light(light, _level):
			light.visible = false
			continue
		if light is OmniLight3D or light is SpotLight3D:
			light.visible = false
			if _streaming_controller != null and is_instance_valid(_streaming_controller):
				if _streaming_controller.has_method("register_light"):
					_streaming_controller.register_light(light)
	if _streaming_controller != null and is_instance_valid(_streaming_controller):
		if _streaming_controller.has_method("update_streaming"):
			_streaming_controller.update_streaming(true)

## 停止 runtime：handle extraction/overtime 收尾。
func stop() -> void:
	expedition_finished = true

func spawn_player() -> Node3D:
	return null  # 仍由 level.spawn_player 提供；接口保留供契约测试

func spawn_enemies(spawned_player: Node3D = null) -> void:
	if layout == null or layout.is_empty() or build_result == null:
		return
	var spawner: Node = Service.dungeon_spawner() if Service != null else null
	if spawner == null:
		push_warning("[DungeonRuntime] DungeonSpawner autoload not found, no enemies spawned")
		return
	var player_node: Node3D = spawned_player
	if player_node == null:
		player_node = GameState.current_player
		if player_node == null:
			push_warning("[DungeonRuntime] Player not spawned, skip enemy generation")
			return
	var spawn_root: Node = build_result.spawn_root if build_result.spawn_root != null else _level
	# 分帧实例化：先取生成计划（不实例化），再按帧批量生成，避免进场单帧卡顿。
	_enemy_spawn_plan = spawner.spawn_enemies_from_layout(layout, spawn_root, player_node, true)
	_enemy_spawn_root = spawn_root
	_enemy_spawn_player = player_node
	_enemy_spawn_index = 0
	if _enemy_spawn_plan.is_empty():
		return
	# 无场景树（如纯单测 .new()）则同步实例化，保持测试可直接断言数量。
	if get_tree() == null:
		_spawn_enemy_batch(_enemy_spawn_plan.size())
		return
	_pump_enemy_spawns()


## 同步实例化最多 count 个待生成敌人，并注册到 streaming。
func _spawn_enemy_batch(count: int) -> void:
	var spawner: Node = Service.dungeon_spawner() if Service != null else null
	if spawner == null or _enemy_spawn_root == null or not is_instance_valid(_enemy_spawn_root):
		return
	var end := mini(_enemy_spawn_index + count, _enemy_spawn_plan.size())
	for i in range(_enemy_spawn_index, end):
		var desc: Dictionary = _enemy_spawn_plan[i]
		var enemy: Node = spawner.instantiate_enemy_descriptor(desc, _enemy_spawn_root, _enemy_spawn_player, layout)
		if enemy != null:
			_register_streamed_physics(enemy)
	_enemy_spawn_index = end


## 按帧推进实例化：每帧生成一批，跨帧完成全图敌人生成。
func _pump_enemy_spawns() -> void:
	if _enemy_spawn_index >= _enemy_spawn_plan.size():
		return
	_spawn_enemy_batch(ENEMY_SPAWN_BATCH_PER_FRAME)
	if _enemy_spawn_index < _enemy_spawn_plan.size():
		if is_instance_valid(get_tree()):
			get_tree().create_timer(0.0).timeout.connect(_pump_enemy_spawns)

func spawn_items() -> void:
	if layout == null or layout.is_empty() or build_result == null:
		return
	var spawner: Node = Service.item_spawner() if Service != null else null
	if spawner == null:
		push_warning("[DungeonRuntime] ItemSpawner autoload not found, skipping item placement")
		return
	var spawn_root: Node = build_result.spawn_root if build_result.spawn_root != null else _level
	spawner.spawn_items_from_layout(layout, spawn_root)
	# decor batch 已由 DungeonSceneBuilder.build 在 build 末尾完成

func wire_extraction_portal_signal() -> void:
	if build_result == null or build_result.interaction_root == null:
		return
	for child in build_result.interaction_root.get_children():
		if String(child.get_meta("topdown_kind", "")) == "extraction" and child.has_signal("extraction_requested"):
			child.extraction_requested.connect(on_extraction_requested)
			break

func finish_expedition(player: Node, voluntary: bool) -> void:
	if expedition_finished:
		return
	expedition_finished = true
	if player != null and is_instance_valid(player):
		_settle_extraction_loot(player)
	if TavernManager != null and is_instance_valid(TavernManager) and TavernManager.has_method("extract_to_tavern"):
		var result: Dictionary = {}
		if exploration_pressure != null and is_instance_valid(exploration_pressure):
			result = exploration_pressure.build_extraction_result(voluntary)
		TavernManager.extract_to_tavern(result)

func _settle_extraction_loot(player: Node) -> void:
	var tm: Node = Service.tavern_manager() if Service != null else null
	if tm == null:
		return
	var carried_materials: int = GameState.get_carried_materials()
	var carried_weapons: int = GameState.get_carried_weapons()
	var carried_shields: int = GameState.get_carried_shields()
	print("[DungeonRuntime] Extraction loot: %d materials, %d weapons, %d shields" % [carried_materials, carried_weapons, carried_shields])
	if tm.has_method("record_expedition_loot"):
		tm.record_expedition_loot(carried_materials, carried_weapons, carried_shields)

func on_extraction_requested(player: Node) -> void:
	print("[DungeonRuntime] Extraction triggered by player!")
	finish_expedition(player, true)

func on_expedition_overtime(_snapshot: Dictionary) -> void:
	var player_node: Player = GameState.current_player as Player
	finish_expedition(player_node, false)

func on_pressure_changed(snapshot: Dictionary) -> void:
	if expedition_hud != null and is_instance_valid(expedition_hud):
		expedition_hud.update_pressure(snapshot)
	var hud := _get_combat_hud()
	if hud != null and is_instance_valid(hud):
		hud.update_pressure(snapshot)
	apply_player_vision_pressure(float(snapshot.get("vision_range_multiplier", 1.0)))
	apply_environment_activity(float(snapshot.get("environment_activity_multiplier", 1.0)))
	apply_monster_hunt_pressure(bool(snapshot.get("force_monster_hunt", false)))

func _get_combat_hud() -> CombatHUD:
	if combat_hud != null and is_instance_valid(combat_hud):
		return combat_hud
	if _level == null or not is_instance_valid(_level):
		return null
	var node: Node = _level
	while node != null:
		var found := node.get_node_or_null("CombatHUD") as CombatHUD
		if found != null:
			combat_hud = found
			return combat_hud
		node = node.get_parent()
	return null

func on_door_pressure_action(action: String) -> void:
	if exploration_pressure == null:
		return
	exploration_pressure.record_door_action(action)

func apply_player_vision_pressure(multiplier: float) -> void:
	var player_node: Node = GameState.current_player
	if player_node == null or not is_instance_valid(player_node):
		return
	var light := player_node.get_node_or_null(Player.PLAYER_VISION_LIGHT_NAME) as OmniLight3D
	if light == null:
		return
	var light_multiplier := clampf(multiplier, 0.0, 1.0)
	light.visible = light_multiplier > 0.0
	light.light_energy = _rendering_cfg.player_vision_base_energy * light_multiplier
	light.omni_range = _rendering_cfg.player_vision_base_range * light_multiplier

func apply_environment_activity(multiplier: float) -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		if node == null or not is_instance_valid(node):
			continue
		node.set_meta("environment_activity_mult", clampf(multiplier, 1.0, 1.75))

func apply_monster_hunt_pressure(force_hunt: bool) -> void:
	var player_node: Player = GameState.current_player as Player
	if player_node == null or not is_instance_valid(player_node):
		return
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy == null or not is_instance_valid(enemy):
			continue
		enemy.set_meta("dark_erosion_hunt", force_hunt)
		if force_hunt:
			enemy.player = player_node

func _register_streamed_physics(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if _streaming_controller != null and is_instance_valid(_streaming_controller) \
			and _streaming_controller.has_method("register_physics_node"):
		_streaming_controller.register_physics_node(node)
		return
	if _level != null and is_instance_valid(_level) and _level.has_method("register_streamed_physics_node"):
		_level.register_streamed_physics_node(node)
