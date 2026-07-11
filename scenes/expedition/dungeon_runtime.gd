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
#   - 不管理 streaming（controller 已接管）
#   - 信号接线（extraction_requested.connect / pressure.pressure_changed.connect）属本模块范畴
#
# 本会话先建框架 + 接口声明，真迁移放下回合（保 procedural 旧路径不破，避免单回合高风险大改）。
class_name DungeonRuntime
extends Node

const EXPLORATION_PRESSURE_SCRIPT := preload("res://globals/dungeon/exploration_pressure.gd")

# 配置（由 ProceduralDungeon._ready 注入）
var layout: DungeonLayout = null
var build_result: DungeonBuildResult = null
var expedition_finished: bool = false
var _level: Node = null  # ProceduralDungeon 引用（转调其 spawn_player/HUD/pressure 旧路径，下回合真迁）

## 配置：注入 layout + build_result + level（ProceduralDungeon 引用，转调旧路径暂保）。
func configure(p_layout: DungeonLayout, p_build_result: DungeonBuildResult, p_level: Node = null) -> void:
	layout = p_layout
	build_result = p_build_result
	_level = p_level

## 启动 runtime：spawn player/enemies/items + mount HUD + setup pressure + connect extraction + music。
## D 步3 真迁移：本版转调 procedural 旧路径（通过 _level 引用），下回合把函数体真搬入本模块。
func start() -> void:
	if _level == null or not is_instance_valid(_level):
		return
	# spawn 序（余下转调 procedural 旧路径，下步真迁）
	var spawned_player = _level.spawn_player()
	# D 步5：spawn_enemies 已真迁入本模块（不转调 procedural）
	spawn_enemies(spawned_player)
	spawn_items()
	# D 步7：stabilize_lighting 已真迁入本模块（转调 procedural 工具 + streaming_controller）
	stabilize_lighting()
	# D 步10：mount_expedition_hud + setup_exploration_pressure 已真迁入本模块
	mount_expedition_hud()
	setup_exploration_pressure()
	# D 步4：extraction 信号接线已真迁入本模块（不转调 procedural）
	wire_extraction_portal_signal()
	if AudioManager:
		AudioManager.start_music()

func mount_expedition_hud() -> void:
	# D 步10 真迁：把 procedural._mount_expedition_hud 逻辑搬入本模块，
	# _expedition_hud/_combat_hud 挂 _level（保字段路径不破）。
	if _level == null or not is_instance_valid(_level):
		return
	var hud_scene = load("res://scenes/ui/expedition_hud.tscn")
	if not hud_scene:
		return
	var hud := hud_scene.instantiate() as ExpeditionHUD
	_level._expedition_hud = hud
	var layer = CanvasLayer.new()
	layer.name = "ExpeditionHUDLayer"
	layer.add_child(hud)
	_level.add_child(layer)
	if not _is_running_under_world():
		var game_ui = load("res://scenes/ui/ui.tscn")
		if game_ui:
			var ui_instance = game_ui.instantiate()
			_level.add_child(ui_instance)
		var combat_hud_scene = load("res://scenes/ui/combat_hud.tscn")
		if combat_hud_scene:
			_level._combat_hud = combat_hud_scene.instantiate() as CombatHUD
			_level.add_child(_level._combat_hud)

func _is_running_under_world() -> bool:
	# D 步10 真迁：把 procedural._is_running_under_world 逻辑搬入本模块
	if _level == null:
		return false
	var node: Node = _level.get_parent()
	while node != null:
		if node.has_method("transition_to_tavern") and node.has_method("transition_to_dungeon"):
			return true
		node = node.get_parent()
	return false

func setup_exploration_pressure() -> void:
	# D 步10 真迁：把 procedural._setup_exploration_pressure 逻辑搬入本模块，
	# 信号接本模块 on_pressure_changed/on_expedition_overtime（已真迁）。
	if _level == null or not is_instance_valid(_level):
		return
	_level._exploration_pressure = EXPLORATION_PRESSURE_SCRIPT.new() as ExplorationPressure
	_level._exploration_pressure.name = "ExplorationPressure"
	_level._exploration_pressure.pressure_changed.connect(on_pressure_changed)
	_level._exploration_pressure.expedition_overtime.connect(on_expedition_overtime)
	_level.add_child(_level._exploration_pressure)
	on_pressure_changed(_level._exploration_pressure.make_snapshot())

