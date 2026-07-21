extends BaseLevel
class_name ProceduralDungeon

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
const DungeonStreamingConfig := preload("res://scenes/expedition/dungeon_streaming_config.gd")
# 阶段 E 步5：rendering const 迁入 DungeonRenderingConfig，顶 const 已删改读 _rendering_cfg.*
const DungeonRenderingConfig := preload("res://scenes/expedition/dungeon_rendering_config.gd")
const DungeonRuntimeConfig := preload("res://scenes/expedition/dungeon_runtime_config.gd")

# 阶段 E 步4：streaming const 迁入 DungeonStreamingConfig，顶 const 已删改读 _streaming_cfg.*
var _streaming_cfg: DungeonStreamingConfig = DungeonStreamingConfig.default()
var _rendering_cfg: DungeonRenderingConfig = DungeonRenderingConfig.default()
var _runtime_cfg: DungeonRuntimeConfig = DungeonRuntimeConfig.default()
# runtime.spawn_player() 的返回（玩家节点）缓存，供后续清理/引用。
var _player_spawn

# 地形渲染配置已提取至 DungeonTerrainConfig




# 散落装饰/材料的距离剔除阈值（米）：超过该距离不再渲染，减少远处 draw call。
# 结构几何体（地板/墙/天花板）不应用此剔除，避免远处穿洞。

var player_spawn_pos := Vector3.ZERO

## 当前地牢所属区域（BrewingData.Zone 枚举值）。
## 决定宝箱材料掉落池，由关卡入口或 ExpeditionManager 注入。
@export var dungeon_zone: int = 0  # 默认地牢

# 阶段 9 接线：新生产链持有引用（供生产集成测试断言 level.layout / level.build_result / level.streaming_controller）
# 阶段 9 条 2：旧字段 _grid/layout.rooms/layout.room_roles/layout.heights 已退役，统一读 layout.*
var layout: DungeonLayout = null
var build_result: DungeonBuildResult = null
var streaming_controller: DungeonStreamingController = null
var _runtime: DungeonRuntime = null

# 是否生成敌人/掉落物人口。生产默认 true（正常探险会刷怪）。
# 无头集成测试可在 add_child 前置 false：headless 下反复实例化多具蒙皮 rig 敌人
# 会累积 GPU 资源并触发引擎原生崩溃（signal 11，非逻辑错误）。详见 DungeonRuntime.spawn_population_enabled。
var spawn_population_enabled: bool = true

# 可注入的生成种子。生产默认 0 = 随机（DungeonGenerator 自选种子）。
# 无头测试/调试可在 add_child 前置非 0 值，使布局确定可复现
# （需在 add_child 触发 _ready 前设置；instantiate 不调 _ready）。
var generation_seed: int = 0

const TILE_SIZE := 3.0  # 默认地块尺寸；与 DungeonLayout.tile_size 默认值一致。minimap.gd / 测试经此读取。

var _shared_floor_mat: ShaderMaterial = null
var _shared_ceiling_mat: ShaderMaterial = null

# 用于收集 GPU 实例坐标，优化渲染性能
# 墙面按尺寸分组：key=rounded size, value={size, transforms}
# 不同高度/方向的薄墙段需要不同的 mesh 和 tile_repeat，避免整格墙体重合闪烁。
var _exploration_pressure: ExplorationPressure = null
var _expedition_hud: ExpeditionHUD = null
var _combat_hud: CombatHUD = null
var _expedition_finished := false
var _streamed_physics_bodies: Array[PhysicsBody3D] = []  # 阶段 9 条 5 后仅留作注释参考；实际 streaming 路径 controller 持

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
	config.seed = generation_seed  # 0=随机（生产）；非 0 时布局确定可复现（测试/调试）。
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

	# 阶段 9 条 1 步4：builder.build(layout, self) 已产 floor/wall/ceiling/lintel Transform（build_result.*），
	# _build_terrain_geometry 仅推导 player_spawn_pos；几何/装饰/导航由 builder 完成。
	_setup_zone_ambient()
	_build_terrain_geometry(layout.grid)
	# 出生点标记必须在 spawn_player 之前就位：runtime.start() 内部会调 spawn_player()，
	# 而 spawn_player 读取 %PlayerSpawn 的 global_transform 决定落点。若在 start() 之后才
	# 设置标记，玩家会生成在原点（tscn 默认位）而非算出的出生点。
	player_spawn.global_position = player_spawn_pos
	# D 步3：runtime 接管 spawn/HUD/pressure/extraction/music 启动序（转调本类旧路径，下步真迁函数体）
	_runtime = DungeonRuntime.new()
	add_child(_runtime)
	_runtime.configure(layout, build_result, self, streaming_controller, _rendering_cfg, spawn_population_enabled)
	_runtime.start()
	# spawn_player 已由 _runtime.start() 内调（转 procedural.spawn_player）；玩家引用经 GameState.current_player 回读
	_player_spawn = GameState.current_player


