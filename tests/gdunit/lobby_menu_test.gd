extends GdUnitTestSuite

const LOBBY_MENU_PATH := "res://scenes/ui/lobby_menu.tscn"

func test_lobby_menu_scene_loads() -> void:
	var scene: PackedScene = load(LOBBY_MENU_PATH)
	assert_object(scene).is_not_null()
	var menu: Control = scene.instantiate()
	assert_object(menu).is_not_null()
	menu.free()

func test_lobby_menu_layout_structure() -> void:
	var menu: Control = load(LOBBY_MENU_PATH).instantiate()
	add_child(menu)
	
	# 检查 CenterContainer 节点是否存在且铺满全屏
	var center_container: CenterContainer = menu.get_node_or_null("CenterContainer")
	assert_object(center_container).is_not_null()
	assert_float(center_container.anchor_left).is_equal(0.0)
	assert_float(center_container.anchor_top).is_equal(0.0)
	assert_float(center_container.anchor_right).is_equal(1.0)
	assert_float(center_container.anchor_bottom).is_equal(1.0)
	assert_int(center_container.grow_horizontal).is_equal(Control.GROW_DIRECTION_BOTH)
	assert_int(center_container.grow_vertical).is_equal(Control.GROW_DIRECTION_BOTH)
	
	# 检查 Center (VBoxContainer) 是否是 CenterContainer 的子节点
	var center: VBoxContainer = center_container.get_node_or_null("Center")
	assert_object(center).is_not_null()
	assert_float(center.custom_minimum_size.x).is_equal(520.0)
	
	# 检查重要的子节点是否挂载在 Center 下
	var title: Label = center.get_node_or_null("Title")
	assert_object(title).is_not_null()
	
	var host_panel: PanelContainer = center.get_node_or_null("HostPanel")
	assert_object(host_panel).is_not_null()
	
	var join_panel: PanelContainer = center.get_node_or_null("JoinPanel")
	assert_object(join_panel).is_not_null()
	
	var lobby_panel: PanelContainer = center.get_node_or_null("LobbyPanel")
	assert_object(lobby_panel).is_not_null()
	
	var status_label: Label = center.get_node_or_null("StatusLabel")
	assert_object(status_label).is_not_null()
	
	# 检查左上返回按钮
	var back_btn: Button = menu.get_node_or_null("BackBtn")
	assert_object(back_btn).is_not_null()
	assert_int(back_btn.anchors_preset).is_equal(Control.PRESET_TOP_LEFT)

	remove_child(menu)
	menu.free()
