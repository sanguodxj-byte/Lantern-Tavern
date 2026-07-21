extends GdUnitTestSuite
## 出发探险提示测试
## 验证：场景加载 + 环形进度条 + 出发文字 + 主菜单流程改酒馆

func test_expedition_prompt_scene_loads() -> void:
	var scene: PackedScene = load("res://scenes/ui/expedition_prompt.tscn")
	assert_object(scene).is_not_null()

func test_expedition_prompt_has_ring_progress() -> void:
	var inst: Control = load("res://scenes/ui/expedition_prompt.tscn").instantiate()
	add_child(inst)
	assert_object(inst.get_node_or_null("RingCenter/RingProgress")).is_not_null()
	assert_str(inst.get_node("RingCenter/RingProgress").get_class()).is_equal("TextureProgressBar")
	inst.queue_free()

func test_ring_texture_generated_on_ready() -> void:
	var inst: Control = load("res://scenes/ui/expedition_prompt.tscn").instantiate()
	add_child(inst)
	# _ready() 后纹理应被程序化生成，不再是 null
	assert_object(inst.ring.texture_under).is_not_null()
	assert_object(inst.ring.texture_progress).is_not_null()
	# 纹理尺寸应为 128x128
	assert_int(inst.ring.texture_under.get_width()).is_equal(128)
	assert_int(inst.ring.texture_under.get_height()).is_equal(128)
	inst.queue_free()

func test_ring_texture_is_circular_not_square() -> void:
	var inst: Control = load("res://scenes/ui/expedition_prompt.tscn").instantiate()
	add_child(inst)
	# 取纹理中心行，验证角茒位置透明、中间位置不透明
	var tex := inst.ring.texture_under as ImageTexture
	assert_object(tex).is_not_null()
	var image := tex.get_image()
	assert_object(image).is_not_null()
	var size := image.get_width()
	# 四个角（接近 0,0 / 0,max / max,0 / max,max）应透明
	assert_float(image.get_pixel(2, 2).a).is_equal_approx(0.0, 0.1)
	assert_float(image.get_pixel(size - 3, 2).a).is_equal_approx(0.0, 0.1)
	assert_float(image.get_pixel(2, size - 3).a).is_equal_approx(0.0, 0.1)
	assert_float(image.get_pixel(size - 3, size - 3).a).is_equal_approx(0.0, 0.1)
	# 中心点（内孔）也应透明
	assert_float(image.get_pixel(size / 2, size / 2).a).is_equal_approx(0.0, 0.1)
	# 环形带中间位置（顶部、底部、左、右）应不透明
	# 环形带中间半径 = (outer_r + inner_r) / 2
	var inner_r: float = inst.RING_OUTER_RADIUS - inst.RING_THICKNESS
	var mid_radius := int((inst.RING_OUTER_RADIUS + inner_r) / 2.0)
	var c := size / 2
	assert_float(image.get_pixel(c, c - mid_radius).a).is_greater(0.5)
	assert_float(image.get_pixel(c, c + mid_radius).a).is_greater(0.5)
	assert_float(image.get_pixel(c - mid_radius, c).a).is_greater(0.5)
	assert_float(image.get_pixel(c + mid_radius, c).a).is_greater(0.5)
	inst.queue_free()

func test_ring_radial_initial_angle_from_top() -> void:
	var inst: Control = load("res://scenes/ui/expedition_prompt.tscn").instantiate()
	add_child(inst)
	# radial_initial_angle 应为 270 度（从顶部开始，Godot 将 -90 规范化为 270）
	assert_float(inst.ring.radial_initial_angle).is_equal_approx(270.0, 0.1)
	inst.queue_free()

func test_expedition_prompt_has_depart_text() -> void:
	var inst: Control = load("res://scenes/ui/expedition_prompt.tscn").instantiate()
	add_child(inst)
	var label: Label = inst.get_node("RingCenter/DepartText")
	assert_object(label).is_not_null()
	assert_str(label.text).is_equal("出发")
	inst.queue_free()

