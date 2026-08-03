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
const DungeonSpawnFootprint := preload("res://scenes/expedition/dungeon_spawn_footprint.gd")
const VOXEL_LIGHTING := preload("res://globals/visual/voxel_lighting_adapter.gd")

# 配置（由 ProceduralDungeon._ready 注入）
var layout: DungeonLayout = null
var build_result: DungeonBuildResult = null
var expedition_finished: bool = false
var _downstairs_transition_started: bool = false

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
var _enemy_spawn_active: bool = false
var _enemy_spawn_generation: int = 0
var _enemy_spawn_timer: SceneTreeTimer = null
var _force_monster_hunt := false

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
	_downstairs_transition_started = false
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
	wire_downstairs_signal()
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
	var floor_label := _get_current_floor_label()
	hud.set_floor_label(floor_label)
	hud.show_floor_arrival(_get_current_zone_name(), floor_label)
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
	var player_node: Node3D = GameState.resolve_player_node(0) as Node3D
	if player_node != null and is_instance_valid(player_node):
		if player_node.has_method("_setup_player_light"):
			player_node._setup_player_light()
	var scene_lights: Array[Light3D] = []
	LIGHTING_HELPER.collect_scene_lights(_level, scene_lights)
	for light in scene_lights:
		VOXEL_LIGHTING.disable_light_specular(light)
	var local_lights: Array[Light3D] = []
	LIGHTING_HELPER.collect_local_lights(_level, local_lights)
	var base_energy: float = _rendering_cfg.player_vision_base_energy
	var base_range: float = _rendering_cfg.player_vision_base_range
	for light in local_lights:
		if LIGHTING_HELPER.is_player_vision_light(light, Player.PLAYER_VISION_LIGHT_NAME):
			LIGHTING_HELPER.configure_player_vision_light(
				light,
				base_energy,
				base_range,
				_rendering_cfg.player_vision_color,
				_rendering_cfg.player_vision_attenuation,
			)
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
	# SceneTreeTimer 没有可靠的取消 API；generation token 使已排队的
	# callback 失效，并清掉它可能持有的 root/player 引用。
	_enemy_spawn_active = false
	_enemy_spawn_generation += 1
	_enemy_spawn_timer = null
	_enemy_spawn_plan.clear()
	_enemy_spawn_root = null
	_enemy_spawn_player = null
	_enemy_spawn_index = 0
	_force_monster_hunt = false
	if _streaming_controller != null and is_instance_valid(_streaming_controller) \
			and _streaming_controller.has_method("clear"):
		_streaming_controller.clear()

func _exit_tree() -> void:
	stop()

func spawn_player() -> Node3D:
	return null  # 仍由 level.spawn_player 提供；接口保留供契约测试

func spawn_enemies(spawned_player: Node3D = null) -> void:
	if expedition_finished or layout == null or layout.is_empty() or build_result == null:
		return
	var spawner: Node = Service.dungeon_spawner() if Service != null else null
	if spawner == null:
		push_warning("[DungeonRuntime] DungeonSpawner autoload not found, no enemies spawned")
		return
	var player_node: Node3D = spawned_player
	if player_node == null:
		player_node = GameState.resolve_player_node(0)
		if player_node == null:
			push_warning("[DungeonRuntime] Player not spawned, skip enemy generation")
			return
	var spawn_root: Node = build_result.spawn_root if build_result.spawn_root != null else _level
	# 分帧实例化：先取生成计划（不实例化），再按帧批量生成，避免进场单帧卡顿。
	_enemy_spawn_plan = spawner.spawn_enemies_from_layout(layout, spawn_root, player_node, true)
	_snap_enemy_spawn_plan_to_navigation()
	_enemy_spawn_plan = _reserve_enemy_spawn_plan_footprints(_enemy_spawn_plan)
	_enemy_spawn_root = spawn_root
	_enemy_spawn_player = player_node
	_enemy_spawn_index = 0
	_enemy_spawn_active = true
	_enemy_spawn_generation += 1
	if _enemy_spawn_plan.is_empty():
		_enemy_spawn_active = false
		return
	# 无场景树（如纯单测 .new()）则同步实例化，保持测试可直接断言数量。
	if get_tree() == null:
		_spawn_enemy_batch(_enemy_spawn_plan.size())
		return
	_pump_enemy_spawns()


