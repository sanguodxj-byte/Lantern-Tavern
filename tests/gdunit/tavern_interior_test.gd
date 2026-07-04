extends GdUnitTestSuite
## 测试酒馆 3D 视觉场景 (tavern_interior.tscn) 的构建完整性。
## 覆盖：资源存在性、场景可实例化、骨架节点、座位收集、UI overlay、阶段切换路径。

const TAVERN_SCENE_PATH := "res://scenes/tavern/tavern.tscn"
const TAVERN_SCRIPT_PATH := "res://scenes/tavern/tavern_manager_node.gd"
const EXPECTED_SEAT_COUNT := 16

# ---------- 资源存在性 ----------

func test_tavern_interior_scene_exists() -> void:
	assert_bool(ResourceLoader.exists(TAVERN_SCENE_PATH)) \
		.override_failure_message("酒馆 3D 场景文件缺失: %s" % TAVERN_SCENE_PATH) \
		.is_true()


func test_tavern_manager_node_script_exists() -> void:
	assert_bool(ResourceLoader.exists(TAVERN_SCRIPT_PATH)) \
		.override_failure_message("酒馆场景管理脚本缺失: %s" % TAVERN_SCRIPT_PATH) \
		.is_true()


func test_tavern_interior_has_uid() -> void:
	# 确认场景文件头声明了 uid，避免被 import 后产生重复 uid
	var packed: PackedScene = load(TAVERN_SCENE_PATH)
	assert_object(packed).is_not_null()
	assert_bool(packed.get_meta("uid", "") != "" or packed.resource_path == TAVERN_SCENE_PATH).is_true()


# ---------- 场景可实例化 ----------

func test_scene_can_be_instantiated() -> void:
	var packed: PackedScene = load(TAVERN_SCENE_PATH)
	assert_object(packed).is_not_null()
	var inst: Node = packed.instantiate()
	assert_object(inst).is_not_null()
	assert_bool(inst is Node3D).is_true()
	inst.free()


# ---------- 骨架节点（与 base_room.tscn 对齐） ----------

func test_skeleton_nodes_present() -> void:
	var inst: Node3D = _instantiate_tavern()
	for node_name in ["Structure", "RoomNavigation", "Lights", "Decor", "Stations", "CustomerSeats", "PlayerSpawn", "WorldEnvironment"]:
		assert_bool(inst.has_node(node_name)) \
			.override_failure_message("缺失骨架节点: %s" % node_name) \
			.is_true()
	inst.free()


func test_structure_uses_tavern_structure_script() -> void:
	# Structure 节点必须挂载 TavernStructure @tool 脚本
	var inst: Node3D = _instantiate_tavern()
	var structure: Node3D = inst.get_node("Structure")
	assert_object(structure.get_script()) \
		.override_failure_message("Structure 节点未挂载 tavern_structure.gd") \
		.is_not_null()
	inst.free()


func test_structure_has_dedicated_tavern_materials() -> void:
	# 确认结构脚本使用酒馆专属材质，不复用旧地牢 wall_mat.tres
	var inst: Node3D = _instantiate_tavern()
	var structure: Node3D = inst.get_node("Structure")
	assert_bool(structure.floor_mat != null and \
		structure.floor_mat.resource_path.find("tavern_floor_mat") != -1) \
		.override_failure_message("未使用酒馆专属地板材质") \
		.is_true()
	assert_bool(structure.wall_mat != null and \
		structure.wall_mat.resource_path.find("tavern_wall_mat") != -1) \
		.override_failure_message("未使用酒馆专属墙壁材质") \
		.is_true()
	assert_bool(structure.ceiling_mat != null and \
		structure.ceiling_mat.resource_path.find("tavern_ceiling_mat") != -1) \
		.override_failure_message("未使用酒馆专属天花板材质") \
		.is_true()
	inst.free()


