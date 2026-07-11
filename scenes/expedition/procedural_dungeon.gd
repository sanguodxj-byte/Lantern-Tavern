extends BaseLevel
class_name ProceduralDungeon

const PILLAR_PREFAB := preload("res://scenes/props/structures/pillar.tscn")
const CRATE_PREFAB := preload("res://scenes/props/crates/small_crate.tscn")
const BARREL_PREFAB := preload("res://scenes/props/barrel/barrel.tscn")
const TORCH_PREFAB := preload("res://scenes/props/torch/torch.tscn")
const CHEST_PREFAB := preload("res://scenes/props/chest/chest.tscn")
const BOSS_CHEST_PREFAB := preload("res://scenes/props/chest/boss_chest.tscn")
const PICKABLE_ITEM_PREFAB := preload("res://scenes/equipment/pickable_item.tscn")
const RUBBLE_PREFAB := preload("res://scenes/props/decor/ruble.tscn")
const BONES_PREFAB := preload("res://scenes/props/decor/bones.tscn")
const SPIKES_TRAP_PREFAB := preload("res://scenes/traps/spikes_trap.tscn")
const FLAME_VENT_TRAP_PREFAB := preload("res://scenes/traps/flame_vent_trap.tscn")
const ACID_TRAP_PATH := "res://scenes/traps/acid_trap.tscn"
const EXTRACTION_PORTAL_PREFAB := preload("res://scenes/expedition/extraction_portal.tscn")
const ISAAC_ROOM_GENERATOR := preload("res://scenes/expedition/isaac_room_dungeon_generator.gd")
const DUNGEON_DOOR_SCRIPT := preload("res://scenes/expedition/dungeon_door.gd")
const EXPLORATION_PRESSURE_SCRIPT := preload("res://globals/dungeon/exploration_pressure.gd")
const SCENE_OBJECT_SCRIPT := preload("res://scenes/props/scene_object.gd")
const SCENE_OBJECT_LAYER := 64
const Service := preload("res://globals/core/service.gd")
# 阶段 9 接线：新生产链模块
const DungeonGenerator := preload("res://scenes/expedition/dungeon_generator.gd")
const DungeonLayout := preload("res://scenes/expedition/dungeon_layout.gd")
const DungeonGenerationConfig := preload("res://scenes/expedition/dungeon_generation_config.gd")
const DungeonConnectivityValidator := preload("res://scenes/expedition/dungeon_connectivity_validator.gd")
const DungeonHazardPlanner := preload("res://scenes/expedition/dungeon_hazard_planner.gd")
const DungeonSpawnPlanner := preload("res://scenes/expedition/dungeon_spawn_planner.gd")
const DungeonSceneBuilder := preload("res://scenes/expedition/dungeon_scene_builder.gd")
const DungeonBuildResult := preload("res://scenes/expedition/dungeon_build_result.gd")
const DungeonStreamingController := preload("res://scenes/expedition/dungeon_streaming_controller.gd")
const DUNGEON_VISIBLE_LOCAL_LIGHT_BUDGET := 12
const STREAM_CHUNK_SIZE_CELLS := 8
const STREAM_LIGHT_CHUNK_RADIUS := 2
const STREAM_PHYSICS_CHUNK_RADIUS := 1
const STREAM_VISUAL_CHUNK_RADIUS := 1
const STREAM_TERRAIN_CHUNK_RADIUS := 1
const STREAM_UPDATE_INTERVAL := 0.25
const LARGE_ROOM_AREA := 48
const DOOR_SURROUND_THICKNESS := 0.2
const CEILING_THICKNESS := 0.1
const CEILING_TRANSITION_GAP := 0.015
const PLAYER_VISION_BASE_ENERGY := 2.4
const PLAYER_VISION_BASE_RANGE := 10.0

# 地形渲染配置已提取至 DungeonTerrainConfig
const VOXEL_LIGHTING := preload("res://globals/visual/voxel_lighting_adapter.gd")
const TERRAIN_CFG := preload("res://scenes/expedition/dungeon_terrain_config.gd")
const LIGHTING_HELPER := preload("res://scenes/expedition/dungeon_lighting_helper.gd")

const MATERIALS_CONFIG = {
	"blackberry": 15, "glowshroom": 12, "moongrass": 10, "goblin_nail": 8,
	"mistflower": 8, "wolfear_herb": 8, "pixie_dust": 5, "poison_berry": 4
}

const DECOR_CONFIG = {
	"res://scenes/props/decor/bones.tscn": 20,
	"res://scenes/props/decor/lit_candles.tscn": 15,
	"res://scenes/props/decor/floor_candelabrum.tscn": 9,
	"res://scenes/props/decor/wall_candelabrum.tscn": 8,
	"res://scenes/props/decor/iron_bar_grate.tscn": 7,
	"res://scenes/props/decor/spiderweb.tscn": 15,
	"res://scenes/props/decor/bench.tscn": 10,
	"res://scenes/props/decor/chair.tscn": 10,
	"res://scenes/props/decor/table.tscn": 10,
	"res://scenes/props/crates/small_crate.tscn": 10,
	"res://scenes/props/barrel/barrel.tscn": 10
}

const BATCHED_DECOR_SCENES := {
	"res://scenes/props/decor/bones.tscn": true,
	"res://scenes/props/decor/bench.tscn": true,
	"res://scenes/props/decor/chair.tscn": true,
	"res://scenes/props/decor/table.tscn": true,
	"res://scenes/props/crates/small_crate.tscn": true,
	# iron_bar_grate：纯静态 MeshInstance3D（10 根铁栏），无 Light/Particle/脚本/拾取行为，
	# 可安全并入 MultiMesh 批处理，单实例 10 个 draw call → 整批 1 个。
	"res://scenes/props/decor/iron_bar_grate.tscn": true,
	# pillar：纯静态体素石柱，但按房间高度 scale.y，需逐实例 Transform 合批（见 _spawn_batched_decor）。
	"res://scenes/props/structures/pillar.tscn": true,
	# ruble：纯静态体素瓦砾，大房间随机旋转，需逐实例旋转 Transform 合批。
	"res://scenes/props/decor/ruble.tscn": true,
}

# 散落装饰/材料的距离剔除阈值（米）：超过该距离不再渲染，减少远处 draw call。
# 结构几何体（地板/墙/天花板）不应用此剔除，避免远处穿洞。
const DECOR_VISIBILITY_RANGE_END := 60.0
const TORCH_VISIBILITY_RANGE_END := 35.0

var player_spawn_pos := Vector3.ZERO

# 阶段 9 接线：新生产链持有引用（供生产集成测试断言 level.layout / level.build_result / level.streaming_controller）
# 阶段 9 条 2：旧字段 _grid/layout.rooms/layout.room_roles/layout.heights 已退役，统一读 layout.*
var layout: DungeonLayout = null
var build_result: DungeonBuildResult = null
var streaming_controller: DungeonStreamingController = null

const TILE_SIZE := 3.0
const STANDARD_DOOR_SIZE_METERS := Vector2(1.0, 2.0)
const BOSS_DOOR_SIZE_METERS := Vector2(2.0, 2.0)

var _shared_floor_mat: ShaderMaterial = null
var _shared_ceiling_mat: ShaderMaterial = null

# 用于收集 GPU 实例坐标，优化渲染性能
var floor_transforms: Array[Transform3D] = []
var ceiling_transforms: Array[Transform3D] = []
# 墙面按尺寸分组：key=rounded size, value={size, transforms}
# 不同高度/方向的薄墙段需要不同的 mesh 和 tile_repeat，避免整格墙体重合闪烁。
var wall_transforms_by_height: Dictionary = {}
var batched_decor_transforms: Dictionary = {}
var _exploration_pressure: ExplorationPressure = null
var _expedition_hud: ExpeditionHUD = null
var _combat_hud: CombatHUD = null
var _expedition_finished := false
var _streamed_physics_bodies: Array[PhysicsBody3D] = []  # 阶段 9 条 5 后仅留作注释参考；实际 streaming 路径 controller 持

## 创建地形 ShaderMaterial
## tile_name: TILE_LAYOUT 中的键（"WALL"/"FLOOR"/"CEILING"等）
## tile_repeat: 每轴平铺次数， = 该面的物理尺寸（米），1m = 1次 = 32px
func _make_terrain_mat(tile_name: String, tile_repeat: Vector2) -> ShaderMaterial:
	return TERRAIN_CFG.make_terrain_mat(tile_name, tile_repeat)

## 当前地牢所属区域（BrewingData.Zone 枚举值）。
## 决定宝箱材料掉落池，由关卡入口或 ExpeditionManager 注入。
@export var dungeon_zone: int = 0  # 默认地牢

func is_procedural() -> bool:
	return true

func _ready() -> void:
	# 注册为当前关卡，供 throw_weapon 等 add_child 使用
	GameState.register_level(self)

	# 从 ZoneManager 读取玩家选定的区域，配置宝箱 zone 与散落材料池
	var zm: Node = Service.zone_manager()
	if zm != null:
		dungeon_zone = zm.get_zone()

	# 阶段 9 接线：新生产链 DungeonGenerator → Layout → Validator → Planner → Builder → Streaming
	var config := DungeonGenerationConfig.new()
	config.zone = dungeon_zone
	layout = DungeonGenerator.new().generate(config)
	if layout.is_empty():
		push_warning("[Dungeon] DungeonGenerator returned empty layout, fallback abandoned")
		return

	var layout_report := layout.validate()
	if not layout_report["valid"]:
		# 旧 isaac 产出可能 extraction/stairs 未命中（0.2 概率），validate 报 warning 不强制 invalid；
		# 只有真 error 才中止。errors 含真错时中止。
		var real_errors: Array = layout_report["errors"]
		if not real_errors.is_empty():
			push_warning("[Dungeon] layout validate failed: %s" % str(real_errors))
			return

	if config.enable_connectivity_check:
		var connectivity_report := DungeonConnectivityValidator.new().validate(layout)
		# 阶段 9 条 7：阈值代码落实（reachable_ratio_threshold 默认 0.9 在 validator 内），
		# 不再把"90%+"写注释；必命中点 player_spawn/boss 仍必须可达。
		var missing: Array = connectivity_report["missing_required_points"]
		if missing.has("player_spawn_cell") or missing.has("boss_cell"):
			push_warning("[Dungeon] connectivity missing required points: %s" % str(missing))
			return
		if bool(connectivity_report["ratio_below_threshold"]):
			push_warning("[Dungeon] connectivity reachable ratio %.2f below threshold" % float(connectivity_report["reachable_ratio"]))
			return

	if config.enable_hazards:
		DungeonHazardPlanner.new().plan(layout)

	if config.enable_spawn_planning:
		var spawn_planner := DungeonSpawnPlanner.new()
		spawn_planner.plan_enemy_spawns(layout)
		spawn_planner.plan_item_spawns(layout)
		spawn_planner.plan_chest_spawns(layout)

	# build_result 集中实例化 hazard/chest/extraction portal（唯一路径，旧 _generate_visuals 调用已注释）
	build_result = DungeonSceneBuilder.new().build(layout, self)

	# streaming controller 挂场景树自跑（_process 自带节流），不再由本类包一层定时器
	streaming_controller = DungeonStreamingController.new()
	add_child(streaming_controller)
	streaming_controller.configure(layout, build_result)

	# 阶段 9 条 2：_grid/layout.rooms/layout.room_roles/layout.heights 退役，统一读 layout.*
	# （terrain floor/wall/ceiling/door 重型几何暂留 procedural，条 1 再迁入 DungeonSceneBuilder）
	_setup_zone_ambient()
	_build_terrain_geometry(layout.grid)
	player_spawn.global_position = player_spawn_pos
	var spawned_player: Player = spawn_player()
	_spawn_dungeon_enemies(spawned_player)
	_spawn_dungeon_items()  # 使用 ItemSpawner 按标签放置物品
	_stabilize_dungeon_lighting()
	_mount_expedition_hud()
	_setup_exploration_pressure()
	# extraction portal 信号接线（builder 只 instantiate，信号属 runtime 范畴）
	_wire_extraction_portal_signal()
	if AudioManager:
		AudioManager.start_music()

