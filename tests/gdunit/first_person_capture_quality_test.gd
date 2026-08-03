extends GdUnitTestSuite

const QUALITY := preload("res://tools/first_person_capture_quality.gd")


func test_capture_quality_measures_foreground_bounds_luminance_and_margins() -> void:
	var image := Image.create(100, 60, false, Image.FORMAT_RGBA8)
	image.fill(QUALITY.DEFAULT_BACKGROUND)
	image.fill_rect(Rect2i(20, 10, 50, 40), Color(0.8, 0.8, 0.8, 1.0))
	var metrics := QUALITY.analyze(image)
	assert_int(metrics["foreground_pixels"]).is_equal(2000)
	var bounds: Rect2i = metrics["bounds"]
	assert_int(bounds.position.x).is_equal(20)
	assert_int(bounds.position.y).is_equal(10)
	assert_int(bounds.size.x).is_equal(50)
	assert_int(bounds.size.y).is_equal(40)
	assert_float(metrics["mean_luminance"]).is_equal_approx(0.8, 0.001)
	var margins: Vector4 = metrics["margins"]
	assert_float(margins.x).is_equal_approx(20.0, 0.001)
	assert_float(margins.y).is_equal_approx(10.0, 0.001)
	assert_float(margins.z).is_equal_approx(30.0, 0.001)
	assert_float(margins.w).is_equal_approx(10.0, 0.001)
	assert_array(QUALITY.validate(metrics, 500, 30, 0.4, 5)).is_empty()


func test_capture_quality_rejects_blank_underexposed_and_edge_clipped_frames() -> void:
	var blank := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	blank.fill(QUALITY.DEFAULT_BACKGROUND)
	assert_array(QUALITY.validate(QUALITY.analyze(blank), 10, 10, 0.1, 1)).contains([
		"foreground is missing or too small (0 px)",
	])
	var clipped := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	clipped.fill(QUALITY.DEFAULT_BACKGROUND)
	clipped.fill_rect(Rect2i(0, 12, 40, 40), Color(0.12, 0.12, 0.12, 1.0))
	var issues := QUALITY.validate(QUALITY.analyze(clipped), 100, 30, 0.3, 4)
	assert_bool(issues.any(func(issue: String) -> bool: return "underexposed" in issue)).is_true()
	assert_bool(issues.any(func(issue: String) -> bool: return "safe edge" in issue)).is_true()


func test_review_world_uses_a_lit_non_emissive_camera_fill_setup() -> void:
	var viewport: SubViewport = auto_free(SubViewport.new()) as SubViewport
	QUALITY.configure_review_world(viewport)
	var camera_fill := viewport.get_node_or_null("FirstPersonReviewCameraFill") as OmniLight3D
	assert_object(camera_fill).is_not_null()
	if camera_fill == null:
		return
	assert_float(camera_fill.light_energy).is_equal_approx(2.45, 0.001)
	assert_bool(camera_fill.shadow_enabled).is_false()
	assert_float(camera_fill.omni_range).is_equal_approx(3.0, 0.001)
