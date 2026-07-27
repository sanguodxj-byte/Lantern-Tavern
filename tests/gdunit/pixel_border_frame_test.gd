extends GdUnitTestSuite

const FRAME_SCRIPT := "res://scenes/ui/pixel_border_frame.gd"


func test_pixel_border_frame_is_a_non_layout_control() -> void:
	var frame_script := load(FRAME_SCRIPT) as GDScript
	var frame: Control = frame_script.new() as Control
	assert_object(frame).is_instanceof(Control)
	var source := FileAccess.get_file_as_string(FRAME_SCRIPT)
	assert_str(source).contains("mouse_filter = Control.MOUSE_FILTER_IGNORE")
	assert_str(source).contains("texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST")
	frame.free()


func test_pixel_border_frame_owns_texture_ring_and_corner_rendering() -> void:
	var source := FileAccess.get_file_as_string(FRAME_SCRIPT)
	assert_str(source).contains("_draw_texture_ring")
	assert_str(source).contains("draw_texture_rect_region")
	assert_str(source).contains("_draw_corners")
	assert_str(source).contains("get_global_rect")
	assert_str(source).contains("transparent")


func test_pixel_border_frame_has_positive_default_geometry() -> void:
	var frame: Control = (load(FRAME_SCRIPT) as GDScript).new() as Control
	assert_float(float(frame.get("border_width"))).is_greater(0.0)
	assert_float(float(frame.get("border_inset"))).is_greater_equal(0.0)
	assert_float(float(frame.get("corner_size"))).is_greater(0.0)
	frame.free()