## 将生成计划投影到已烘焙导航面，避免敌人出生在装饰物顶部、碰撞体内部或导航面边界外。
## 只接受同一格附近的投影，防止导航异常时把敌人跨房间移动；没有可用导航图则保留原计划。
func _snap_enemy_spawn_plan_to_navigation() -> void:
	if _enemy_spawn_plan.is_empty() or _level == null or not is_instance_valid(_level):
		return
	var map := _get_spawn_navigation_map()
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) <= 0:
		return
	var max_horizontal_snap := maxf(layout.tile_size * 1.5, 1.0) if layout != null else 4.5
	for index in range(_enemy_spawn_plan.size()):
		var descriptor: Dictionary = _enemy_spawn_plan[index]
		var original: Variant = descriptor.get("pos", Vector3.ZERO)
		if not original is Vector3:
			continue
		var requested: Vector3 = original
		var closest := NavigationServer3D.map_get_closest_point(
			map, Vector3(requested.x, 0.5, requested.z))
		if not _is_finite_vector(closest):
			continue
		var horizontal_delta := Vector2(closest.x - requested.x, closest.z - requested.z).length()
		if not is_finite(horizontal_delta) or horizontal_delta > max_horizontal_snap:
			continue
		# 导航面 y 仅用于烘焙层高度；角色根节点仍以脚底 y=0.5 生成并自然落地。
		descriptor["pos"] = Vector3(closest.x, 0.5, closest.z)
		_enemy_spawn_plan[index] = descriptor


func _reserve_enemy_spawn_plan_footprints(plan: Array) -> Array:
	if build_result == null:
		return plan
	var accepted: Array = []
	for descriptor in plan:
		var position: Variant = descriptor.get("pos", null)
		if not position is Vector3:
			continue
		var enemy_type := String(descriptor.get("enemy_type", ""))
		var half_extents := DungeonSpawnFootprint.half_extents_for("enemy", enemy_type)
		if not DungeonSpawnFootprint.can_place(build_result.spawn_footprints, position, half_extents):
			push_warning("[DungeonRuntime] skipped overlapping enemy placement: %s" % enemy_type)
			continue
		DungeonSpawnFootprint.register(build_result.spawn_footprints, position, half_extents,
				"enemy:%s" % enemy_type)
		accepted.append(descriptor)
	return accepted


func _get_spawn_navigation_map() -> RID:
	if _level == null or not is_instance_valid(_level):
		return RID()
	for node in _level.find_children("*", "NavigationRegion3D", true, false):
		var region := node as NavigationRegion3D
		if region == null:
			continue
		var map := region.get_navigation_map()
		if map.is_valid() and NavigationServer3D.map_get_iteration_id(map) > 0:
			return map
	return RID()


func _is_finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


## 同步实例化最多 count 个待生成敌人，并注册到 streaming。
func _spawn_enemy_batch(count: int) -> void:
	var spawner: Node = Service.dungeon_spawner() if Service != null else null
	if not _enemy_spawn_active or spawner == null or _enemy_spawn_root == null \
			or not is_instance_valid(_enemy_spawn_root):
		return
	var end := mini(_enemy_spawn_index + count, _enemy_spawn_plan.size())
	for i in range(_enemy_spawn_index, end):
		var desc: Dictionary = _enemy_spawn_plan[i]
		var enemy: Node = spawner.instantiate_enemy_descriptor(desc, _enemy_spawn_root, _enemy_spawn_player, layout)
		if enemy != null:
			var runtime_enemy := enemy as Enemy
			if _force_monster_hunt and runtime_enemy != null:
				runtime_enemy.set_dark_erosion_hunt(true)
				runtime_enemy.player = _enemy_spawn_player as Player
			_register_streamed_physics(enemy)
	_enemy_spawn_index = end
	if _enemy_spawn_index >= _enemy_spawn_plan.size():
		_enemy_spawn_active = false