## 把 ExtractionPortal 的 extraction_requested 信号接到本类的 _on_extraction_requested。
## builder 阶段不接信号（只 instantiate 节点）；runtime 范畴在此接。
func _wire_extraction_portal_signal() -> void:
	if build_result == null or build_result.interaction_root == null:
		return
	for child in build_result.interaction_root.get_children():
		if String(child.get_meta("topdown_kind", "")) == "extraction" and child.has_signal("extraction_requested"):
			child.extraction_requested.connect(_on_extraction_requested)
			break  # 唯一 ExtractionPortal

func _process(delta: float) -> void:
	# 阶段 9 接线：streaming 唯一由 DungeonStreamingController 实现（controller 是子 Node，自带 _process 节流）。
	# 本类不再包一层定时器，旧 _update_streamed_chunks 调用注释掉。
	# terrain streaming 注册转调 controller（见 register_streamed_physics_node / register_streamed_visual_node）。
	if streaming_controller == null or not is_instance_valid(streaming_controller):
		return
	# controller._process 自跑节流；本类 _process 仅留作未来 runtime 需要帧驱动时用，现无操作。
	return

## 调用 DungeonSpawner autoload 按区域生成怪物，注入 player 引用
## spawned_player: 由 spawn_player() 返回的 Player 实例，避免依赖 GameState.current_player
## 的延迟注册时序问题
func _spawn_dungeon_enemies(spawned_player: Node3D = null) -> void:
	var spawner: Node = Service.dungeon_spawner()
	if spawner == null:
		push_warning("[Dungeon] DungeonSpawner autoload not found, no enemies spawned")
		return
	var player_node: Node3D = spawned_player
	if player_node == null:
		player_node = GameState.current_player
	if player_node == null:
		push_warning("[Dungeon] Player not spawned, skip enemy generation")
		return
	# 阶段 9 接线：调 spawn_enemies_from_layout 接 layout.enemy_spawn_specs，
	# 不再 9 参数重读 _grid/layout.rooms/layout.room_roles（DungeonSpawnPlanner 已规划 spec）。
	# 敌人挂到 build_result.spawn_root 集中管理，不再散 add 到本类根。
	var spawn_root: Node = build_result.spawn_root if build_result != null else self
	var spawned_enemies: Array = spawner.spawn_enemies_from_layout(layout, spawn_root, player_node)
	for enemy in spawned_enemies:
		register_streamed_physics_node(enemy)

## 调用 ItemSpawner autoload 按 layout.item_spawn_specs 放置物品（材料）。
## 阶段 9 条 4 接线：不再 spawn_items_for_level(_grid, ...) 6 参数重读 grid 盲扫，
## 改调 spawn_items_from_layout 接 layout.item_spawn_specs 实例化，物挂 build_result.spawn_root。
func _spawn_dungeon_items() -> void:
	var spawner: Node = Service.item_spawner()
	if spawner == null:
		push_warning("[Dungeon] ItemSpawner autoload not found, skipping item placement")
		return
	var spawn_root: Node = build_result.spawn_root if build_result != null else self
	spawner.spawn_items_from_layout(layout, spawn_root)
	_build_batched_decor_multi_meshes()

func _stabilize_dungeon_lighting() -> void:
	var player_node: Node3D = GameState.current_player
	if player_node != null and is_instance_valid(player_node):
		if player_node.has_method("_setup_player_light"):
			player_node._setup_player_light()
	# 阶段 9 条 5：灯光收集转调 DungeonStreamingController.register_light，
	# 不再 procedural 持有 _streamed_environment_lights/_environment_light_chunks 旧 streaming 状态。
	var local_lights: Array[Light3D] = []
	_collect_local_lights(self, local_lights)
	for light in local_lights:
		if _is_player_vision_light(light):
			_configure_player_vision_light(light)
			continue
		if _is_hint_light(light):
			light.visible = false
			continue
		if light is OmniLight3D or light is SpotLight3D:
			light.visible = false
			if streaming_controller != null and is_instance_valid(streaming_controller):
				streaming_controller.register_light(light)
	if streaming_controller != null and is_instance_valid(streaming_controller):
		streaming_controller.update_streaming(true)

# 阶段 9 条 5：terrain chunk 注册 / chunk 计算转调 DungeonStreamingController（删旧实现后唯一路径）
func _register_terrain_chunk_node(chunk: Vector2i, node: Node3D) -> void:
	if streaming_controller != null and is_instance_valid(streaming_controller):
		streaming_controller.register_terrain_chunk(chunk, node)

func _world_to_stream_chunk(pos: Vector3) -> Vector2i:
	# layout 未就绪时用默认 tile_size=3.0 估算（与 controller 一致公式）
	var tile_size: float = layout.tile_size if layout != null else 3.0
	var chunk_size := float(STREAM_CHUNK_SIZE_CELLS) * tile_size
	return Vector2i(int(floor(pos.x / chunk_size)), int(floor(pos.z / chunk_size)))

func _collect_local_lights(node: Node, result: Array[Light3D]) -> void:
	LIGHTING_HELPER.collect_local_lights(node, result)

func _is_player_vision_light(light: Light3D) -> bool:
	return LIGHTING_HELPER.is_player_vision_light(light, Player.PLAYER_VISION_LIGHT_NAME)

func _configure_player_vision_light(light: Light3D) -> void:
	LIGHTING_HELPER.configure_player_vision_light(light, PLAYER_VISION_BASE_ENERGY, PLAYER_VISION_BASE_RANGE)

func _is_hint_light(light: Light3D) -> bool:
	return LIGHTING_HELPER.is_hint_light(light, self)

func _is_generated_trap_node(node: Node) -> bool:
	return LIGHTING_HELPER.is_generated_trap_node(node)

func register_streamed_visual_node(node: Node3D) -> void:
	# 阶段 9 条 5：纯转调 DungeonStreamingController，删旧兜底（controller 在 _ready add_child 后永就绪）
	if streaming_controller != null and is_instance_valid(streaming_controller):
		streaming_controller.register_visual_node(node)

func register_streamed_physics_node(node: Node) -> void:
	# 阶段 9 条 5：纯转调 DungeonStreamingController，删旧兜底
	if streaming_controller != null and is_instance_valid(streaming_controller):
		streaming_controller.register_physics_node(node)

func _mount_expedition_hud() -> void:
	var hud_scene = load("res://scenes/ui/expedition_hud.tscn")
	if not hud_scene:
		return
	var hud := hud_scene.instantiate() as ExpeditionHUD
	_expedition_hud = hud
	var layer = CanvasLayer.new()
	layer.name = "ExpeditionHUDLayer"
	layer.add_child(hud)
	add_child(layer)

	# World.tscn owns the shared in-game UI. Standalone dungeon runs keep this fallback.
	if not _is_running_under_world():
		var game_ui = load("res://scenes/ui/ui.tscn")
		if game_ui:
			var ui_instance = game_ui.instantiate()
			add_child(ui_instance)
		var combat_hud_scene = load("res://scenes/ui/combat_hud.tscn")
		if combat_hud_scene:
			_combat_hud = combat_hud_scene.instantiate() as CombatHUD
			add_child(_combat_hud)

func _is_running_under_world() -> bool:
	var node: Node = get_parent()
	while node != null:
		if node.has_method("transition_to_tavern") and node.has_method("transition_to_dungeon"):
			return true
		node = node.get_parent()
	return false

func _setup_exploration_pressure() -> void:
	_exploration_pressure = EXPLORATION_PRESSURE_SCRIPT.new() as ExplorationPressure
	_exploration_pressure.name = "ExplorationPressure"
	_exploration_pressure.pressure_changed.connect(_on_pressure_changed)
	_exploration_pressure.expedition_overtime.connect(_on_expedition_overtime)
	add_child(_exploration_pressure)
	_on_pressure_changed(_exploration_pressure.make_snapshot())

func _on_pressure_changed(snapshot: Dictionary) -> void:
	if _expedition_hud != null and is_instance_valid(_expedition_hud):
		_expedition_hud.update_pressure(snapshot)
	var combat_hud := _get_combat_hud()
	if combat_hud != null and is_instance_valid(combat_hud):
		combat_hud.update_pressure(snapshot)
	_apply_player_vision_pressure(float(snapshot.get("vision_range_multiplier", 1.0)))
	_apply_environment_activity(float(snapshot.get("environment_activity_multiplier", 1.0)))
	_apply_monster_hunt_pressure(bool(snapshot.get("force_monster_hunt", false)))

func _get_combat_hud() -> CombatHUD:
	if _combat_hud != null and is_instance_valid(_combat_hud):
		return _combat_hud
	var node: Node = self
	while node != null:
		var found := node.get_node_or_null("CombatHUD") as CombatHUD
		if found != null:
			_combat_hud = found
			return _combat_hud
		node = node.get_parent()
	return null

func _apply_player_vision_pressure(multiplier: float) -> void:
	var player_node := GameState.current_player
	if player_node == null or not is_instance_valid(player_node):
		return
	var light := player_node.get_node_or_null(Player.PLAYER_VISION_LIGHT_NAME) as OmniLight3D
	if light == null:
		return
	var light_multiplier := clampf(multiplier, 0.0, 1.0)
	light.visible = light_multiplier > 0.0
	light.light_energy = PLAYER_VISION_BASE_ENERGY * light_multiplier
	light.omni_range = PLAYER_VISION_BASE_RANGE * light_multiplier

func _apply_environment_activity(multiplier: float) -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		if node == null or not is_instance_valid(node):
			continue
		node.set_meta("environment_activity_mult", clampf(multiplier, 1.0, 1.75))

func _apply_monster_hunt_pressure(force_hunt: bool) -> void:
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

func _on_door_pressure_action(action: String) -> void:
	if _exploration_pressure == null:
		return
	_exploration_pressure.record_door_action(action)

func _on_expedition_overtime(_snapshot: Dictionary) -> void:
	var player_node := GameState.current_player as Player
	_finish_expedition(player_node, false)

