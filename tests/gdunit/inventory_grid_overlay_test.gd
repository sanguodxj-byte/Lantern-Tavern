extends GdUnitTestSuite

const OVERLAY_SCRIPT := "res://scenes/ui/inventory_grid_overlay.gd"


func test_overlay_is_non_interactive_and_above_parent_content() -> void:
	var overlay := load(OVERLAY_SCRIPT).new() as Control
	add_child(overlay)
	await await_idle_frame()
	assert_int(overlay.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int(overlay.z_index).is_greater(0)
	overlay.queue_free()


func test_overlay_can_exist_without_inventory_source() -> void:
	var overlay := load(OVERLAY_SCRIPT).new() as Control
	add_child(overlay)
	await await_idle_frame()
	assert_object(overlay).is_not_null()
	overlay.queue_free()
