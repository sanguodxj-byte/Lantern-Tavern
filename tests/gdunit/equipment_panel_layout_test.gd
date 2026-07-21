extends GdUnitTestSuite

const EQUIPMENT_SCENE := preload("res://scenes/ui/tavern_equipment_panel.tscn")
const LEFT_COLUMN_PATH := "PanelContainer/VBoxContainer/MainLayout/LeftColumn"


func test_left_column_does_not_expand_when_switching_right_tabs() -> void:
	var panel := EQUIPMENT_SCENE.instantiate() as Control
	assert_object(panel).is_not_null()
	get_tree().root.set_meta("equipment_capture_mode", true)
	panel.visible = true
	panel.size = Vector2(1920, 1080)
	get_tree().root.add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame

	var left_column := panel.get_node(LEFT_COLUMN_PATH) as Control
	var right_tabs := panel.get_node("%RightTabs") as TabContainer
	var expected_width := 640.0

	right_tabs.current_tab = 0
	await get_tree().process_frame
	var items_width := left_column.size.x
	right_tabs.current_tab = 1
	await get_tree().process_frame
	var skills_width := left_column.size.x

	assert_float(items_width).is_equal_approx(expected_width, 0.1)
	assert_float(skills_width).is_equal_approx(expected_width, 0.1)
	assert_int(left_column.size_flags_horizontal).is_equal(Control.SIZE_SHRINK_BEGIN)

	panel.queue_free()
	get_tree().root.remove_meta("equipment_capture_mode")
