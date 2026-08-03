extends GdUnitTestSuite

const GENERATOR := "res://tools/generate_voxel_buckler.py"
const GLB_PATH := "res://assets/meshes/shields/voxel_buckler.glb"
const SHIELD_DATA_PATH := "res://data/shields/buckler.tres"
const PICKABLE_PATH := "res://scenes/equipment/pickable_buckler.tscn"
const SUPPORT := preload("res://tests/gdunit/support/voxel_model_test_support.gd")


func test_buckler_generator_is_fixed_identity_guarded_and_pixel_authored() -> void:
	var source := FileAccess.get_file_as_string(GENERATOR)
	assert_str(source).contains('MODEL_ID = "buckler"')
	assert_str(source).contains("DIAMETER_PX = 24.0")
	assert_str(source).contains("THICKNESS_PX = 5.0")
	assert_str(source).contains("make_pixel_material")
	assert_str(source).contains("reject_target_override(MODEL_ID)")
	assert_str(source).contains("assert_parts_no_positive_volume_overlap")
	assert_str(source).contains("assert_parts_voxel_assembly_valid")
	assert_bool(source.contains("BUILDERS")).is_false()


func test_buckler_glb_is_single_merged_buckler_mesh_with_runtime_mount_contract() -> void:
	var instance := _instantiate()
	assert_str(instance.name).contains("voxel_buckler")
	var children: Array[Node] = instance.find_children("Buckler", "MeshInstance3D", true, false)
	assert_int(children.size()).is_equal(1)
	var mesh := children[0] as MeshInstance3D
	assert_object(mesh.mesh).is_not_null()
	# 5 material surfaces: oak, oak_shadow, iron, steel, leather_grip.
	assert_int(mesh.mesh.get_surface_count()).is_equal(5)
	instance.free()


func test_buckler_triangle_budget_is_voxel_scale_not_legacy_cylinder_flood() -> void:
	var instance := _instantiate()
	var children: Array[Node] = instance.find_children("Buckler", "MeshInstance3D", true, false)
	var mesh := children[0] as MeshInstance3D
	var tri := 0
	var vert := 0
	for si in range(mesh.mesh.get_surface_count()):
		var arrays := mesh.mesh.surface_get_arrays(si)
		var indices: Array = arrays[Mesh.ARRAY_INDEX]
		var verts: Array = arrays[Mesh.ARRAY_VERTEX]
		tri += (indices.size() / 3) if indices != null and indices.size() > 0 else (verts.size() / 3)
		vert += verts.size()
	assert_int(tri).is_less(1500)
	assert_int(vert).is_less(1500)
	assert_int(tri).is_greater(100)
	instance.free()


func test_buckler_envelope_matches_pixel_dimensions() -> void:
	var instance := _instantiate()
	var bounds: AABB = SUPPORT.combined_aabb(instance)
	# Round face ~24px diameter; 5px body plus boss/grip protrusions -> ~9px thick.
	assert_float(bounds.size.x).is_equal_approx(23.0 / 32.0, 0.01)
	assert_float(bounds.size.y).is_equal_approx(24.0 / 32.0, 0.01)
	assert_float(bounds.size.z).is_equal_approx(9.0 / 32.0, 0.01)
	instance.free()


func test_buckler_imported_palette_keeps_pixel_textures_and_metal_variants() -> void:
	var instance := _instantiate()
	var children: Array[Node] = instance.find_children("Buckler", "MeshInstance3D", true, false)
	var mesh := children[0] as MeshInstance3D
	var textured: Array[StandardMaterial3D] = []
	var metals: Array[StandardMaterial3D] = []
	for si in range(mesh.mesh.get_surface_count()):
		var material := mesh.get_active_material(si) as StandardMaterial3D
		assert_object(material).is_not_null()
		if material.albedo_texture != null:
			textured.append(material)
		elif material.metallic > 0.5:
			metals.append(material)
	# oak, oak_shadow, leather_grip carry embedded 8x8 pixel textures.
	assert_int(textured.size()).is_equal(3)
	assert_int(metals.size()).is_equal(2)
	for material in textured:
		assert_int(material.albedo_texture.get_width()).is_equal(8)
		assert_int(material.albedo_texture.get_height()).is_equal(8)
	instance.free()


func test_buckler_shield_data_and_pickable_keep_runtime_contract() -> void:
	var shield_text := FileAccess.get_file_as_string(SHIELD_DATA_PATH)
	assert_str(shield_text).contains("res://assets/meshes/shields/voxel_buckler.glb")
	assert_str(shield_text).contains('name = "Buckler"')
	var pickable := FileAccess.get_file_as_string(PICKABLE_PATH)
	assert_str(pickable).contains('mesh_node = NodePath("buckler/Buckler")')
	assert_str(pickable).contains("res://assets/meshes/shields/voxel_buckler.glb")


func test_buckler_registered_in_structural_capture_allowlist() -> void:
	var capture_source := FileAccess.get_file_as_string("res://tools/voxel_prop_three_view_capture.gd")
	assert_str(capture_source).contains('"buckler": "res://assets/meshes/shields/voxel_buckler.glb"')


func test_buckler_verification_images_are_readable_and_nonblank() -> void:
	for view_name in ["preview", "front", "side", "top"]:
		var rendered := SUPPORT.inspect_image_file(
			"res://reports/props_preview/voxel_buckler_render_%s.png" % view_name
		)
		assert_bool(rendered["nonblank"]) \
			.override_failure_message("blank buckler Blender view: %s" % view_name).is_true()
	for view_name in ["front", "side", "top"]:
		var structural := SUPPORT.inspect_image_file(
			"res://reports/props_preview/buckler_%s.png" % view_name
		)
		assert_bool(structural["nonblank"]) \
			.override_failure_message("blank buckler structural view: %s" % view_name).is_true()


func _instantiate() -> Node3D:
	var packed := load(GLB_PATH) as PackedScene
	assert_object(packed).is_not_null()
	var instance := packed.instantiate() as Node3D
	assert_object(instance).is_not_null()
	add_child(instance)
	return instance