func test_expedition_prompt_script_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/ui/expedition_prompt.gd")).is_true()

func test_expedition_prompt_uses_depart_input() -> void:
	# 出发使用独立输入，F/G 保留给技能栏
	var script: Resource = load("res://scenes/ui/expedition_prompt.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find('Input.is_action_pressed(DEPART_ACTION)') != -1).is_true()
	assert_bool(source.find('DEPART_ACTION := "depart"') != -1).is_true()
	assert_bool(source.find('Input.is_action_pressed("kick")') == -1) \
		.override_failure_message("出发提示不应再占用 F/kick，F 是技能栏动作槽").is_true()

func test_depart_input_action_registered() -> void:
	assert_bool(InputMap.has_action("depart")).is_true()

func test_expedition_prompt_routes_to_zone_select() -> void:
	var script: Resource = load("res://scenes/ui/expedition_prompt.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("zone_select.tscn") != -1).is_true()
	assert_bool(source.find("open_zone_select") != -1) \
		.override_failure_message("出发提示应优先通过 World 打开区域选择 overlay").is_true()

func test_main_menu_start_routes_to_tavern() -> void:
	var script: Resource = load("res://scenes/ui/main_menu.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("start_new_game") != -1) \
		.override_failure_message("主菜单开始游戏未通过 TavernManager 进入酒馆夜晚阶段").is_true()

func test_tavern_manager_start_new_game_enters_night_tavern() -> void:
	var script: Resource = load("res://globals/tavern/tavern_manager.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("func start_new_game") != -1).is_true()
	assert_bool(source.find("current_phase = Phase.NIGHT_TAVERN") != -1) \
		.override_failure_message("开始游戏未设置 NIGHT_TAVERN，Tab 酒馆装备面板会被阶段判断挡住").is_true()
	assert_bool(source.find("res://scenes/world/world.tscn") != -1) \
		.override_failure_message("开始游戏应进入 World 根场景，由 World 加载 3D 酒馆").is_true()
	assert_bool(source.find('change_scene_to_file("res://scenes/tavern/tavern.tscn")') == -1) \
		.override_failure_message("开始游戏不应直接切酒馆子场景").is_true()

func test_tavern_manager_node_mounts_expedition_prompt() -> void:
	var script: Resource = load("res://scenes/tavern/tavern_manager_node.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("_mount_expedition_prompt") != -1).is_true()
	assert_bool(source.find("expedition_prompt.tscn") != -1).is_true()

func test_tavern_manager_node_day_phase_mounts_prompt() -> void:
	var script: Resource = load("res://scenes/tavern/tavern_manager_node.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("DAY_EXPEDITION") != -1).is_true()

func test_expedition_prompt_layout_and_pixel_perfect() -> void:
	var inst: Control = load("res://scenes/ui/expedition_prompt.tscn").instantiate()
	add_child(inst)
	var ring_center: Control = inst.get_node("RingCenter")
	var ring_progress: TextureProgressBar = inst.get_node("RingCenter/RingProgress")
	var depart_text: Label = inst.get_node("RingCenter/DepartText")
	
	# 检查 RingCenter 的尺寸是否为 128x128 以保证与生成的 128x128 纹理 1:1 对齐
	assert_float(ring_center.size.x).is_equal_approx(128.0, 0.1)
	assert_float(ring_center.size.y).is_equal_approx(128.0, 0.1)
	
	# 检查 RingProgress 纹理过滤模式是否为最近邻 (TEXTURE_FILTER_NEAREST = 1)
	assert_int(ring_progress.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_NEAREST)
	
	# 确保 DepartText 是居中对齐的
	assert_int(depart_text.horizontal_alignment).is_equal(HORIZONTAL_ALIGNMENT_CENTER)
	assert_int(depart_text.vertical_alignment).is_equal(VERTICAL_ALIGNMENT_CENTER)
	
	inst.queue_free()
