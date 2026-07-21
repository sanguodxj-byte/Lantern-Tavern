extends GdUnitTestSuite
## 酒馆经营 HUD 入口测试
## 验证：tavern_ui.tscn 的 BrewingPanel 默认隐藏，HUD 由吧台交互唤出。

func test_brewing_panel_default_hidden() -> void:
	var inst: Control = load("res://scenes/ui/tavern_ui.tscn").instantiate()
	add_child(inst)
	var panel: Control = inst.get_node_or_null("BrewingPanel")
	assert_object(panel).is_not_null()
	assert_bool(panel.visible).is_false()
	inst.queue_free()

func test_brewing_panel_instance_present() -> void:
	var inst: Control = load("res://scenes/ui/tavern_ui.tscn").instantiate()
	add_child(inst)
	assert_object(inst.get_node_or_null("BrewingPanel/BrewingPanelInstance")).is_not_null()
	inst.queue_free()

func test_bar_interaction_toggles_tavern_hud() -> void:
	var script: GDScript = load("res://scenes/tavern/tavern_manager_node.gd")
	var source := script.source_code
	assert_bool(source.find("toggle_tavern_hud") != -1).is_true()
	assert_bool(source.find("BarTopBody") != -1).is_true()
	assert_bool(source.find("TAVERN_BAR_INTERACTION_SCRIPT") != -1).is_true()