func _setup_zone_ambient() -> void:
	# 清空先前收集的 Transform 数组



	# 按区域设置环境光与雾效：
	#   地牢(0): 阴冷微光，潮湿石砌地牢，依赖火把照明
	#   森林(1): 明亮青绿顶光，模拟树冠筛落的月光（无需火把）
	#   洞窟(2): 极暗冷紫，依赖火把照明
	#   墓园(3): 阴冷灰蓝，依赖火把照明
	#   火山(4): 暖橙辉光，熔岩自发光（无需火把）
	#   遗迹(5): 灵界蓝白辉光，古代魔力弥漫（无需火把）
	var zone_ambient_config := _get_zone_ambient_config(dungeon_zone)
	var ambient_dir := DirectionalLight3D.new()
	ambient_dir.rotation_degrees = Vector3(-90, 0, 0)
	ambient_dir.light_energy = zone_ambient_config.light_energy
	ambient_dir.light_color = zone_ambient_config.light_color
	ambient_dir.shadow_enabled = false
	add_child(ambient_dir)

	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_color = zone_ambient_config.ambient_color
	env.environment.ambient_light_energy = zone_ambient_config.ambient_energy
	env.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment.fog_enabled = zone_ambient_config.fog_enabled
	env.environment.fog_light_color = zone_ambient_config.fog_color
	env.environment.fog_density = zone_ambient_config.fog_density
	# 露天区域添加天空盒
	var open_sky_zones := [1, 3, 4, 5]  # 森林、墓园、火山、遗迹
	if dungeon_zone in open_sky_zones:
		var sky_mat := ProceduralSkyMaterial.new()
		match dungeon_zone:
			1:  # 森林 — 深绿夜空
				sky_mat.sky_top_color = Color(0.05, 0.08, 0.15)
				sky_mat.sky_horizon_color = Color(0.1, 0.18, 0.12)
				sky_mat.ground_horizon_color = Color(0.05, 0.1, 0.06)
				sky_mat.ground_bottom_color = Color(0.02, 0.04, 0.03)
			3:  # 墓园 — 阴冷灰蓝夜空
				sky_mat.sky_top_color = Color(0.08, 0.08, 0.15)
				sky_mat.sky_horizon_color = Color(0.1, 0.12, 0.18)
				sky_mat.ground_horizon_color = Color(0.08, 0.06, 0.1)
				sky_mat.ground_bottom_color = Color(0.03, 0.02, 0.05)
			4:  # 火山 — 暗红橙夜空，熔岩映照
				sky_mat.sky_top_color = Color(0.12, 0.04, 0.02)
				sky_mat.sky_horizon_color = Color(0.25, 0.08, 0.03)
				sky_mat.ground_horizon_color = Color(0.15, 0.05, 0.02)
				sky_mat.ground_bottom_color = Color(0.08, 0.02, 0.01)
			5:  # 遗迹 — 灵界紫蓝夜空，星光闪烁
				sky_mat.sky_top_color = Color(0.06, 0.04, 0.15)
				sky_mat.sky_horizon_color = Color(0.12, 0.08, 0.25)
				sky_mat.ground_horizon_color = Color(0.08, 0.05, 0.15)
				sky_mat.ground_bottom_color = Color(0.03, 0.02, 0.08)
		var sky := Sky.new()
		sky.sky_material = sky_mat
		env.environment.background_mode = Environment.BG_SKY
		env.environment.sky = sky
	add_child(env)


func _build_terrain_geometry(grid: Array) -> void:
	# 阶段 9 条 1 拆分：地形几何段（wall_h_map 预计算 + floor/wall/ceiling/lintel/pillar/torch/chest 主循环）
	# 暂留 procedural 内独立成函数，下回合真迁 DungeonSceneBuilder
	floor_transforms.clear()
	ceiling_transforms.clear()
	wall_transforms_by_height.clear()
	batched_decor_transforms.clear()
	var grid_width = grid[0].size() if grid.size() > 0 else 0
	var grid_height = grid.size()
	var offset_x = -(grid_width * TILE_SIZE) / 2.0
	var offset_z = -(grid_height * TILE_SIZE) / 2.0
	var OFFSET := Vector3(offset_x, 0, offset_z)
	var player_spawned := false
	var preferred_spawn_cell := Vector2i.ZERO
	var has_preferred_spawn := false
	if layout.room_roles.has("start"):
		preferred_spawn_cell = _rect_center_cell(layout.room_roles["start"])
		has_preferred_spawn = true

	# ── 预计算墙体高度（两遍，消除相邻墙格高度差接缝）──────────────────
	# 第一遍：每个墙格取所有 4 邻格（含其他墙格）的最大 layout.heights 值
	var wall_h_map: Dictionary = {}
	for wy in range(grid_height):
		for wx in range(grid_width):
			if grid[wy][wx] == 2:
				var best: float = layout.heights[wy][wx]
				for d in [Vector2i(0,-1), Vector2i(0,1), Vector2i(1,0), Vector2i(-1,0)]:
					var nx2 = wx + d.x
					var ny2 = wy + d.y
					if nx2 >= 0 and nx2 < grid_width and ny2 >= 0 and ny2 < grid_height:
						best = max(best, layout.heights[ny2][nx2])
				wall_h_map[Vector2i(wx, wy)] = best if best > 0.0 else 3.0

	# 第二遍：相邻墙格互相传播最大值（消除"隔一格"仍存在的高度差）
	for wy in range(grid_height):
		for wx in range(grid_width):
			if grid[wy][wx] == 2:
				var key := Vector2i(wx, wy)
				var cur: float = wall_h_map[key]
				for d in [Vector2i(0,-1), Vector2i(0,1), Vector2i(1,0), Vector2i(-1,0)]:
					var nk := Vector2i(wx + d.x, wy + d.y)
					if wall_h_map.has(nk) and wall_h_map[nk] > cur:
						cur = wall_h_map[nk]
				wall_h_map[key] = cur
	# ─────────────────────────────────────────────────────────────────────
	var door_edge_keys := _collect_room_door_edge_keys(grid)

	for y in range(grid.size()):
		for x in range(grid[y].size()):
			var cell_type: int = grid[y][x]
			var cell_pos := OFFSET + Vector3(x * TILE_SIZE, 0, y * TILE_SIZE)
			_spawn_floor(cell_pos, TILE_SIZE)

			if cell_type == 2:
				var wall_height: float = wall_h_map.get(Vector2i(x, y), 3.0)
				_spawn_wall(cell_pos, TILE_SIZE, wall_height)
			elif cell_type != 0:
				_spawn_ceiling(cell_pos, TILE_SIZE, layout.heights[y][x])

				# Generate lintels for ceiling height mismatches between adjacent floors
				var adj_dirs := [
					[Vector2i(0, -1), Vector3(0, 0, -TILE_SIZE / 2.0), Vector3(TILE_SIZE, 1.0, 0.2)],
					[Vector2i(0, 1), Vector3(0, 0, TILE_SIZE / 2.0), Vector3(TILE_SIZE, 1.0, 0.2)],
					[Vector2i(1, 0), Vector3(TILE_SIZE / 2.0, 0, 0), Vector3(0.2, 1.0, TILE_SIZE)],
					[Vector2i(-1, 0), Vector3(-TILE_SIZE / 2.0, 0, 0), Vector3(0.2, 1.0, TILE_SIZE)]
				]
				var current_h: float = layout.heights[y][x]
				for adj in adj_dirs:
					var d: Vector2i = adj[0]
					var offset_pos: Vector3 = adj[1]
					var default_size: Vector3 = adj[2]
					var nx = x + d.x
					var ny = y + d.y
					if nx >= 0 and nx < grid_width and ny >= 0 and ny < grid_height:
						var n_type = grid[ny][nx]
						if n_type != 2 and n_type != 0:
							var n_h: float = layout.heights[ny][nx]
							if current_h > n_h:
								var current_cell := Vector2i(x, y)
								var neighbor_cell := Vector2i(nx, ny)
								if _should_spawn_ceiling_transition_lintel(current_cell, neighbor_cell, door_edge_keys):
									var transition_spec := _ceiling_transition_lintel_spec(cell_pos, offset_pos, default_size, n_h, current_h)
									if not transition_spec.is_empty():
										_spawn_lintel(transition_spec["position"], transition_spec["size"])

			match cell_type:
				5:
					var room_h = layout.heights[y][x]
					var pillar_t := Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, room_h / 3.0, 1.0)), cell_pos)
					if not _spawn_batched_decor(PILLAR_PREFAB.resource_path, pillar_t):
						# 兜底：prefab 加载失败时仍按旧逻辑逐个实例化（柱子为纯静态，无拾取逻辑）。
						var pillar := PILLAR_PREFAB.instantiate()
						pillar.position = cell_pos
						pillar.scale.y = room_h / 3.0
						add_child(pillar)
						_ensure_collision_on_instance(pillar)
						_configure_scene_object(pillar)
						register_streamed_physics_node(pillar)
				3:
					var cell := Vector2i(x, y)
					if _is_boss_reward_chest_cell(cell):
						_spawn_prefab(BOSS_CHEST_PREFAB, cell_pos)
					elif randf() < 0.7:
						_spawn_prefab(CHEST_PREFAB, cell_pos)
					else:
						_spawn_random_decor(cell_pos)
				4:
					pass

			if cell_type != 2 and cell_type != 0:
				if not player_spawned and cell_type == 1 and (not has_preferred_spawn or Vector2i(x, y) == preferred_spawn_cell):
					player_spawn_pos = cell_pos + Vector3(0, 0.5, 0)
					player_spawned = true
				elif player_spawned and not _is_start_room_cell(Vector2i(x, y)):
					# 火把仅限地牢(0)、洞窟(2)和墓园(3)，其他区域靠环境光或自发光
					var torch_zones := [0, 2, 3]  # 地牢、洞窟、墓园
					if dungeon_zone in torch_zones:
						# Wall torches
						var directions := [
							Vector2i(0, -1),
							Vector2i(0, 1),
							Vector2i(1, 0),
							Vector2i(-1, 0),
						]
						var torch_spawned := false
						for dir in directions:
							var nx = x + dir.x
							var ny = y + dir.y
							if nx >= 0 and nx < grid_width and ny >= 0 and ny < grid_height:
								if grid[ny][nx] == 2:
									if randf() < 0.12:
										var h: float = wall_h_map.get(Vector2i(nx, ny), 3.0)
										_spawn_torch_on_wall(cell_pos, dir, h)
										torch_spawned = true
										break

						if not torch_spawned:
							# Low density room dressing; materials are handled centrally by ItemSpawner.
							if randf() < 0.035:
								var scatter = Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))
								_spawn_random_decor(cell_pos + scatter)
					else:
						# 无火把区域：只增加少量装饰，素材不在视觉阶段额外生成。
						if randf() < 0.055:
							var scatter = Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))
							_spawn_random_decor(cell_pos + scatter)

	# 一次性构建 MultiMesh 并添加到场景，实现合批极速绘制
	_build_multi_meshes()
	# 烘焙导航网格供敌人 NavigationAgent3D 寻路（用地板碰撞体作为可行走面）
	_build_navigation_mesh()
	_spawn_room_door_panels(grid, OFFSET, TILE_SIZE)

	# Place extraction portal on a random FLOOR tile far from spawn
	if player_spawned:
		# 阶段 9 接线：hazard/chest/extraction portal 已由 DungeonSceneBuilder 唯一实例化，
		# 旧 _spawn_large_room_terrain_features / _spawn_extraction_portal / _spawn_hazard_anchors
		# 调用注释掉避免双份实例化（验收门槛：新旧路径不存在重复实例化）。
		# downstairs portal 是手工 MeshInstance3D 拼装（属 terrain 类），builder 第二版未接，暂留此处。
		#_spawn_large_room_terrain_features(grid, OFFSET, TILE_SIZE, player_spawn_pos, layout.rooms)
		#if layout.room_roles.has("extraction"):
		#	_spawn_extraction_portal(grid, OFFSET, TILE_SIZE, player_spawn_pos)
		_spawn_downstairs_portal(grid, OFFSET, TILE_SIZE, player_spawn_pos)
		#_spawn_hazard_anchors(grid, OFFSET, TILE_SIZE, player_spawn_pos, layout.rooms)

	if not player_spawned:
		player_spawn_pos = Vector3(0, 0.5, 0)