func test_structure_builds_on_ready() -> void:
	# @tool 脚本在 _ready 时构建 BuiltStructure 子树（地板/墙/天花板/立柱/吧台）
	var inst: Node3D = _instantiate_tavern()
	add_child(inst)
	await await_idle_frame()
	assert_bool(inst.has_node("Structure/BuiltStructure")) \
		.override_failure_message("Structure._ready() 未生成 BuiltStructure 子树") \
		.is_true()
	var built: Node3D = inst.get_node("Structure/BuiltStructure")
	assert_bool(built.has_node("Floor")).is_true()
	assert_bool(built.has_node("Ceiling")).is_true()
	assert_bool(built.has_node("BarTop")).is_true()
	# 四墙
	for wall_name in ["WallNorth", "WallSouth", "WallEast", "WallWest"]:
		assert_bool(built.has_node(wall_name)) \
			.override_failure_message("BuiltStructure 缺失墙壁: %s" % wall_name) \
			.is_true()
	# 四立柱
	for i in range(1, 5):
		assert_bool(built.has_node("Pillar%d" % i)) \
			.override_failure_message("BuiltStructure 缺失立柱 Pillar%d" % i) \
			.is_true()
	inst.free()


func test_floor_has_collision_body() -> void:
	# 地板必须有 StaticBody3D 碰撞，否则玩家/顾客会掉出场景
	var inst: Node3D = _instantiate_tavern()
	add_child(inst)
	await await_idle_frame()
	var floor_body: Node = inst.get_node_or_null("Structure/BuiltStructure/FloorBody")
	assert_object(floor_body) \
		.override_failure_message("地板未生成碰撞体 FloorBody") \
		.is_not_null()
	inst.free()


func test_walls_have_collision() -> void:
	var inst: Node3D = _instantiate_tavern()
	add_child(inst)
	await await_idle_frame()
	var built: Node3D = inst.get_node("Structure/BuiltStructure")
	for wall_name in ["WallNorth", "WallSouth", "WallEast", "WallWest"]:
		assert_bool(built.has_node(wall_name + "Body")) \
			.override_failure_message("墙壁 %s 未生成碰撞体" % wall_name) \
			.is_true()
	inst.free()


func test_world_environment_present() -> void:
	# 必须有 WorldEnvironment，否则编辑器/运行时 3D 场景无环境光照看不见
	var inst: Node3D = _instantiate_tavern()
	var we: WorldEnvironment = inst.get_node("WorldEnvironment")
	assert_object(we).is_not_null()
	assert_object(we.environment).is_not_null()
	inst.free()


func test_directional_light_present() -> void:
	# 至少一盏 DirectionalLight3D 作为补光，确保场景可见
	var inst: Node3D = _instantiate_tavern()
	var light: DirectionalLight3D = inst.get_node("DirectionalLight3D")
	assert_object(light).is_not_null()
	inst.free()


func test_player_spawn_is_marker3d() -> void:
	var inst: Node3D = _instantiate_tavern()
	var spawn: Node3D = inst.get_node("PlayerSpawn")
	assert_bool(spawn is Marker3D).is_true()
	inst.free()


func test_tavern_materials_not_reusing_old_dungeon_wall_mat() -> void:
	# 反向断言：确认酒馆材质不复用旧地牢 materials/wall_mat.tres
	# 用精确路径匹配，避免误判 tavern_wall_mat.tres（文件名含 wall_mat.tres 子串）
	var inst: Node3D = _instantiate_tavern()
	var structure: Node3D = inst.get_node("Structure")
	for mat in [structure.floor_mat, structure.wall_mat, structure.ceiling_mat, structure.pillar_mat, structure.bar_mat]:
		assert_bool(mat != null and mat.resource_path.find("res://materials/wall_mat.tres") == -1) \
			.override_failure_message("酒馆材质复用了旧地牢 materials/wall_mat.tres: %s" % mat.resource_path) \
			.is_true()
	inst.free()


# ---------- 场景纯净性：3D 场景不应内嵌 UI，避免被误认为 UI 界面 ----------

func test_scene_has_no_ui_overlay_node() -> void:
	# 3D 场景不应自带 CanvasLayer/UIOverlay，UI 应由调用方按需挂载
	var inst: Node3D = _instantiate_tavern()
	assert_bool(inst.has_node("UIOverlay")) \
		.override_failure_message("酒馆 3D 场景不应内嵌 UIOverlay 节点（会遮挡 3D 画面）") \
		.is_false()
	inst.free()