func stabilize_lighting() -> void:
	# D 步7 真迁：把 procedural._stabilize_dungeon_lighting 逻辑搬入本模块，
	# 4 工具（collect/is_player_vision/is_hint/configure）转调 procedural（保路径不破）。
	if _level == null or not is_instance_valid(_level):
		return
	var player_node: Node3D = GameState.current_player
	if player_node != null and is_instance_valid(player_node):
		if player_node.has_method("_setup_player_light"):
			player_node._setup_player_light()
	var local_lights: Array[Light3D] = []
	_level._collect_local_lights(_level, local_lights)
	for light in local_lights:
		if _level._is_player_vision_light(light):
			_level._configure_player_vision_light(light)
			continue
		if _level._is_hint_light(light):
			light.visible = false
			continue
		if light is OmniLight3D or light is SpotLight3D:
			light.visible = false
			var sc = _level.streaming_controller
			if sc != null and is_instance_valid(sc):
				sc.register_light(light)
	var sc2 = _level.streaming_controller
	if sc2 != null and is_instance_valid(sc2):
		sc2.update_streaming(true)

## 停止 runtime：handle extraction/overtime 收尾。
func stop() -> void:
	expedition_finished = true

# ── 接口框架（D 步2 真迁移放下回合，保 procedural 旧路径不破） ──
# 这些函数声明占位，让集成测试可验 DungeonRuntime 已具备 runtime 范畴的全套接口名。
# 真迁移时把 procedural 内对应函数体搬入这里 + 改 procedural 转调本模块。

func spawn_player() -> Node3D:
	return null  # TODO D 步2: 迁自 procedural.spawn_player

func spawn_enemies(spawned_player: Node3D = null) -> void:
	# D 步5 真迁：把 procedural._spawn_dungeon_enemies 逻辑搬入本模块，
	# 调 DungeonSpawner.spawn_enemies_from_layout 接 layout.enemy_spawn_specs，敌人挂 build_result.spawn_root。
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
	var spawned_enemies: Array = spawner.spawn_enemies_from_layout(layout, spawn_root, player_node)
	# streaming 注册转调 procedural.register_streamed_physics_node（它转调 controller，保路径）
	if _level != null and is_instance_valid(_level):
		for enemy in spawned_enemies:
			_level.register_streamed_physics_node(enemy)

func spawn_items() -> void:
	# D 步5 真迁：把 procedural._spawn_dungeon_items 逻辑搬入本模块，
	# 调 ItemSpawner.spawn_items_from_layout 接 layout.item_spawn_specs，物挂 build_result.spawn_root。
	if layout == null or layout.is_empty() or build_result == null:
		return
	var spawner: Node = Service.item_spawner() if Service != null else null
	if spawner == null:
		push_warning("[DungeonRuntime] ItemSpawner autoload not found, skipping item placement")
		return
	var spawn_root: Node = build_result.spawn_root if build_result.spawn_root != null else _level
	spawner.spawn_items_from_layout(layout, spawn_root)
	if _level != null and is_instance_valid(_level):
		_level._build_batched_decor_multi_meshes()

func wire_extraction_portal_signal() -> void:
	# D 步4 真迁：把 procedural._wire_extraction_portal_signal 逻辑搬入本模块，
	# 信号接 runtime.on_extraction_requested（不转调 procedural，真接管）。
	if build_result == null or build_result.interaction_root == null:
		return
	for child in build_result.interaction_root.get_children():
		if String(child.get_meta("topdown_kind", "")) == "extraction" and child.has_signal("extraction_requested"):
			child.extraction_requested.connect(on_extraction_requested)
			break  # 唯一 ExtractionPortal