func _process(delta: float) -> void:
	var network_manager := Service.network_manager()
	if network_manager != null and network_manager.has_method("tick"):
		network_manager.tick(delta)
	# 阶段 9 接线：streaming 唯一由 DungeonStreamingController 实现（controller 是子 Node，自带 _process 节流）。
	# terrain streaming 注册转调 controller（见 register_streamed_physics_node / register_streamed_visual_node）。
	if streaming_controller == null or not is_instance_valid(streaming_controller):
		return
	# controller._process 自跑节流；本类 _process 仅留作未来 runtime 需要帧驱动时用，现无操作。
	return
func register_streamed_visual_node(node: Node3D) -> void:
	# 阶段 9 条 5：纯转调 DungeonStreamingController，删旧兜底（controller 在 _ready add_child 后永就绪）
	if streaming_controller != null and is_instance_valid(streaming_controller):
		streaming_controller.register_visual_node(node)

func register_streamed_physics_node(node: Node) -> void:
	# 阶段 9 条 5：纯转调 DungeonStreamingController，删旧兜底
	if streaming_controller != null and is_instance_valid(streaming_controller):
		streaming_controller.register_physics_node(node)





## D 步9：get_combat_hud 已真迁入 DungeonRuntime._get_combat_hud。
func _get_combat_hud() -> CombatHUD:
	if _runtime != null and is_instance_valid(_runtime):
		return _runtime._get_combat_hud()
	return null




## D 步9：on_door_pressure_action 已真迁入 DungeonRuntime。
func _on_door_pressure_action(action: String) -> void:
	if _runtime != null and is_instance_valid(_runtime):
		_runtime.on_door_pressure_action(action)

func _on_expedition_overtime(_snapshot: Dictionary) -> void:
	if _runtime != null and is_instance_valid(_runtime):
		_runtime.on_expedition_overtime(_snapshot)
		return
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
	# terrain/multi/collision/door/hazard/chest/decor/nav 已由 DungeonSceneBuilder 接管。
	# 这里仅推导 player_spawn_pos（runtime.spawn_player 依赖）。
	# 算法唯一来源：DungeonLayout.calc_player_spawn_pos()（与 DungeonSessionController 共用，消除漂移）。
	if layout != null and not layout.is_empty():
		player_spawn_pos = layout.calc_player_spawn_pos()
	else:
		player_spawn_pos = Vector3(0, 0.5, 0)

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

## D 步8：finish_expedition + _settle_extraction_loot 已真迁入 DungeonRuntime，本类旧体已删。
func _finish_expedition(player: Player, voluntary: bool) -> void:
	if _runtime != null and is_instance_valid(_runtime):
		_runtime.finish_expedition(player, voluntary)

## D 步8：settle_extraction_loot 已真迁入 DungeonRuntime._settle_extraction_loot，本类旧体已删。
func _settle_extraction_loot(player: Player) -> void:
	if _runtime != null and is_instance_valid(_runtime):
		_runtime._settle_extraction_loot(player)

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

func is_start_room_grid_cell(cell: Vector2i) -> bool:
	return _is_start_room_cell(cell)

func _is_start_room_cell(cell: Vector2i) -> bool:
	return layout.room_roles.has("start") and (layout.room_roles["start"] as Rect2i).has_point(cell)