func _spawn_hazard_anchors(grid: Array, offset: Vector3, tile_size: float, spawn_pos: Vector3, rooms: Array[Rect2i] = []) -> void:
	if grid.is_empty():
		return
	var used_cells: Array[Vector2i] = []
	if rooms.is_empty():
		rooms = [Rect2i(0, 0, grid[0].size(), grid.size())]
	for room in rooms:
		if _room_is_start_room(room):
			continue
		var candidates := _collect_hazard_candidates_for_room(grid, room, offset, tile_size, spawn_pos)
		if candidates.is_empty():
			continue
		candidates.shuffle()
		var room_target_count := _get_hazard_anchor_count_for_room(room, candidates.size())
		var room_spawned := 0
		for candidate in candidates:
			if room_spawned >= room_target_count:
				break
			var cell: Vector2i = candidate["cell"]
			var min_gap := 2 if room.size.x * room.size.y >= LARGE_ROOM_AREA else 3
			if _is_near_used_hazard_cell(cell, used_cells, min_gap):
				continue
			var trap := _pick_hazard_trap_prefab(room, room_spawned).instantiate() as Node3D
			if trap == null:
				continue
			trap.position = candidate["pos"]
			trap.set_meta("hazard_anchor", true)
			trap.set_meta("topdown_kind", "hazard")
			trap.set_meta("hazard_room", room)
			trap.set_meta("kick_lane_dir", candidate["dir"])
			trap.set_meta("placement_role", "terrain_damage_anchor")
			_configure_hazard_trap_placement(trap, grid, cell, room)
			add_child(trap)
			register_streamed_physics_node(trap)
			used_cells.append(cell)
			room_spawned += 1


func _spawn_large_room_terrain_features(grid: Array, offset: Vector3, tile_size: float, spawn_pos: Vector3, rooms: Array[Rect2i] = []) -> void:
	if grid.is_empty():
		return
	if rooms.is_empty():
		rooms = [Rect2i(0, 0, grid[0].size(), grid.size())]
	var used_cells: Array[Vector2i] = []
	for room in rooms:
		if _room_is_start_room(room):
			continue
		var area := room.size.x * room.size.y
		if area < LARGE_ROOM_AREA:
			continue
		var candidates := _collect_large_room_feature_candidates(grid, room, offset, tile_size, spawn_pos)
		if candidates.is_empty():
			continue
		candidates.shuffle()
		var target_count := _get_large_room_feature_count(room, candidates.size())
		var spawned_count := 0
		for candidate in candidates:
			if spawned_count >= target_count:
				break
			var cell: Vector2i = candidate["cell"]
			if _is_near_used_hazard_cell(cell, used_cells, 2):
				continue
			var feature := _spawn_large_room_feature(candidate["pos"], room, spawned_count, candidate["cell"])
			if feature == null:
				continue
			used_cells.append(cell)
			spawned_count += 1


func _collect_large_room_feature_candidates(grid: Array, room: Rect2i, offset: Vector3, tile_size: float, spawn_pos: Vector3) -> Array:
	var candidates: Array = []
	var entrances := _find_room_entrance_cells(grid, room)
	var inner := room.grow(-2)
	if inner.size.x <= 0 or inner.size.y <= 0:
		return candidates
	for y in range(inner.position.y, inner.position.y + inner.size.y):
		for x in range(inner.position.x, inner.position.x + inner.size.x):
			if int(grid[y][x]) != BSP_DungeonGenerator.TileType.FLOOR:
				continue
			var cell := Vector2i(x, y)
			var pos := offset + Vector3(x * tile_size, 0, y * tile_size)
			if pos.distance_to(spawn_pos) < tile_size * 4.0:
				continue
			if _is_near_room_entrance(cell, entrances, 3):
				continue
			if _is_narrow_passage_cell(grid, cell):
				continue
			candidates.append({"cell": cell, "pos": pos})
	return candidates


func _get_large_room_feature_count(room: Rect2i, candidate_count: int) -> int:
	if candidate_count <= 0:
		return 0
	var area := room.size.x * room.size.y
	if area < 80:
		return min(candidate_count, 2)
	if area < 110:
		return min(candidate_count, 3)
	return min(candidate_count, 4)


func _spawn_large_room_feature(pos: Vector3, room: Rect2i, placement_index: int, cell: Vector2i = Vector2i(-1, -1)) -> Node3D:
	var prefab := _pick_large_room_feature_prefab(room, placement_index)
	var path := prefab.resource_path
	# 静态体素道具（箱/骨/柱/瓦砾）并入 MultiMesh 批处理：逐实例 Transform（含旋转/缩放）
	# 经硬件实例化一次绘制；碰撞壳与流式注册仍保留。交互类（桶=PickableItem）跳过批处理。
	if BATCHED_DECOR_SCENES.has(path):
		var rot_y := float(randi_range(0, 3)) * 90.0
		var t := Transform3D(Basis.IDENTITY.rotated(Vector3.UP, deg_to_rad(rot_y)), pos)
		if path == PILLAR_PREFAB.resource_path:
			var room_h := 3.0
			if cell.x >= 0 and cell.y >= 0 and cell.y < layout.heights.size() and cell.x < layout.heights[cell.y].size():
				room_h = maxf(float(layout.heights[cell.y][cell.x]), 3.0)
			t = Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, room_h / 3.0, 1.0)), pos)
		if _spawn_batched_decor(path, t):
			var body := get_child(get_child_count() - 1) as Node3D
			if body != null:
				body.set_meta("topdown_kind", "terrain_feature")
				body.set_meta("large_room_feature", true)
				body.set_meta("feature_room", room)
			return null
	var instance := prefab.instantiate()
	if not (instance is Node3D):
		instance.queue_free()
		return null
	var node := instance as Node3D
	node.position = pos
	node.rotation_degrees.y = float(randi_range(0, 3)) * 90.0
	node.set_meta("topdown_kind", "terrain_feature")
	node.set_meta("large_room_feature", true)
	node.set_meta("feature_room", room)
	add_child(node)
	_ensure_collision_on_instance(node)
	_configure_scene_object(node)
	register_streamed_physics_node(node)
	return node


func _pick_large_room_feature_prefab(room: Rect2i, placement_index: int) -> PackedScene:
	var area := room.size.x * room.size.y
	var roll := (placement_index + randi_range(0, 5)) % 6
	if area >= 100 and roll == 0:
		return PILLAR_PREFAB
	match roll:
		1:
			return CRATE_PREFAB
		2:
			return BARREL_PREFAB
		3:
			return RUBBLE_PREFAB
		4:
			return BONES_PREFAB
		_:
			return PILLAR_PREFAB


func _collect_hazard_candidates_for_room(grid: Array, room: Rect2i, offset: Vector3, tile_size: float, spawn_pos: Vector3) -> Array:
	var candidates: Array = []
	var entrances := _find_room_entrance_cells(grid, room)
	var inner := room.grow(-1)
	if inner.size.x <= 0 or inner.size.y <= 0:
		return candidates
	for y in range(inner.position.y, inner.position.y + inner.size.y):
		for x in range(inner.position.x, inner.position.x + inner.size.x):
			if not _is_walkable_hazard_cell(grid, x, y):
				continue
			var cell := Vector2i(x, y)
			var pos := offset + Vector3(x * tile_size, 0.05, y * tile_size)
			if pos.distance_to(spawn_pos) < tile_size * 4.0:
				continue
			var entrance_padding := 1 if min(room.size.x, room.size.y) <= 5 else 2
			if _is_near_room_entrance(cell, entrances, entrance_padding):
				continue
			if _is_narrow_passage_cell(grid, cell):
				continue
			var lane_dir := _find_kick_lane_direction(grid, x, y, 2)
			if lane_dir != Vector2i.ZERO:
				candidates.append({"cell": cell, "dir": lane_dir, "pos": pos})
	return candidates

func _get_hazard_anchor_count_for_room(room: Rect2i, candidate_count: int) -> int:
	if candidate_count <= 0:
		return 0
	var area := room.size.x * room.size.y
	if area < 20:
		return min(candidate_count, 1)
	if area < 48:
		return min(candidate_count, 1)
	if area < 80:
		return min(candidate_count, 3)
	return min(candidate_count, 4)

func _find_room_entrance_cells(grid: Array, room: Rect2i) -> Array[Vector2i]:
	var entrances: Array[Vector2i] = []
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
					entrances.append(cell)
					break
	return entrances

func _is_on_room_edge(cell: Vector2i, room: Rect2i) -> bool:
	return cell.x == room.position.x \
		or cell.y == room.position.y \
		or cell.x == room.position.x + room.size.x - 1 \
		or cell.y == room.position.y + room.size.y - 1

func _is_near_room_entrance(cell: Vector2i, entrances: Array[Vector2i], padding_cells: int) -> bool:
	for entrance in entrances:
		if abs(cell.x - entrance.x) + abs(cell.y - entrance.y) <= padding_cells:
			return true
	return false

func _is_narrow_passage_cell(grid: Array, cell: Vector2i) -> bool:
	var open_neighbors := 0
	for dir in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var next: Vector2i = cell + dir
		if _is_walkable_hazard_cell(grid, next.x, next.y):
			open_neighbors += 1
	return open_neighbors <= 2

func _pick_hazard_trap_prefab(room: Rect2i = Rect2i(), placement_index: int = 0) -> PackedScene:
	var area := room.size.x * room.size.y
	if area >= LARGE_ROOM_AREA:
		var roll := (placement_index + randi_range(0, 2)) % 3
		match roll:
			0:
				return SPIKES_TRAP_PREFAB
			1:
				return _load_acid_trap_or_spikes()
			_:
				return FLAME_VENT_TRAP_PREFAB
	if dungeon_zone == 4:
		return _load_acid_trap_or_spikes()
	if dungeon_zone == 2 and randf() < 0.35:
		return _load_acid_trap_or_spikes()
	return SPIKES_TRAP_PREFAB


