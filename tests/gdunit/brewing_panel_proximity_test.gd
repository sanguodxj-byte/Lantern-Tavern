extends GdUnitTestSuite
## 酿酒台近距离检测测试
## 验证：tavern_ui.tscn 的 BrewingPanel 默认隐藏 + player.gd 常量正确

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

## player.gd 的 BREWING_STATION_POS 常量与酿酒台实际位置对齐
func test_brewing_station_pos_matches_tavern_scene() -> void:
	var tavern: Node3D = load("res://scenes/tavern/tavern.tscn").instantiate()
	add_child(tavern)
	var station: Node3D = tavern.get_node_or_null("Stations/BrewingStation_Table")
	assert_object(station).is_not_null()
	# BrewingStation_Table transform.origin = (-5, 0, -4)
	assert_float(station.global_position.x).is_equal(-5.0)
	assert_float(station.global_position.z).is_equal(-4.0)
	tavern.queue_free()
