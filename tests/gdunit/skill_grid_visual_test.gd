extends GdUnitTestSuite

const EQUIPMENT_SCENE := preload("res://scenes/ui/tavern_equipment_panel.tscn")

func test_available_skills_is_a_two_column_icon_grid() -> void:
	var panel := EQUIPMENT_SCENE.instantiate()
	var list := panel.get_node("PanelContainer/VBoxContainer/MainLayout/RightTabs/技能/SkillLayout/AvailableSkillsPanel/AvailableSkillsBox/AvailableSkillsList") as ItemList
	assert_int(list.icon_mode).is_equal(ItemList.ICON_MODE_TOP)
	assert_int(list.max_columns).is_equal(2)
	assert_bool(list.same_column_width).is_true()
	assert_int(list.fixed_column_width).is_equal(132)
	assert_int(list.fixed_icon_size.x).is_equal(64)
	assert_int(list.fixed_icon_size.y).is_equal(64)
	panel.free()


func test_skill_grid_keeps_deterministic_icon_fallback() -> void:
	var source := FileAccess.get_file_as_string("res://scenes/ui/tavern_equipment_panel.gd")
	assert_bool(source.contains("ItemList.ICON_MODE_TOP")).is_true()
	assert_bool(source.contains("skill_id.to_utf8_buffer().hex_encode()" )).is_true()
	assert_bool(source.contains("Capture mode can omit the SkillIcons autoload")).is_true()


func test_skill_workspace_uses_visibility_aware_pixel_border() -> void:
	var border_source := FileAccess.get_file_as_string("res://scenes/ui/pixel_border_frame.gd")
	var scene_source := FileAccess.get_file_as_string("res://scenes/ui/tavern_equipment_panel.tscn")
	assert_bool(border_source.contains("target.visible and target.is_visible_in_tree()")).is_true()
	assert_bool(scene_source.contains("PixelSkillWorkspaceBorder")).is_true()
	assert_bool(scene_source.contains("target_path = NodePath(\"PanelContainer/VBoxContainer/MainLayout/RightTabs/技能\")")).is_true()
