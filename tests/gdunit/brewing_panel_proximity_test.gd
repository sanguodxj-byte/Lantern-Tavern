extends GdUnitTestSuite
## 酒馆经营 HUD 入口测试
## 决策 G3（审查 0856 P0-1）：tavern_ui.tscn 已移除 BrewingPanel 节点，
## 酿造操作全部走 3D 酿造间链路（BrewFlowSystem），HUD 仅展示经营信息。

func test_brewing_panel_removed_from_tavern_ui() -> void:
	var inst: Control = load("res://scenes/ui/tavern_ui.tscn").instantiate()
	add_child(inst)
	# 旧 BrewingPanel 节点已从生产 HUD 移除
	assert_object(inst.get_node_or_null("BrewingPanel")).is_null()
	inst.queue_free()

func test_brewing_panel_instance_removed_from_tavern_ui() -> void:
	var inst: Control = load("res://scenes/ui/tavern_ui.tscn").instantiate()
	add_child(inst)
	assert_object(inst.get_node_or_null("BrewingPanel/BrewingPanelInstance")).is_null()
	inst.queue_free()

func test_bar_interaction_toggles_tavern_hud() -> void:
	var script: GDScript = load("res://scenes/tavern/tavern_manager_node.gd")
	var source := script.source_code
	assert_bool(source.find("toggle_tavern_hud") != -1).is_true()
	assert_bool(source.find("BarTopBody") != -1).is_true()
	assert_bool(source.find("TAVERN_BAR_INTERACTION_SCRIPT") != -1).is_true()