func _configure_hazard_trap_placement(trap: Node3D, grid: Array, cell: Vector2i, room: Rect2i) -> void:
	var trap_name := String(trap.name)
	match trap_name:
		"SpikesTrap":
			_configure_spikes_trap_placement(trap, grid, cell, room)
		"AcidTrap":
			_configure_acid_trap_placement(trap)
		"FlameVentTrap", "SnareTrap":
			trap.position.y = 0.04
			trap.rotation_degrees.x = 0.0
			trap.rotation_degrees.z = 0.0
			trap.set_meta("trap_mount", "floor")
		_:
			trap.position.y = 0.04


func _configure_spikes_trap_placement(trap: Node3D, grid: Array, cell: Vector2i, room: Rect2i) -> void:
	var wall_dir := _find_adjacent_wall_direction(grid, cell)
	var use_wall_mount := wall_dir != Vector2i.ZERO and randf() < 0.45 and room.size.x * room.size.y >= LARGE_ROOM_AREA
	if use_wall_mount:
		trap.set_meta("spike_mount", "wall")
		trap.set_meta("trap_mount", "wall")
		trap.set_meta("wall_direction", wall_dir)
		trap.position += Vector3(wall_dir.x, 0, wall_dir.y) * (TILE_SIZE * 0.42)
		trap.position.y = 1.05
		trap.rotation_degrees.x = 0.0
		trap.rotation.y = atan2(float(wall_dir.x), float(wall_dir.y))
	else:
		trap.set_meta("spike_mount", "floor")
		trap.set_meta("trap_mount", "floor")
		trap.position.y = 0.08
		trap.rotation_degrees.x = -90.0
		trap.rotation_degrees.z = 0.0


func _configure_acid_trap_placement(trap: Node3D) -> void:
	trap.position.y = 0.03
	trap.rotation_degrees.x = 0.0
	trap.rotation_degrees.z = 0.0
	trap.set_meta("trap_mount", "floor")
	trap.set_meta("acid_ground_only", true)
	trap.set_meta("acid_pit", true)
	_add_acid_pit_visual(trap)


func _add_acid_pit_visual(trap: Node3D) -> void:
	if trap.find_child("AcidPit", true, false) != null:
		return
	var pit := MeshInstance3D.new()
	pit.name = "AcidPit"
	pit.set_meta("topdown_kind", "terrain_feature")
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.9
	mesh.bottom_radius = 0.75
	mesh.height = 0.14
	mesh.radial_segments = 18
	pit.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.02, 0.025, 0.018, 1.0)
	mat.roughness = 1.0
	pit.material_override = mat
	pit.position = Vector3(0.5, -0.24, 0.5)
	trap.add_child(pit)


func _find_adjacent_wall_direction(grid: Array, cell: Vector2i) -> Vector2i:
	var directions: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0)]
	for dir in directions:
		var next: Vector2i = cell + dir
		if next.y < 0 or next.y >= grid.size() or next.x < 0 or next.x >= grid[next.y].size():
			continue
		if int(grid[next.y][next.x]) == BSP_DungeonGenerator.TileType.WALL:
			return dir
	return Vector2i.ZERO

func _load_acid_trap_or_spikes() -> PackedScene:
	var acid_scene := load(ACID_TRAP_PATH)
	if acid_scene is PackedScene:
		return acid_scene
	return SPIKES_TRAP_PREFAB

func _find_kick_lane_direction(grid: Array, x: int, y: int, min_lane_cells: int = 2) -> Vector2i:
	for dir in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var clear := true
		for step in range(1, min_lane_cells + 1):
			var lx: int = x - dir.x * step
			var ly: int = y - dir.y * step
			if not _is_walkable_hazard_cell(grid, lx, ly):
				clear = false
				break
		if clear:
			return dir
	return Vector2i.ZERO

func _is_walkable_hazard_cell(grid: Array, x: int, y: int) -> bool:
	if y < 0 or y >= grid.size():
		return false
	if x < 0 or x >= grid[y].size():
		return false
	var cell_type: int = int(grid[y][x])
	return cell_type != 0 and cell_type != 2

func _is_near_used_hazard_cell(cell: Vector2i, used_cells: Array[Vector2i], min_distance_cells: int) -> bool:
	for used in used_cells:
		if abs(cell.x - used.x) + abs(cell.y - used.y) < min_distance_cells:
			return true
	return false

func _spawn_extraction_portal(grid: Array, offset: Vector3, tile_size: float, spawn_pos: Vector3) -> void:
	var best_dist = 0.0
	var best_pos = Vector3.ZERO
	var found_floor := false
	if not layout.room_roles.has("extraction"):
		return
	var extraction_room: Rect2i = layout.room_roles["extraction"]
	var extraction_center := _rect_center_cell(extraction_room)
	if _is_walkable_hazard_cell(grid, extraction_center.x, extraction_center.y):
		best_pos = offset + Vector3(extraction_center.x * tile_size, 0.5, extraction_center.y * tile_size)
		found_floor = true
	for y in range(grid.size()):
		for x in range(grid[y].size()):
			var cell := Vector2i(x, y)
			if not extraction_room.has_point(cell):
				continue
			if not _is_walkable_hazard_cell(grid, x, y):
				continue
			var pos = offset + Vector3(x * tile_size, 0.5, y * tile_size)
			var dist = Vector2(cell).distance_squared_to(Vector2(extraction_center))
			if not found_floor or dist < best_dist:
				found_floor = true
				best_dist = dist
				best_pos = pos

	if not found_floor:
		push_warning("[Dungeon] No floor tile found for extraction portal")
		return

	# 体素风撤离传送门：石质底座 + 四角发光符文柱 + 顶部光环。
	# 预制体内部已含 StaticBody3D(层64, 可被玩家准星射线命中显示悬停提示) 与
	# Area3D(走入自动撤离) 以及 interact()(按 [E] 主动撤离)。
	var portal := EXTRACTION_PORTAL_PREFAB.instantiate() as Node3D
	portal.name = "ExtractionPortal"
	portal.set_meta("topdown_kind", "extraction")
	portal.position = best_pos
	portal.extraction_requested.connect(_on_extraction_requested)
	add_child(portal)
	register_streamed_physics_node(portal)

	print("[Dungeon] Extraction portal placed at ", best_pos)

func _on_extraction_requested(player: Player) -> void:
	print("[Dungeon] Extraction triggered by player!")
	_finish_expedition(player, true)

func _spawn_downstairs_portal(grid: Array, offset: Vector3, tile_size: float, spawn_pos: Vector3) -> void:
	var best_dist := 0.0
	var best_pos := Vector3.ZERO
	var found_floor := false
	if layout.room_roles.has("stairs"):
		var stairs_center := _rect_center_cell(layout.room_roles["stairs"])
		if _is_walkable_hazard_cell(grid, stairs_center.x, stairs_center.y):
			best_pos = offset + Vector3(stairs_center.x * tile_size, 0.5, stairs_center.y * tile_size)
			found_floor = true
	for y in range(grid.size()):
		for x in range(grid[y].size()):
			if int(grid[y][x]) != BSP_DungeonGenerator.TileType.FLOOR:
				continue
			var pos := offset + Vector3(x * tile_size, 0.5, y * tile_size)
			var dist := pos.distance_to(spawn_pos)
			if not found_floor or (not layout.room_roles.has("stairs") and dist > best_dist):
				found_floor = true
				best_dist = dist
				best_pos = pos

	if not found_floor:
		push_warning("[Dungeon] No floor tile found for downstairs portal")
		return

	var root := Node3D.new()
	root.name = "DownstairsPortal"
	root.set_meta("topdown_kind", "stairs")
	root.position = best_pos
	add_child(root)
	register_streamed_visual_node(root)

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

	var area := Area3D.new()
	area.name = "DownstairsArea"
	area.set_meta("topdown_kind", "stairs")
	area.position = Vector3(0, 0.5, 0)
	var col_shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(2.0, 2.0, 2.0)
	col_shape.shape = box_shape
	area.add_child(col_shape)
	area.body_entered.connect(_on_downstairs_entered)
	root.add_child(area)

	print("[Dungeon] Downstairs portal placed at ", best_pos)

func _on_downstairs_entered(body: Node3D) -> void:
	if not body is Player:
		return
	print("[Dungeon] Downstairs triggered by player")
	var world := _find_world_controller()
	if world != null:
		world.transition_to_dungeon()
	elif GameEvents:
		GameEvents.level_restarted.emit()

func _find_world_controller() -> Node:
	var node: Node = get_parent()
	while node != null:
		if node.has_method("transition_to_dungeon"):
			return node
		node = node.get_parent()
	return null

func _finish_expedition(player: Player, voluntary: bool) -> void:
	if _expedition_finished:
		return
	_expedition_finished = true
	# 撤离结算：保留随身材料，进入酒馆后可手动存入仓库
	if player != null and is_instance_valid(player):
		_settle_extraction_loot(player)
	if TavernManager:
		var result := _exploration_pressure.build_extraction_result(voluntary) if _exploration_pressure != null else {}
		TavernManager.extract_to_tavern(result)

## 撤离结算：本趟材料留在 GameState.carried_materials，进入酒馆后由仓库面板手动存取。
func _settle_extraction_loot(player: Player) -> void:
	var tm: Node = Service.tavern_manager()
	if tm == null:
		return
	# 统计本局地牢拾取物（由 GameState 记录）
	var carried_materials: int = GameState.get_carried_materials()
	var carried_weapons: int = GameState.get_carried_weapons()
	var carried_shields: int = GameState.get_carried_shields()
	print("[Dungeon] Extraction loot: %d materials, %d weapons, %d shields" % [carried_materials, carried_weapons, carried_shields])
	# 武器/盾已装备到 equipment；后续再接入完整装备仓库数据结构
	# 注入 TavernManager 统计（若方法存在）
	if tm.has_method("record_expedition_loot"):
		tm.record_expedition_loot(carried_materials, carried_weapons, carried_shields)

