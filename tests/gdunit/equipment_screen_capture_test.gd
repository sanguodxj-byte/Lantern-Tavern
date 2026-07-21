extends GdUnitTestSuite

func test_capture_tool_uses_isolated_subviewport_and_current_equipment_scene() -> void:
	var source := FileAccess.get_file_as_string("res://tools/equipment_screen_capture.gd")
	assert_bool(source.contains("SubViewport.new()")).is_true()
	assert_bool(source.contains("tavern_equipment_panel.tscn")).is_true()
	assert_bool(source.contains("after_equipment.png")).is_true()
	assert_bool(source.contains("after_skills_v2.png")).is_true()
	assert_bool(source.contains("--skills")).is_true()

func test_capture_tool_seeds_persistent_detail_fixture() -> void:
	var source := FileAccess.get_file_as_string("res://tools/equipment_screen_capture.gd")
	assert_bool(source.contains("ItemDetailTitle")).is_true()
	assert_bool(source.contains("ItemDetailBody")).is_true()
	assert_bool(source.contains("ItemDetailCompare")).is_true()
	assert_bool(source.contains("FilterBar")).is_false()
	assert_bool(source.contains("player_visual_model.tscn")).is_true()
	assert_bool(source.contains("voxel_player_48px_rig.glb")).is_false()

func test_capture_tool_seeds_skill_tab_fixture() -> void:
	var source := FileAccess.get_file_as_string("res://tools/equipment_screen_capture.gd")
	assert_bool(source.contains("_seed_skills")).is_true()
	assert_bool(source.contains("AvailableSkillsList")).is_true()
	assert_bool(source.contains("RuneWarehouseList")).is_true()
	assert_bool(source.contains("SkillWorkspaceCapture")).is_true()
	assert_bool(source.contains("SkillWarehouseRowCapture")).is_true()


func test_capture_mode_avoids_full_player_runtime_bootstrap() -> void:
	var panel_source := FileAccess.get_file_as_string("res://scenes/ui/tavern_equipment_panel.gd")
	var capture_source := FileAccess.get_file_as_string("res://tools/equipment_screen_capture.gd")
	assert_bool(panel_source.contains("PLAYER_PREVIEW_SCENE_PATH")).is_true()
	assert_bool(panel_source.contains("COMBAT_STATS_SCRIPT_PATH")).is_true()
	assert_bool(panel_source.contains("_is_capture_mode()")).is_true()
	assert_bool(capture_source.contains("equipment_capture_mode")).is_true()
	assert_bool(capture_source.contains('panel.call("_refresh_equipment_slots")')).is_true()


func test_capture_uses_fixed_left_column_layout() -> void:
	var scene_source := FileAccess.get_file_as_string("res://scenes/ui/tavern_equipment_panel.tscn")
	var panel_source := FileAccess.get_file_as_string("res://scenes/ui/tavern_equipment_panel.gd")
	assert_bool(scene_source.contains("custom_minimum_size = Vector2(640, 0)")).is_true()
	assert_bool(scene_source.contains("size_flags_horizontal = 0")).is_true()
	assert_bool(panel_source.contains("const LEFT_COLUMN_WIDTH := 640.0")).is_true()
	assert_bool(panel_source.contains("left_column.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN")).is_true()
	var capture_source := FileAccess.get_file_as_string("res://tools/equipment_screen_capture.gd")
	assert_bool(capture_source.contains("Control.PRESET_TOP_LEFT")).is_true()
	assert_bool(capture_source.contains("panel.size = Vector2(SIZE)")).is_true()
	assert_bool(panel_source.contains("func _lock_panel_frame_layout() -> void:")).is_true()
	assert_bool(panel_source.contains("panel_frame.position = Vector2(20.0, 20.0)")).is_true()
	assert_bool(panel_source.contains("func _on_right_tab_changed(_tab_index: int) -> void:")).is_true()