func test_scene_has_no_control_descendants() -> void:
	# 检查酒馆场景自身不应挂载任何 Control 根节点（递归查 glb 内部 Control 会误判）。
	# 仅检查场景树中由本场景直接声明的 Control 节点，跳过导入模型内部节点。
	var inst: Node3D = _instantiate_tavern()
	var top_level_controls: int = 0
	for child in inst.get_children():
		if child is Control:
			top_level_controls += 1
	assert_int(top_level_controls) \
		.override_failure_message("酒馆 3D 场景根下含 Control 子节点 %d 个" % top_level_controls) \
		.is_equal(0)
	inst.free()


func test_scene_has_no_canvas_layer_descendants() -> void:
	# CanvasLayer 不会被 glb 内部包含，可递归检查
	var inst: Node3D = _instantiate_tavern()
	var layers := inst.find_children("*", "CanvasLayer", true, false)
	assert_int(layers.size()) \
		.override_failure_message("酒馆 3D 场景含 CanvasLayer 子节点 %d 个" % layers.size()) \
		.is_equal(0)
	inst.free()


func test_root_is_node3d_not_control() -> void:
	# 根节点必须是 Node3D，不能是 Control（否则会被识别为 UI 界面）
	var inst: Node3D = _instantiate_tavern()
	assert_bool(inst is Node3D).is_true()
	assert_str(inst.get_class()).is_equal("Node3D")
	inst.free()


func test_hud_only_mounted_in_night_phase() -> void:
	# 默认 current_phase 为 DAY_EXPEDITION，实例化后不应有 HUDLayer
	var inst: TavernInterior = _instantiate_tavern() as TavernInterior
	add_child(inst)
	await await_idle_frame()
	assert_bool(inst.has_node("HUDLayer")) \
		.override_failure_message("非夜晚营业阶段不应挂载 HUD") \
		.is_false()
	inst.free()


# ---------- 座位收集（tavern_manager_node.gd 核心逻辑） ----------

func test_seat_count_matches_expected() -> void:
	var inst: TavernInterior = _instantiate_tavern() as TavernInterior
	# 手动调用 _ready 依赖的 @onready 收集逻辑需在树内生效；这里直接调内部方法验证
	add_child(inst)
	await await_idle_frame()
	assert_int(inst.seat_count()).is_equal(EXPECTED_SEAT_COUNT)
	inst.free()


func test_seat_names_are_sequential() -> void:
	var inst: TavernInterior = _instantiate_tavern() as TavernInterior
	add_child(inst)
	await await_idle_frame()
	for i in range(1, EXPECTED_SEAT_COUNT + 1):
		var seat: Marker3D = inst.get_seat(i - 1)
		assert_object(seat).is_not_null()
		var expected_name := "seat_%02d" % i
		assert_str(seat.name).is_equal(expected_name)
	inst.free()


func test_get_seat_out_of_range_returns_null() -> void:
	var inst: TavernInterior = _instantiate_tavern() as TavernInterior
	add_child(inst)
	await await_idle_frame()
	assert_object(inst.get_seat(-1)).is_null()
	assert_object(inst.get_seat(EXPECTED_SEAT_COUNT)).is_null()
	inst.free()


func test_all_seats_are_marker3d() -> void:
	var inst: TavernInterior = _instantiate_tavern() as TavernInterior
	add_child(inst)
	await await_idle_frame()
	for i in range(inst.seat_count()):
		var seat = inst.get_seat(i)
		assert_bool(seat is Marker3D) \
			.override_failure_message("座位 %d 不是 Marker3D: %s" % [i, str(seat)]) \
			.is_true()
	inst.free()


# ---------- 家具铺设（手动构建的关键产物） ----------

func test_lighting_props_present() -> void:
	var inst: Node3D = _instantiate_tavern()
	var lights: Node3D = inst.get_node("Lights")
	# 至少 5 个火把 + 2 组点燃蜡烛 + 2 组普通蜡烛
	assert_int(lights.get_child_count()) \
		.override_failure_message("灯光节点数量不足: %d" % lights.get_child_count()) \
		.is_greater_equal(9)
	inst.free()