func _spawn_collision(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	body.position = pos
	add_child(body)
	register_streamed_physics_node(body)

func _spawn_floor(pos: Vector3, tile_size: float) -> void:
	var t := Transform3D()
	t.origin = pos - Vector3(0, 0.05, 0)
	floor_transforms.append(t)
	# 碰撞由 _build_merged_collisions() 按 chunk 合并，不再每格创建 StaticBody3D

func _spawn_wall(pos: Vector3, tile_size: float, wall_height: float) -> void:
	var t := Transform3D()
	t.origin = pos
	t.origin.y += wall_height / 2.0
	var size := Vector3(tile_size, wall_height, tile_size)
	var key := _wall_segment_key(size)
	if not wall_transforms_by_height.has(key):
		wall_transforms_by_height[key] = {
			"size": size,
			"transforms": [],
		}
	(wall_transforms_by_height[key]["transforms"] as Array).append(t)
	# 碰撞由 _build_merged_collisions() 按 chunk 合并，不再每格创建 StaticBody3D

func _spawn_ceiling(pos: Vector3, tile_size: float, ceiling_height: float) -> void:
	var t := Transform3D()
	t.origin = pos + Vector3(0, ceiling_height + CEILING_THICKNESS * 0.5, 0)
	ceiling_transforms.append(t)
	# 碰撞由 _build_merged_collisions() 按 chunk 合并，不再每格创建 StaticBody3D

func _spawn_prefab(prefab: PackedScene, pos: Vector3) -> void:
	var instance := prefab.instantiate()
	instance.position = pos
	add_child(instance)
	# 宝箱注入区域属性，决定其材料掉落池
	if instance is Chest:
		instance.zone = dungeon_zone
	# 预制体补全碰撞，并标记为场景物体层，避免和地形环境层混淆。
	_ensure_collision_on_instance(instance)
	_configure_scene_object(instance)
	register_streamed_physics_node(instance)

## 确保实例有物理碰撞：若实例及其子节点无 PhysicsBody3D，则基于 AABB 添加 StaticBody3D。
func _ensure_collision_on_instance(instance: Node) -> void:
	# 已有 PhysicsBody3D 则跳过
	if _has_physics_body(instance):
		return
	# 仅对 Node3D 处理（基于 mesh AABB 添加碰撞）
	if not (instance is Node3D):
		return
	var node3d: Node3D = instance
	# 收集所有 MeshInstance3D 子节点，为每个添加碰撞
	var meshes: Array = node3d.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		return
	# 用整体 AABB 创建单个碰撞体（更高效）
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

func _mesh_aabb_in_node_space(root: Node3D, mesh_instance: MeshInstance3D) -> AABB:
	var relative := Transform3D.IDENTITY
	var current: Node = mesh_instance
	while current != null and current != root:
		if current is Node3D:
			relative = (current as Node3D).transform * relative
		current = current.get_parent()
	if current != root:
		return mesh_instance.get_aabb()
	return relative * mesh_instance.get_aabb()

func _configure_scene_object(node: Node) -> void:
	if node is StaticBody3D:
		var body := node as StaticBody3D
		body.collision_layer = SCENE_OBJECT_LAYER
		body.collision_mask = 0
		if body.get_script() == null:
			body.set_script(SCENE_OBJECT_SCRIPT)
	for c in node.get_children():
		_configure_scene_object(c)

## 递归检测节点树是否已含 PhysicsBody3D
func _has_physics_body(node: Node) -> bool:
	if node is PhysicsBody3D:
		return true
	for c in node.get_children():
		if _has_physics_body(c):
			return true
	return false

func _spawn_lintel(pos: Vector3, size: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = pos
	# 门楣宽/高按物理尺寸平铺，1m = 1次 = 32px
	var mat := _make_terrain_mat("LINTEL", Vector2(size.x, size.y))
	mesh.material_override = mat
	add_child(mesh)
	register_streamed_visual_node(mesh)
	_spawn_collision(pos, size)

func _ceiling_transition_lintel_spec(cell_pos: Vector3, offset_pos: Vector3, default_size: Vector3, lower_height: float, upper_height: float) -> Dictionary:
	var bottom := lower_height + CEILING_THICKNESS + CEILING_TRANSITION_GAP
	var top := upper_height - CEILING_TRANSITION_GAP
	if top <= bottom:
		return {}
	var size := Vector3(default_size.x, top - bottom, default_size.z)
	var pos := cell_pos + offset_pos
	pos.y = bottom + size.y * 0.5
	return {
		"position": pos,
		"size": size,
	}

func _should_spawn_ceiling_transition_lintel(cell: Vector2i, neighbor: Vector2i, door_edge_keys: Dictionary) -> bool:
	return not door_edge_keys.has(_door_edge_key(cell, neighbor))

func _spawn_room_door_panels(grid: Array, offset: Vector3, tile_size: float) -> void:
	if layout.rooms.is_empty():
		return
	var door_specs := {}
	for room in layout.rooms:
		for spec in _collect_room_door_specs(grid, room):
			var inside: Vector2i = spec["inside"]
			var outside: Vector2i = spec["outside"]
			var key := _door_edge_key(inside, outside)
			var leads_to_boss := _is_boss_room_cell(inside) or _is_boss_room_cell(outside)
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
		_spawn_door_panel(door_specs[key], offset, tile_size, index)
		index += 1

func _collect_room_door_edge_keys(grid: Array) -> Dictionary:
	var result := {}
	if layout.rooms.is_empty():
		return result
	for room in layout.rooms:
		for spec in _collect_room_door_specs(grid, room):
			result[_door_edge_key(spec["inside"], spec["outside"])] = true
	return result

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

func _collect_room_door_specs(grid: Array, room: Rect2i) -> Array:
	var candidates: Array = []
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
						candidates.append({
							"inside": cell,
							"outside": outside,
							"dir": dir,
						})
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

func _spawn_door_panel(spec: Dictionary, offset: Vector3, tile_size: float, index: int) -> void:
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
	_spawn_door_wall_surround(door.name + "Surround", panel_pos, inside, outside, dir, boss, tile_size)
	door.configure(
		DungeonDoor.KIND_BOSS if boss else DungeonDoor.KIND_STANDARD,
		dir,
		_make_terrain_mat("BOSS_DOOR" if boss else "DOOR", Vector2(1.0, 1.0)),
		_make_terrain_mat("DOOR_SIDE", Vector2(DungeonDoor.THICKNESS, BOSS_DOOR_SIZE_METERS.y if boss else STANDARD_DOOR_SIZE_METERS.y)),
		_make_terrain_mat("DOOR_TOP", Vector2(BOSS_DOOR_SIZE_METERS.x * 0.5 if boss else STANDARD_DOOR_SIZE_METERS.x, DungeonDoor.THICKNESS))
	)
	add_child(door)
	register_streamed_visual_node(door)
	door.pressure_action.connect(_on_door_pressure_action)

func _spawn_door_wall_surround(base_name: String, panel_pos: Vector3, inside: Vector2i, outside: Vector2i, dir: Vector2i, boss: bool, tile_size: float) -> void:
	var door_size := BOSS_DOOR_SIZE_METERS if boss else STANDARD_DOOR_SIZE_METERS
	var wall_height := maxf(maxf(_height_at_cell(inside), _height_at_cell(outside)), door_size.y + 0.5)
	var side_width := maxf((tile_size - door_size.x) * 0.5, 0.0)
	if side_width <= 0.01:
		return
	var width_axis := Vector3(0, 0, 1) if dir.x != 0 else Vector3(1, 0, 0)
	var side_size := _door_surround_size(side_width, wall_height, dir)
	var side_offset := door_size.x * 0.5 + side_width * 0.5
	_spawn_door_wall_box(base_name + "LeftJamb", panel_pos - width_axis * side_offset + Vector3(0, wall_height * 0.5, 0), side_size)
	_spawn_door_wall_box(base_name + "RightJamb", panel_pos + width_axis * side_offset + Vector3(0, wall_height * 0.5, 0), side_size)

	var lintel_height := maxf(wall_height - door_size.y, 0.0)
	if lintel_height > 0.05:
		var lintel_size := _door_surround_size(door_size.x, lintel_height, dir)
		var lintel_pos := panel_pos + Vector3(0, door_size.y + lintel_height * 0.5, 0)
		_spawn_door_wall_box(base_name + "Lintel", lintel_pos, lintel_size)

func _door_surround_size(width: float, height: float, dir: Vector2i) -> Vector3:
	if dir.x != 0:
		return Vector3(DOOR_SURROUND_THICKNESS, height, width)
	return Vector3(width, height, DOOR_SURROUND_THICKNESS)

func _spawn_door_wall_box(name: String, pos: Vector3, size: Vector3) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = name
	mesh.set_meta("door_surround", true)
	mesh.set_meta("topdown_kind", "terrain_feature")
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = pos
	mesh.material_override = _make_terrain_mat("WALL", Vector2(maxf(size.x, size.z), size.y))
	add_child(mesh)
	register_streamed_visual_node(mesh)
	_spawn_collision(pos, size)
	return mesh

func _height_at_cell(cell: Vector2i) -> float:
	if cell.y < 0 or cell.y >= layout.heights.size():
		return 3.0
	if cell.x < 0 or cell.x >= layout.heights[cell.y].size():
		return 3.0
	return maxf(float(layout.heights[cell.y][cell.x]), 3.0)

func _door_edge_key(a: Vector2i, b: Vector2i) -> String:
	if a.x < b.x or (a.x == b.x and a.y <= b.y):
		return "%d,%d:%d,%d" % [a.x, a.y, b.x, b.y]
	return "%d,%d:%d,%d" % [b.x, b.y, a.x, a.y]

func _wall_segment_key(size: Vector3) -> String:
	return "%.2f,%.2f,%.2f" % [size.x, size.y, size.z]

func _is_blocking_terrain_cell(grid: Array, x: int, y: int) -> bool:
	if y < 0 or y >= grid.size():
		return true
	if x < 0 or x >= grid[y].size():
		return true
	var cell_type := int(grid[y][x])
	return cell_type == BSP_DungeonGenerator.TileType.WALL or cell_type == BSP_DungeonGenerator.TileType.EMPTY

func _wall_height_for_boundary(walkable_cell: Vector2i, blocked_cell: Vector2i, wall_h_map: Dictionary) -> float:
	if wall_h_map.has(blocked_cell):
		return float(wall_h_map[blocked_cell])
	return _height_at_cell(walkable_cell)

func _build_wall_boundary_height_map(grid: Array, wall_h_map: Dictionary) -> Dictionary:
	var entries_by_run := {}
	for y in range(grid.size()):
		for x in range(grid[y].size()):
			if not _is_walkable_hazard_cell(grid, x, y):
				continue
			var walkable_cell := Vector2i(x, y)
			for raw_dir in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0)]:
				var dir: Vector2i = raw_dir
				var blocked_cell: Vector2i = walkable_cell + dir
				if not _is_blocking_terrain_cell(grid, blocked_cell.x, blocked_cell.y):
					continue
				var run_key: String = _wall_boundary_run_key(walkable_cell, dir)
				if not entries_by_run.has(run_key):
					entries_by_run[run_key] = []
				(entries_by_run[run_key] as Array).append({
					"sort": walkable_cell.y if dir.x != 0 else walkable_cell.x,
					"key": _wall_boundary_key(walkable_cell, blocked_cell),
					"height": _wall_height_for_boundary(walkable_cell, blocked_cell, wall_h_map),
				})

	var result := {}
	for run_key in entries_by_run.keys():
		var entries: Array = entries_by_run[run_key]
		entries.sort_custom(func(a, b): return int(a["sort"]) < int(b["sort"]))
		var run: Array = []
		var previous := -999999
		for entry in entries:
			var value := int(entry["sort"])
			if not run.is_empty() and value != previous + 1:
				_assign_wall_boundary_run_height(result, run)
				run = []
			run.append(entry)
			previous = value
		if not run.is_empty():
			_assign_wall_boundary_run_height(result, run)
	return result

func _assign_wall_boundary_run_height(target: Dictionary, run: Array) -> void:
	var height := 3.0
	for entry in run:
		height = maxf(height, float(entry["height"]))
	for entry in run:
		target[str(entry["key"])] = height