## 按帧推进实例化：每帧生成一批，跨帧完成全图敌人生成。
func _pump_enemy_spawns(generation: int = -1) -> void:
	if generation >= 0 and generation != _enemy_spawn_generation:
		return
	if not _enemy_spawn_active or not is_inside_tree():
		return
	if _enemy_spawn_index >= _enemy_spawn_plan.size():
		_enemy_spawn_active = false
		return
	_spawn_enemy_batch(ENEMY_SPAWN_BATCH_PER_FRAME)
	if _enemy_spawn_active and _enemy_spawn_index < _enemy_spawn_plan.size():
		var next_generation := _enemy_spawn_generation
		_enemy_spawn_timer = get_tree().create_timer(0.0)
		_enemy_spawn_timer.timeout.connect(_pump_enemy_spawns.bind(next_generation), CONNECT_ONE_SHOT)

func spawn_items() -> void:
	if layout == null or layout.is_empty() or build_result == null:
		return
	var spawner: Node = Service.item_spawner() if Service != null else null
	if spawner == null:
		push_warning("[DungeonRuntime] ItemSpawner autoload not found, skipping item placement")
		return
	var spawn_root: Node = build_result.spawn_root if build_result.spawn_root != null else _level
	spawner.spawn_items_from_layout(layout, spawn_root, null, build_result.spawn_footprints)
	# decor batch 已由 DungeonSceneBuilder.build 在 build 末尾完成

func wire_extraction_portal_signal() -> void:
	if build_result == null or build_result.interaction_root == null:
		return
	for child in build_result.interaction_root.get_children():
		if String(child.get_meta("topdown_kind", "")) == "extraction" and child.has_signal("extraction_requested"):
			child.extraction_requested.connect(on_extraction_requested)
			if child.has_signal("extraction_started"):
				child.extraction_started.connect(on_extraction_started)
			if child.has_signal("extraction_progress"):
				child.extraction_progress.connect(on_extraction_progress)
			if child.has_signal("extraction_cancelled"):
				child.extraction_cancelled.connect(on_extraction_cancelled)
			break

## 连接当前地牢的向下楼梯。楼梯只负责进入下一层，不走撤离结算。
func wire_downstairs_signal() -> void:
	if build_result == null or build_result.interaction_root == null:
		return
	for child in build_result.interaction_root.get_children():
		if String(child.get_meta("topdown_kind", "")) != "stairs":
			continue
		var area := child.get_node_or_null("DownstairsArea") as Area3D
		if area == null:
			continue
		area.collision_layer = PhysicsSetup.LAYER_TRIGGER
		area.collision_mask = PhysicsSetup.LAYER_PLAYER
		area.monitoring = true
		area.monitorable = true
		if not area.body_entered.is_connected(on_downstairs_entered):
			area.body_entered.connect(on_downstairs_entered)
		break

func on_downstairs_entered(body: Node3D) -> void:
	if not body is Player or expedition_finished or _downstairs_transition_started:
		return
	_downstairs_transition_started = true
	print("[DungeonRuntime] Downstairs triggered by player")
	var world := _find_world_controller()
	if world != null and world.has_method("transition_to_next_floor"):
		world.transition_to_next_floor()
		return
	if GameState != null and GameState.has_method("advance_dungeon_floor"):
		GameState.advance_dungeon_floor()
	if world != null and world.has_method("transition_to_dungeon"):
		world.transition_to_dungeon()
	elif GameEvents:
		GameEvents.level_restarted.emit()