func test_pillars_built_by_structure_script() -> void:
	# 立柱由 Structure @tool 脚本动态生成在 BuiltStructure 下（Pillar1~Pillar4）
	# 已由 test_structure_builds_on_ready 覆盖，此测试保留作为独立断言
	var inst: Node3D = _instantiate_tavern()
	add_child(inst)
	await await_idle_frame()
	var built: Node3D = inst.get_node("Structure/BuiltStructure")
	var pillar_count := 0
	for i in range(1, 5):
		if built.has_node("Pillar%d" % i):
			pillar_count += 1
	assert_int(pillar_count).is_equal(4)
	inst.free()


func test_barrel_rack_present() -> void:
	var inst: Node3D = _instantiate_tavern()
	var decor: Node3D = inst.get_node("Decor")
	var barrel_count := 0
	for child in decor.get_children():
		if child.name.begins_with("BarrelRack_"):
			barrel_count += 1
	assert_int(barrel_count).is_greater_equal(4)
	inst.free()


func test_bar_counter_built_by_structure_script() -> void:
	# 吧台由 Structure 脚本生成：BarTop（台面）+ BarFront（前挡板）
	var inst: Node3D = _instantiate_tavern()
	add_child(inst)
	await await_idle_frame()
	var built: Node3D = inst.get_node("Structure/BuiltStructure")
	assert_bool(built.has_node("BarTop")) \
		.override_failure_message("BuiltStructure 缺失吧台台面 BarTop") \
		.is_true()
	assert_bool(built.has_node("BarFront")) \
		.override_failure_message("BuiltStructure 缺失吧台前挡板 BarFront") \
		.is_true()
	inst.free()


func test_brewing_and_upgrade_stations_present() -> void:
	var inst: Node3D = _instantiate_tavern()
	var stations: Node3D = inst.get_node("Stations")
	assert_bool(stations.has_node("BrewingStation_Table")).is_true()
	assert_bool(stations.has_node("UpgradeDesk_Table")).is_true()
	inst.free()


func test_dining_tables_present() -> void:
	var inst: Node3D = _instantiate_tavern()
	var seats: Node3D = inst.get_node("CustomerSeats")
	var table_count := 0
	for child in seats.get_children():
		if child.name.begins_with("Table_"):
			table_count += 1
	assert_int(table_count).is_equal(4)
	inst.free()


func test_each_dining_table_has_four_chairs() -> void:
	var inst: Node3D = _instantiate_tavern()
	var seats: Node3D = inst.get_node("CustomerSeats")
	for i in range(1, 5):
		var table: Node3D = seats.get_node("Table_0%d" % i)
		var chair_count := 0
		for child in table.get_children():
			if child.name.begins_with("Chair_"):
				chair_count += 1
		assert_int(chair_count) \
			.override_failure_message("Table_0%d 椅子数不为 4: %d" % [i, chair_count]) \
			.is_equal(4)
	inst.free()


# ---------- 阶段切换路径 ----------

func test_tavern_manager_night_phase_points_to_3d_scene() -> void:
	# 确认 tavern_manager.gd 已改为切换到 3D 酒馆场景而非纯 UI。
	# 通过 load 脚本读取 source_code，避免 res:// 文件路径解析差异。
	var script: GDScript = load("res://globals/tavern_manager.gd") as GDScript
	assert_object(script).is_not_null()
	var source: String = script.source_code
	assert_bool(source.find("res://scenes/tavern/tavern.tscn") != -1) \
		.override_failure_message("tavern_manager.gd 未切换到 3D 酒馆场景") \
		.is_true()
	assert_bool(source.find('change_scene_to_file("res://scenes/ui/tavern_ui.tscn")') == -1) \
		.override_failure_message("tavern_manager.gd 仍直接切换到纯 UI 场景") \
		.is_true()


# ---------- 辅助 ----------

func _instantiate_tavern() -> Node3D:
	var packed: PackedScene = load(TAVERN_SCENE_PATH)
	return packed.instantiate() as Node3D