func _wall_boundary_run_key(walkable_cell: Vector2i, dir: Vector2i) -> String:
	if dir.x != 0:
		var edge_x: int = walkable_cell.x if dir.x > 0 else walkable_cell.x - 1
		return "v:%d:%d" % [edge_x, dir.x]
	var edge_y: int = walkable_cell.y if dir.y > 0 else walkable_cell.y - 1
	return "h:%d:%d" % [edge_y, dir.y]

func _wall_boundary_key(walkable_cell: Vector2i, blocked_cell: Vector2i) -> String:
	return "%d,%d:%d,%d" % [walkable_cell.x, walkable_cell.y, blocked_cell.x, blocked_cell.y]

func _build_multi_meshes() -> void:
	# 1. 地板 MultiMesh（FLOOR 图块，平面 TILE_SIZE×TILE_SIZE）
	if _shared_floor_mat == null:
		# TILE_SIZE=3m → 每轴平铺 3 次（每次 = 1m = 32px）
		_shared_floor_mat = _make_terrain_mat("FLOOR", Vector2(TILE_SIZE, TILE_SIZE))
	_build_chunked_multi_meshes(
		"FloorMultiMesh",
		floor_transforms,
		Vector3(TILE_SIZE, 0.1, TILE_SIZE),
		_shared_floor_mat
	)

	# 2. 天花板 MultiMesh（CEILING 图块）
	if _shared_ceiling_mat == null:
		_shared_ceiling_mat = _make_terrain_mat("CEILING", Vector2(TILE_SIZE, TILE_SIZE))
	_build_chunked_multi_meshes(
		"CeilingMultiMesh",
		ceiling_transforms,
		Vector3(TILE_SIZE, CEILING_THICKNESS, TILE_SIZE),
		_shared_ceiling_mat
	)

	# 3. 墙面 MultiMesh（按尺寸分组，保证横向/纵向纹理重复与物理尺寸一致）
	for wall_key in wall_transforms_by_height:
		var group: Dictionary = wall_transforms_by_height[wall_key]
		var transforms: Array = group.get("transforms", [])
		if transforms.is_empty():
			continue
		var size: Vector3 = group.get("size", Vector3(TILE_SIZE, 3.0, DOOR_SURROUND_THICKNESS))
		# 屏弃缩放，改用正确尺寸的网格——此方案保证法线垂直于面，光照计算正确。
		var mat := _make_terrain_mat("WALL", Vector2(maxf(size.x, size.z), size.y))
		_build_chunked_multi_meshes(
			"WallMultiMesh_%s" % wall_key.replace(",", "_"),
			transforms,
			size,
			mat
		)

	_build_wall_occluders()
	_build_batched_decor_multi_meshes()

	# 4. 合并碰撞：每 chunk 一个 StaticBody3D + 单个 ConcavePolygonShape3D
	# 将数千个独立 StaticBody3D 收敛为几十个 body + 几十个 shape，大幅降低 Jolt 宽/窄相位开销
	_build_merged_collisions()

## 按 chunk 合并地形碰撞为少量 ConcavePolygonShape3D。
## floor/ceiling 各一组按 chunk 合；墙体按高度+chunk 合。
## 每个 chunk+类型产出一个 StaticBody3D + 单个 ConcavePolygonShape3D（由若干 Box 面片构成）。
## 为每个墙段生成 BoxOccluder3D 遮挡体。
## 配合 project.godot 的 rendering/occlusion_culling/use_occlusion_culling=true，
## 让 Godot 在运行时跳过“处于视锥内但被墙挡住”的网格/道具绘制，直接砍掉 draw call
## （实测最差视角 yaw=180 有 582 个被墙遮挡却照画的单体网格）。
## 盒尺寸对齐墙段并轻微外扩，避免盒边缘与墙几何不齐导致漏剔（墙缝里的物体被误隐藏）。
func _build_wall_occluders() -> void:
	if not ProjectSettings.get_setting("rendering/occlusion_culling/use_occlusion_culling", false):
		return
	var container := Node3D.new()
	container.name = "WallOccluders"
	add_child(container)
	for wall_key in wall_transforms_by_height:
		var group: Dictionary = wall_transforms_by_height[wall_key]
		var transforms: Array = group.get("transforms", [])
		if transforms.is_empty():
			continue
		var size: Vector3 = group.get("size", Vector3(TILE_SIZE, 3.0, DOOR_SURROUND_THICKNESS))
		for t in transforms:
			var tr := t as Transform3D
			var occ := OccluderInstance3D.new()
			var box := BoxOccluder3D.new()
			box.size = size + Vector3(0.06, 0.06, 0.06)
			occ.occluder = box
			occ.transform = tr
			container.add_child(occ)

func _build_merged_collisions() -> void:
	_build_merged_collision_group("FloorCollisions", floor_transforms, Vector3(TILE_SIZE, 0.1, TILE_SIZE))
	_build_merged_collision_group("CeilingCollisions", ceiling_transforms, Vector3(TILE_SIZE, CEILING_THICKNESS, TILE_SIZE))
	for wall_key in wall_transforms_by_height:
		var group: Dictionary = wall_transforms_by_height[wall_key]
		var transforms: Array = group.get("transforms", [])
		if transforms.is_empty():
			continue
		var size: Vector3 = group.get("size", Vector3(TILE_SIZE, 3.0, DOOR_SURROUND_THICKNESS))
		_build_merged_collision_group(
			"WallCollisions_%s" % wall_key.replace(",", "_"),
			transforms,
			size
		)

## 把一组 Transform3D（每个对应一个 box_size 盒子）按 chunk 合并为少量
## StaticBody3D + ConcavePolygonShape3D。每个盒子贡献 12 个三角形面片。
func _build_merged_collision_group(base_name: String, transforms: Array, box_size: Vector3) -> void:
	if transforms.is_empty():
		return
	var by_chunk: Dictionary = _group_transforms_by_stream_chunk(transforms)
	for chunk in by_chunk.keys():
		var chunk_transforms: Array = by_chunk[chunk]
		var body := StaticBody3D.new()
		body.name = "%s_%d_%d" % [base_name, chunk.x, chunk.y]
		body.collision_layer = PhysicsSetup.LAYER_ENVIRONMENT
		body.collision_mask = PhysicsSetup.MASK_ENVIRONMENT
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
		add_child(body)
		_register_terrain_chunk_node(chunk, body)

## 把一个轴对齐盒子的 6 个面（12 三角形）追加到 faces 数组。
## center: 盒子中心世界坐标；size: 盒子尺寸。
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
	# 6 面，每面 2 三角形（外法线朝外）
	faces.append_array([p000, p100, p110, p000, p110, p010]) # -Z
	faces.append_array([p001, p011, p111, p001, p111, p101]) # +Z
	faces.append_array([p000, p010, p011, p000, p011, p001]) # -X
	faces.append_array([p100, p101, p111, p100, p111, p110]) # +X
	faces.append_array([p000, p001, p101, p000, p101, p100]) # -Y
	faces.append_array([p010, p110, p111, p010, p111, p011]) # +Y

## 烘焙程序化地牢的导航网格。
## 直接用地板格子的顶面面片构建 NavigationMeshSourceGeometryData3D，
## 完全绕过 RenderingServer，避免 GPU → CPU 几何回传阻塞渲染管线。
## 烘焙完成后敌人 NavigationAgent3D（默认使用 World3D 默认 map）即可寻路。
func _build_navigation_mesh() -> void:
	if floor_transforms.is_empty():
		return
	# 1. 创建 NavigationRegion3D 并配置 NavigationMesh
	var region := NavigationRegion3D.new()
	region.name = "DungeonNavigationRegion"
	var nav_mesh := NavigationMesh.new()
	nav_mesh.agent_radius = PhysicsSetup.HUMANOID_COLLISION_RADIUS
	nav_mesh.agent_height = PhysicsSetup.HUMANOID_COLLISION_HEIGHT
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.2
	region.navigation_mesh = nav_mesh
	add_child(region)

	# 2. 直接构建可行走源几何数据（地板顶面面片），不创建任何 MeshInstance3D。
	#    使用 add_faces 直接注入面片到 NavigationMeshSourceGeometryData3D，
	#    完全绕过 RenderingServer，避免 GPU → CPU 几何回传阻塞渲染。
	var source_geometry_data := NavigationMeshSourceGeometryData3D.new()
	var floor_size := Vector3(TILE_SIZE, 0.1, TILE_SIZE)
	var floor_faces := PackedVector3Array()
	for t in floor_transforms:
		_append_floor_top_face(floor_faces, t.origin, floor_size)
	source_geometry_data.add_faces(floor_faces, Transform3D.IDENTITY)

	# 3. 墙体面片作为障碍几何，防止 navmesh 在墙体两侧生成穿墙路径。
	#    add_obstruction_faces 在部分 Godot 4.x 版本中不存在，
	#    使用 has_method 做兼容检查；不支持时仅靠地板面片烘焙（墙体不在
	#    add_faces 中故不会成为可行走区域，不影响基本寻路正确性）。
	var wall_faces := PackedVector3Array()
	for wall_key in wall_transforms_by_height:
		var group: Dictionary = wall_transforms_by_height[wall_key]
		var transforms: Array = group.get("transforms", [])
		var size: Vector3 = group.get("size", Vector3(TILE_SIZE, 3.0, DOOR_SURROUND_THICKNESS))
		for t in transforms:
			_append_box_faces(wall_faces, (t as Transform3D).origin, size)
	if source_geometry_data.has_method("add_obstruction_faces"):
		source_geometry_data.add_obstruction_faces(wall_faces, Transform3D.IDENTITY)

	# 4. 从源几何数据烘焙导航网格（同步，不经过 RenderingServer）
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source_geometry_data, Callable())

## 把一个轴对齐地板盒子的顶面（+Y，2 个三角形）追加到 faces 数组。
## 仅取顶面作为可行走面，减少数据量。
func _append_floor_top_face(faces: PackedVector3Array, center: Vector3, size: Vector3) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var p010 := center + Vector3(-hx, hy, -hz)
	var p110 := center + Vector3( hx, hy, -hz)
	var p111 := center + Vector3( hx, hy,  hz)
	var p011 := center + Vector3(-hx, hy,  hz)
	faces.append_array([p010, p110, p111, p010, p111, p011])

func _build_chunked_multi_meshes(base_name: String, transforms: Array, mesh_size: Vector3, material: Material) -> void:
	if transforms.is_empty():
		return
	var chunks := _group_transforms_by_stream_chunk(transforms)
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
		add_child(mm_instance)
		_register_terrain_chunk_node(chunk, mm_instance)