func _find_world_controller() -> Node:
	var node: Node = _level
	while node != null:
		if node.has_method("transition_to_next_floor") or node.has_method("transition_to_dungeon"):
			return node
		node = node.get_parent()
	return null

func _get_current_floor_label() -> String:
	if GameState != null and GameState.has_method("get_dungeon_floor_label"):
		return String(GameState.get_dungeon_floor_label())
	return "L1"

func _get_current_zone_name() -> String:
	var zone := 0
	if layout != null:
		zone = layout.zone
	var zone_manager := Service.zone_manager() if Service != null else null
	if zone_manager != null and zone_manager.has_method("get_zone_name"):
		return String(zone_manager.get_zone_name(zone))
	return "未知区域"

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
	if expedition_hud != null and is_instance_valid(expedition_hud):
		expedition_hud.complete_extraction()
	finish_expedition(player, true)


func on_extraction_started(_player: Node, duration: float) -> void:
	if expedition_hud != null and is_instance_valid(expedition_hud):
		expedition_hud.begin_extraction(duration)
	# 拉闸声会惊动当前地牢中的怪物，但不会像 100 暗蚀那样永久打开所有门。
	apply_monster_hunt_pressure(true, false)


func on_extraction_progress(_player: Node, progress: float, remaining: float) -> void:
	if expedition_hud != null and is_instance_valid(expedition_hud):
		expedition_hud.update_extraction_progress(progress, remaining)


func on_extraction_cancelled(_player: Node, reason: String) -> void:
	if expedition_hud != null and is_instance_valid(expedition_hud):
		expedition_hud.cancel_extraction(reason)
	var pressure_hunt := false
	if exploration_pressure != null and is_instance_valid(exploration_pressure):
		pressure_hunt = exploration_pressure.should_force_monster_hunt()
	apply_monster_hunt_pressure(pressure_hunt, false)

func on_expedition_overtime(_snapshot: Dictionary) -> void:
	var player_node := _get_valid_current_player()
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
	var player_node: Node = GameState.resolve_player_node(0)
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

func apply_monster_hunt_pressure(force_hunt: bool, open_doors: bool = true) -> void:
	_force_monster_hunt = force_hunt
	if force_hunt and open_doors:
		_open_doors_for_monster_hunt()
	var player_node := _get_valid_current_player()
	if player_node == null or not is_instance_valid(player_node):
		return
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy == null or not is_instance_valid(enemy):
			continue
		if enemy.has_method("set_dark_erosion_hunt"):
			enemy.set_dark_erosion_hunt(force_hunt)
		else:
			enemy.set_meta("dark_erosion_hunt", force_hunt)
		if force_hunt:
			enemy.player = player_node
	if _streaming_controller != null and is_instance_valid(_streaming_controller) \
			and _streaming_controller.has_method("update_streaming"):
		# 压力变化不一定伴随玩家跨 chunk；强制刷新才能立即唤醒/休眠全图敌人。
		_streaming_controller.update_streaming(true)

func _open_doors_for_monster_hunt() -> void:
	if build_result == null or build_result.doors_root == null:
		return
	for node in build_result.doors_root.get_children():
		if node != null and is_instance_valid(node) and node.has_method("open_for_monster_hunt"):
			node.open_for_monster_hunt()

func _get_valid_current_player() -> Player:
	var candidate: Variant = GameState.resolve_player_node(0)
	if candidate == null or not is_instance_valid(candidate):
		return null
	return candidate as Player

func _register_streamed_physics(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if _streaming_controller != null and is_instance_valid(_streaming_controller) \
			and _streaming_controller.has_method("register_physics_node"):
		_streaming_controller.register_physics_node(node)
		return
	if _level != null and is_instance_valid(_level) and _level.has_method("register_streamed_physics_node"):
		_level.register_streamed_physics_node(node)
