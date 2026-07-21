extends GdUnitTestSuite

const SUPPORT := preload("res://tests/gdunit/support/voxel_model_test_support.gd")


func test_support_detects_bounds_symmetry_and_face_contact() -> void:
	var root_node := Node3D.new()
	add_child(root_node)
	var shared_box := BoxMesh.new()
	shared_box.size = Vector3.ONE
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.4, 0.5, 0.6, 1.0)
	shared_box.material = material
	var left := MeshInstance3D.new()
	left.name = "left"
	left.mesh = shared_box
	left.position.x = -0.5
	root_node.add_child(left)
	var right := MeshInstance3D.new()
	right.name = "right"
	right.mesh = shared_box
	right.position.x = 0.5
	root_node.add_child(right)

	var bounds: AABB = SUPPORT.combined_aabb(root_node)
	assert_bool(bounds.size.is_equal_approx(Vector3(2.0, 1.0, 1.0))).is_true()
	assert_array(SUPPORT.find_unmirrored_parts(root_node, Vector3(-1.0, 1.0, 1.0))).is_empty()
	assert_array(SUPPORT.find_positive_volume_overlaps(root_node)).is_empty()
	assert_array(SUPPORT.find_face_disconnected_parts(root_node)).is_empty()
	root_node.free()


func test_support_detects_positive_overlap_and_detachment() -> void:
	var root_node := Node3D.new()
	add_child(root_node)
	var shared_box := BoxMesh.new()
	shared_box.size = Vector3.ONE
	var first := MeshInstance3D.new()
	first.name = "first"
	first.mesh = shared_box
	root_node.add_child(first)
	var second := MeshInstance3D.new()
	second.name = "second"
	second.mesh = shared_box
	second.position.x = 0.5
	root_node.add_child(second)
	assert_array(SUPPORT.find_positive_volume_overlaps(root_node)).has_size(1)
	second.position.x = 2.0
	assert_array(SUPPORT.find_positive_volume_overlaps(root_node)).is_empty()
	assert_array(SUPPORT.find_face_disconnected_parts(root_node)).contains(["second"])
	root_node.free()


func test_support_reports_missing_image_as_not_readable() -> void:
	var result: Dictionary = SUPPORT.inspect_image_file("res://reports/does_not_exist_weapon_capture.png")
	assert_bool(result["exists"]).is_false()
	assert_bool(result["readable"]).is_false()
	assert_bool(result["nonblank"]).is_false()


func test_capture_ortho_size_uses_each_views_projected_bounds() -> void:
	var bounds := AABB(Vector3.ZERO, Vector3(13.0, 73.0, 9.0) / 32.0)
	assert_float(SUPPORT.capture_ortho_size(bounds, "front")) \
		.is_equal_approx(73.0 / 32.0 * 1.35, 0.0001)
	assert_float(SUPPORT.capture_ortho_size(bounds, "side")) \
		.is_equal_approx(73.0 / 32.0 * 1.35, 0.0001)
	assert_float(SUPPORT.capture_ortho_size(bounds, "top")) \
		.is_equal_approx(13.0 / 32.0 * 1.35, 0.0001)
	assert_float(SUPPORT.capture_ortho_size(bounds, "preview")) \
		.is_equal_approx(73.0 / 32.0 * 1.48, 0.0001)