func _build_batched_decor_multi_meshes() -> void:
	var pending_batches := batched_decor_transforms.duplicate()
	batched_decor_transforms.clear()
	for path in pending_batches.keys():
		var root_transforms: Array = pending_batches[path]
		if root_transforms.is_empty():
			continue
		var prefab := load(String(path))
		if not prefab is PackedScene:
			continue
		var template := (prefab as PackedScene).instantiate()
		if template == null:
			continue
		if template.has_method("rebuild"):
			template.rebuild()
		var parts: Array[Dictionary] = []
		if template is Node3D:
			_collect_batched_mesh_parts(template as Node3D, template as Node3D, parts)
		for batch in _build_combined_batched_mesh_parts(parts):
			_build_chunked_mesh_multimeshes(
				"BatchedDecor_%s_%s" % [_decor_batch_name(String(path)), String(batch["name"])],
				root_transforms,
				batch["mesh"] as Mesh,
				batch["material"] as Material
			)
		template.free()

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
		_append_mesh_to_surface(
			batch["surface"] as SurfaceTool,
			part["mesh"] as Mesh,
			part["transform"] as Transform3D
		)
	var result: Array[Dictionary] = []
	for batch in material_batches.values():
		var mesh := (batch["surface"] as SurfaceTool).commit()
		if mesh == null:
			continue
		result.append({
			"name": String(batch["name"]),
			"mesh": mesh,
			"material": batch["material"],
		})
	return result

func _batched_material_key(material: Material) -> String:
	var material_key := "mat:null"
	if material != null:
		material_key = "mat:%d" % material.get_instance_id()
	return material_key

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

func _collect_batched_mesh_parts(root: Node3D, node: Node, result: Array[Dictionary]) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			result.append({
				"name": String(mesh_instance.name),
				"mesh": mesh_instance.mesh,
				"material": mesh_instance.material_override,
				"transform": _node_transform_relative_to(root, mesh_instance),
			})
	for child in node.get_children():
		_collect_batched_mesh_parts(root, child, result)

func _node_transform_relative_to(root: Node3D, node: Node3D) -> Transform3D:
	var relative := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			relative = (current as Node3D).transform * relative
		current = current.get_parent()
	return relative

func _build_chunked_mesh_multimeshes(base_name: String, transforms: Array, mesh: Mesh, material: Material) -> void:
	if transforms.is_empty() or mesh == null:
		return
	var chunks := _group_transforms_by_stream_chunk(transforms)
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
		add_child(mm_instance)
		_register_terrain_chunk_node(chunk, mm_instance)

func _decor_batch_name(path: String) -> String:
	return path.get_file().get_basename().replace(".", "_").replace("-", "_")

func _group_transforms_by_stream_chunk(transforms: Array) -> Dictionary:
	var chunks := {}
	for transform in transforms:
		var t := transform as Transform3D
		var chunk := _world_to_stream_chunk(t.origin)
		if not chunks.has(chunk):
			chunks[chunk] = []
		chunks[chunk].append(t)
	return chunks

## 在墙面上生成火把。
## cell_pos: 相邻地板的格子中心位置
## wall_dir: 墙体方向
## wall_height: 墙体高度（米），决定火把的放置高度
func _spawn_torch_on_wall(cell_pos: Vector3, wall_dir: Vector2i, wall_height: float = 3.0) -> void:
	var torch := TORCH_PREFAB.instantiate()
	const TILE_SIZE := 3.0
	var pos_offset := Vector3(wall_dir.x, 0, wall_dir.y) * (TILE_SIZE / 2.0)
	var clip_offset := -Vector3(wall_dir.x, 0, wall_dir.y) * 0.1
	# 火把高度 = 墙面高度的 45%，下限 0.8m（低通道），上限距天花板 0.3m
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
		
	add_child(torch)
	_ensure_collision_on_instance(torch)
	_configure_scene_object(torch)
	register_streamed_physics_node(torch)
	# 火把距离剔除：火焰为 additive overdraw，远处无光仍绘制纯属浪费。
	# 35m 与火把灯光衰减(omni_range 11 / distance_fade 24→34m)对齐，灯光不可见处火焰也不画。
	_apply_distance_culling(torch, TORCH_VISIBILITY_RANGE_END)

## 按区域返回环境光配置。
## 返回 Dictionary 含：light_energy, light_color, ambient_color, ambient_energy,
##                     fog_enabled, fog_color, fog_density
func _get_zone_ambient_config(zone: int) -> Dictionary:
	match zone:
		0:  # 幽暗地牢 — 阴冷石砌地牢，保留阴影但保证基础可视
			return {
				light_energy = 0.22,
				light_color = Color(0.55, 0.52, 0.48),
				ambient_color = Color(0.18, 0.16, 0.18),
				ambient_energy = 0.28,
				fog_enabled = true,
				fog_color = Color(0.12, 0.10, 0.11),
				fog_density = 0.008,
			}
		1:  # 寂静之森 — 树冠下月光筛落，青绿冷光，无需火把
			return {
				light_energy = 0.15,
				light_color = Color(0.4, 0.6, 0.5),
				ambient_color = Color(0.15, 0.25, 0.2),
				ambient_energy = 0.3,
				fog_enabled = true,
				fog_color = Color(0.1, 0.18, 0.15),
				fog_density = 0.008,
			}
		2:  # 深邃洞窟 — 暗冷紫光，火把提供主要局部对比
			return {
				light_energy = 0.14,
				light_color = Color(0.38, 0.42, 0.58),
				ambient_color = Color(0.10, 0.09, 0.14),
				ambient_energy = 0.20,
				fog_enabled = true,
				fog_color = Color(0.08, 0.07, 0.10),
				fog_density = 0.012,
			}
		3:  # 荒芜墓园 — 阴冷灰蓝，保留雾气但不压黑地面
			return {
				light_energy = 0.16,
				light_color = Color(0.45, 0.50, 0.62),
				ambient_color = Color(0.12, 0.11, 0.16),
				ambient_energy = 0.22,
				fog_enabled = true,
				fog_color = Color(0.10, 0.09, 0.13),
				fog_density = 0.010,
			}
		4:  # 熔岩火山 — 熔岩辉光暖橙，无需火把
			return {
				light_energy = 0.12,
				light_color = Color(0.8, 0.5, 0.2),
				ambient_color = Color(0.15, 0.08, 0.03),
				ambient_energy = 0.25,
				fog_enabled = true,
				fog_color = Color(0.12, 0.06, 0.02),
				fog_density = 0.01,
			}
		5:  # 古代遗迹 — 灵界蓝白辉光，古代魔力弥漫，无需火把
			return {
				light_energy = 0.1,
				light_color = Color(0.5, 0.6, 0.8),
				ambient_color = Color(0.1, 0.12, 0.2),
				ambient_energy = 0.2,
				fog_enabled = true,
				fog_color = Color(0.08, 0.1, 0.18),
				fog_density = 0.008,
			}
		_:  # fallback — 洞窟风格
			return {
				light_energy = 0.02,
				light_color = Color(0.3, 0.35, 0.5),
				ambient_color = Color(0.04, 0.03, 0.06),
				ambient_energy = 0.04,
				fog_enabled = true,
				fog_color = Color(0.05, 0.04, 0.06),
				fog_density = 0.02,
			}

func _pick_weighted(weights: Dictionary) -> String:
	var total_weight := 0
	for key in weights:
		total_weight += weights[key]
		
	var r = randi() % total_weight
	var cumulative_weight := 0
	for key in weights:
		cumulative_weight += weights[key]
		if r < cumulative_weight:
			return key
	return ""

## 为装饰/道具实例应用距离剔除：超过 DECOR_VISIBILITY_RANGE_END 时不再渲染，
## 减少远处散落物的 draw call。地形/墙体等结构几何体不应调用此函数（避免远处穿洞）。
func _apply_distance_culling(node: Node3D, range_end: float = DECOR_VISIBILITY_RANGE_END) -> void:
	if node == null:
		return
	for gi in node.find_children("*", "GeometryInstance3D", true, false):
		var geom := gi as GeometryInstance3D
		geom.visibility_range_end = range_end
		geom.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

func _spawn_random_material(pos: Vector3) -> void:
	# 按当前区域从 ZoneManager 获取散落材料池（替换旧虚构材料）
	var scatter_pool: Dictionary = MATERIALS_CONFIG  # fallback
	var zm: Node = Service.zone_manager()
	if zm != null:
		scatter_pool = zm.get_scatter_materials(dungeon_zone)
	var mat_id = _pick_weighted(scatter_pool)
	if mat_id != "":
		var item = PICKABLE_ITEM_PREFAB.instantiate()
		item.material_id = mat_id
		item.position = pos + Vector3(0, 0.3, 0)
		add_child(item)
		_apply_distance_culling(item)
		register_streamed_physics_node(item)

func _spawn_random_decor(pos: Vector3) -> void:
	var path = _pick_weighted(DECOR_CONFIG)
	if path != "":
		if _spawn_batched_decor(path, Transform3D(Basis.IDENTITY, pos)):
			return
		var prefab = load(path)
		if prefab:
			var instance = prefab.instantiate()
			instance.position = pos
			add_child(instance)
			_apply_distance_culling(instance)
			# 装饰物补全碰撞，并统一标记为场景物体层。
			_ensure_collision_on_instance(instance)
			_configure_scene_object(instance)
			register_streamed_physics_node(instance)

func _spawn_batched_decor(path: String, transform: Transform3D) -> bool:
	if not BATCHED_DECOR_SCENES.has(path):
		return false
	var prefab := load(path)
	if not prefab is PackedScene:
		return false
	var template := (prefab as PackedScene).instantiate()
	if not template is Node3D:
		if template != null:
			template.free()
		return false
	var template_root := template as Node3D
	if template_root.has_method("rebuild"):
		template_root.rebuild()
	var local_bounds := _combined_batched_mesh_aabb(template_root)
	template_root.free()
	if local_bounds.size == Vector3.ZERO:
		return false
	# 把模板本地 AABB 经实例 transform（可能含缩放/旋转）变换到世界空间，
	# 作为碰撞盒尺寸与中心。MultiMesh 也使用同一 transform 作逐实例矩阵，
	# 视觉与碰撞严格对齐（柱子等缩放实例也能正确合批并拥有贴合的碰撞壳）。
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
	add_child(body)
	register_streamed_physics_node(body)
	if not batched_decor_transforms.has(path):
		batched_decor_transforms[path] = []
	(batched_decor_transforms[path] as Array).append(transform)
	return true

func _combined_batched_mesh_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var has_bounds := false
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var aabb := _node_transform_relative_to(root, mesh_instance) * mesh_instance.get_aabb()
		if not has_bounds:
			result = aabb
			has_bounds = true
		else:
			result = result.merge(aabb)
	return result if has_bounds else AABB()

func _rect_center_cell(rect: Rect2i) -> Vector2i:
	return rect.position + Vector2i(rect.size.x / 2, rect.size.y / 2)

func is_start_room_grid_cell(cell: Vector2i) -> bool:
	return _is_start_room_cell(cell)

func _is_start_room_cell(cell: Vector2i) -> bool:
	return layout.room_roles.has("start") and (layout.room_roles["start"] as Rect2i).has_point(cell)

func _is_boss_room_cell(cell: Vector2i) -> bool:
	return layout.room_roles.has("boss") and (layout.room_roles["boss"] as Rect2i).has_point(cell)

func _is_boss_reward_chest_cell(cell: Vector2i) -> bool:
	if layout.room_roles.has("reward") and (layout.room_roles["reward"] as Rect2i).has_point(cell):
		return true
	return _is_boss_room_cell(cell)

func _room_is_start_room(room: Rect2i) -> bool:
	return layout.room_roles.has("start") and room == (layout.room_roles["start"] as Rect2i)
