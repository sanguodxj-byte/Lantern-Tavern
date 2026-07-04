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

func test_expedition_prompt_has_depart_text() -> void:
	var inst: Control = load("res://scenes/ui/expedition_prompt.tscn").instantiate()
	add_child(inst)
	var label: Label = inst.get_node("RingCenter/DepartText")
	assert_object(label).is_not_null()
	assert_str(label.text).is_equal("出发")
	inst.queue_free()

func test_expedition_prompt_script_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/ui/expedition_prompt.gd")).is_true()

func test_expedition_prompt_uses_kick_input() -> void:
	# 按住 F（kick 输入）累积进度
	var script: Resource = load("res://scenes/ui/expedition_prompt.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find('Input.is_action_pressed("kick")') != -1).is_true()

func test_expedition_prompt_routes_to_zone_select() -> void:
	var script: Resource = load("res://scenes/ui/expedition_prompt.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("zone_select.tscn") != -1).is_true()

func test_main_menu_start_routes_to_tavern() -> void:
	var script: Resource = load("res://scenes/ui/main_menu.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find('change_scene_to_file("res://scenes/tavern/tavern.tscn")') != -1) \
		.override_failure_message("主菜单开始游戏未跳转酒馆场景").is_true()

func test_tavern_manager_node_mounts_expedition_prompt() -> void:
	var script: Resource = load("res://scenes/tavern/tavern_manager_node.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("_mount_expedition_prompt") != -1).is_true()
	assert_bool(source.find("expedition_prompt.tscn") != -1).is_true()

func test_tavern_manager_node_day_phase_mounts_prompt() -> void:
	var script: Resource = load("res://scenes/tavern/tavern_manager_node.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("DAY_EXPEDITION") != -1).is_true()
