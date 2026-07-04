extends GdUnitTestSuite
## 酿酒面板 UI 场景节点结构测试
## 验证 brewing_panel.tscn 7 个节点齐全 + brewing_panel.gd 节点查找正确

const BP_SCENE_PATH := "res://scenes/tavern/brewing_panel.tscn"

func test_brewing_panel_scene_loads() -> void:
	var scene: PackedScene = load(BP_SCENE_PATH)
	assert_object(scene).is_not_null()

func test_brewing_panel_scene_has_7_required_nodes() -> void:
	var scene: PackedScene = load(BP_SCENE_PATH)
	var inst: Control = scene.instantiate()
	add_child(inst)
	# 7 个必需节点
	assert_object(inst.get_node_or_null("KegStatusList")).is_not_null()
	assert_object(inst.get_node_or_null("MaterialGrid")).is_not_null()
	assert_object(inst.get_node_or_null("SelectedIngredientsLabel")).is_not_null()
	assert_object(inst.get_node_or_null("ButtonRow/BrewButton")).is_not_null()
	assert_object(inst.get_node_or_null("ButtonRow/OpenKegButton")).is_not_null()
	assert_object(inst.get_node_or_null("ButtonRow/SealAgingButton")).is_not_null()
	assert_object(inst.get_node_or_null("StatusLabel")).is_not_null()
	inst.queue_free()

func test_brewing_panel_script_finds_all_nodes() -> void:
	var scene: PackedScene = load(BP_SCENE_PATH)
	var inst: Control = scene.instantiate()
	add_child(inst)
	# _ready 已调用 _find_ui_nodes，7 个引用应全部非 null
	assert_object(inst.keg_status_list).is_not_null()
	assert_object(inst.material_grid).is_not_null()
	assert_object(inst.selected_ingredients_label).is_not_null()
	assert_object(inst.brew_button).is_not_null()
	assert_object(inst.open_keg_button).is_not_null()
	assert_object(inst.seal_aging_button).is_not_null()
	assert_object(inst.status_label).is_not_null()
	inst.queue_free()

func test_brewing_panel_buttons_initial_state() -> void:
	var scene: PackedScene = load(BP_SCENE_PATH)
	var inst: Control = scene.instantiate()
	add_child(inst)
	# 下料按钮初始可点击（有空桶时）
	assert_bool(inst.brew_button.disabled).is_false()
	# 开缸/陈酿按钮初始禁用（无选中桶位）
	assert_bool(inst.open_keg_button.disabled).is_true()
	assert_bool(inst.seal_aging_button.disabled).is_true()
	inst.queue_free()

func test_brewing_panel_keg_status_list_populates() -> void:
	var scene: PackedScene = load(BP_SCENE_PATH)
	var inst: Control = scene.instantiate()
	add_child(inst)
	# _ready 已调 _refresh_all，KegStatusList 应有内容
	# FermentationSystem autoload 默认 setup_kegs(1)，应有 1 行
	assert_bool(inst.keg_status_list.item_count > 0).is_true()
	inst.queue_free()

func test_brewing_panel_material_grid_populates() -> void:
	# 设置库存后刷新
	var tm: Node = Engine.get_main_loop().root.get_node_or_null("TavernManager")
	var old_inv: Dictionary = {}
	if tm and "materials_inventory" in tm:
		old_inv = tm.materials_inventory.duplicate()
		tm.materials_inventory = {"blackberry": 2, "glowshroom": 1}
	var scene: PackedScene = load(BP_SCENE_PATH)
	var inst: Control = scene.instantiate()
	add_child(inst)
	inst._refresh_material_grid()
	assert_bool(inst.material_grid.item_count > 0).is_true()
	inst.queue_free()
	# 恢复库存
	if tm:
		tm.materials_inventory = old_inv

func test_tavern_ui_loads_with_brewing_panel_instance() -> void:
	var scene: PackedScene = load("res://scenes/ui/tavern_ui.tscn")
	assert_object(scene).is_not_null()
	var inst: Control = scene.instantiate()
	add_child(inst)
	# BrewingPanel 下应有 BrewingPanelInstance
	var bp_inst: Node = inst.get_node_or_null("BrewingPanel/BrewingPanelInstance")
	assert_object(bp_inst).is_not_null()
	inst.queue_free()