func finish_expedition(player: Node, voluntary: bool) -> void:
	# D 步8 真迁：把 procedural._finish_expedition 逻辑搬入本模块，
	# _exploration_pressure 转调 _level（保路径不破），TavernManager autoload 直调。
	if expedition_finished:
		return
	expedition_finished = true
	if player != null and is_instance_valid(player):
		_settle_extraction_loot(player)
	if TavernManager:
		var pressure = _level._exploration_pressure if _level != null and is_instance_valid(_level) else null
		var result: Dictionary = pressure.build_extraction_result(voluntary) if pressure != null else {}
		TavernManager.extract_to_tavern(result)

func _settle_extraction_loot(player: Node) -> void:
	# D 步8 真迁：把 procedural._settle_extraction_loot 逻辑搬入本模块
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
	# D 步6 真迁：把 procedural._on_extraction_requested 逻辑搬入本模块
	print("[DungeonRuntime] Extraction triggered by player!")
	finish_expedition(player, true)

func on_expedition_overtime(_snapshot: Dictionary) -> void:
	# D 步6 真迁：把 procedural._on_expedition_overtime 逻辑搬入本模块
	var player_node := GameState.current_player as Player
	finish_expedition(player_node, false)

func on_pressure_changed(snapshot: Dictionary) -> void:
	# D 步9 真迁：把 procedural._on_pressure_changed 逻辑搬入本模块
	if _level == null or not is_instance_valid(_level):
		return
	if _level._expedition_hud != null and is_instance_valid(_level._expedition_hud):
		_level._expedition_hud.update_pressure(snapshot)
	var combat_hud := _get_combat_hud()
	if combat_hud != null and is_instance_valid(combat_hud):
		combat_hud.update_pressure(snapshot)
	apply_player_vision_pressure(float(snapshot.get("vision_range_multiplier", 1.0)))
	apply_environment_activity(float(snapshot.get("environment_activity_multiplier", 1.0)))
	apply_monster_hunt_pressure(bool(snapshot.get("force_monster_hunt", false)))

func _get_combat_hud() -> CombatHUD:
	# D 步9 真迁：把 procedural._get_combat_hud 逻辑搬入本模块
	if _level == null or not is_instance_valid(_level):
		return null
	if _level._combat_hud != null and is_instance_valid(_level._combat_hud):
		return _level._combat_hud
	var node: Node = _level
	while node != null:
		var found := node.get_node_or_null("CombatHUD") as CombatHUD
		if found != null:
			_level._combat_hud = found
			return _level._combat_hud
		node = node.get_parent()
	return null

func on_door_pressure_action(action: String) -> void:
	# D 步9 真迁：把 procedural._on_door_pressure_action 逻辑搬入本模块
	if _level == null or not is_instance_valid(_level):
		return
	if _level._exploration_pressure == null:
		return
	_level._exploration_pressure.record_door_action(action)

func apply_player_vision_pressure(multiplier: float) -> void:
	# D 步9 真迁：把 procedural._apply_player_vision_pressure 逻辑搬入本模块
	var player_node := GameState.current_player
	if player_node == null or not is_instance_valid(player_node):
		return
	var light := player_node.get_node_or_null(Player.PLAYER_VISION_LIGHT_NAME) as OmniLight3D
	if light == null:
		return
	var light_multiplier := clampf(multiplier, 0.0, 1.0)
	light.visible = light_multiplier > 0.0
	light.light_energy = _level.PLAYER_VISION_BASE_ENERGY * light_multiplier
	light.omni_range = _level.PLAYER_VISION_BASE_RANGE * light_multiplier

func apply_environment_activity(multiplier: float) -> void:
	# D 步9 真迁：把 procedural._apply_environment_activity 逻辑搬入本模块
	for node in get_tree().get_nodes_in_group("enemies"):
		if node == null or not is_instance_valid(node):
			continue
		node.set_meta("environment_activity_mult", clampf(multiplier, 1.0, 1.75))

func apply_monster_hunt_pressure(force_hunt: bool) -> void:
	# D 步9 真迁：把 procedural._apply_monster_hunt_pressure 逻辑搬入本模块
	var player_node := GameState.current_player as Player
	if player_node == null or not is_instance_valid(player_node):
		return
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy == null or not is_instance_valid(enemy):
			continue
		enemy.set_meta("dark_erosion_hunt", force_hunt)
		if force_hunt:
			enemy.player = player_node
