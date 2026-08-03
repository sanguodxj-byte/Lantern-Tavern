extends GdUnitTestSuite

const PRIMITIVES_PATH := "res://tools/voxel_model_primitives.py"
const HUMANOID_ACTIONS_PATH := "res://tools/voxel_character_rig.py"
const DRAGON_GENERATOR_PATH := "res://tools/generate_voxel_dragon.py"


func _source(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func test_model_primitives_are_mechanical_and_have_no_authored_body_or_registry() -> void:
	assert_bool(FileAccess.file_exists(PRIMITIVES_PATH)).is_true()
	var source := _source(PRIMITIVES_PATH)
	for required_function in [
		"def reset_scene(",
		"def face_attachment_center(",
		"def make_material(",
		"def make_pixel_material(",
		"def cube_px(",
		"def make_root(",
		"def validate_face_attached_assembly(",
		"def export_glb(",
		"def setup_lights_and_camera(",
		"def render_real_views(",
		"def finish_model(",
	]:
		assert_str(source).contains(required_function)
	assert_str(source).contains("assert_parts_voxel_assembly_valid")
	for forbidden_marker in [
		"humanoid_core",
		"parent_standard_humanoid",
		"build_humanoid_rig",
		"build_creature_rig",
		"MODEL_ID",
		"MODEL_REGISTRY",
		"HUMANOID_RIGS",
		"CREATURE_CONFIGS",
		"CHAR_DIR",
		"PREVIEW_DIR",
		"RAT_BONES",
		"SLIME_BONES",
		"DRAGON_BONES",
		"SPIDER_BONES",
	]:
		assert_str(source) \
			.override_failure_message("mechanical primitives contain authored model data: %s" % forbidden_marker) \
			.not_contains(forbidden_marker)


func test_real_3d_render_names_cannot_overwrite_structural_projections() -> void:
	var source := _source(PRIMITIVES_PATH)
	assert_str(source).contains('f"{stem}_render_{view}.png"')
	assert_str(source).not_contains('f"{stem}_{view}.png"')
	for view in ["preview", "front", "side", "top"]:
		assert_str(source).contains('"%s"' % view)


func test_pixel_material_helper_is_mechanical_and_caller_driven() -> void:
	# make_pixel_material must take a caller-supplied palette + seed (no baked
	# model identity table) and emit nearest-filtered textures.
	var source := _source(PRIMITIVES_PATH)
	assert_str(source).contains("def make_pixel_material(")
	assert_str(source).contains("palette:")
	assert_str(source).contains("seed:")
	assert_str(source).contains("pixel_size:")
	assert_str(source).contains("Closest")
	# cube_px must remap each face to the full 0..1 UV square so procedural
	# pixel-art textures are sampled across the whole face, not a 0.25 corner.
	assert_str(source).contains("_face_corners")
	assert_str(source).contains("uv_layers")
	# No model identity may leak into the mechanical helper.
	for forbidden_marker in ["soul_gem", "dragon_scale", "glowshroom", "SG_PALETTE"]:
		assert_str(source) \
			.override_failure_message("pixel helper leaked model identity: %s" % forbidden_marker) \
			.not_contains(forbidden_marker)


func test_cube_px_uv_mapping_comment_documents_full_face_coverage() -> void:
	var source := _source(PRIMITIVES_PATH)
	# The UV remap must be documented as full 0..1 coverage per face.
	assert_str(source).contains("full 0..1 UV square")


func test_humanoid_action_module_has_no_model_paths_import_rebuilder_or_mixed_species() -> void:
	var source := _source(HUMANOID_ACTIONS_PATH)
	for required_function in [
		"def make_action(",
		"def build_all_actions(",
		"def build_weapon_actions(",
		"def export_glb(",
	]:
		assert_str(source).contains(required_function)
	for forbidden_marker in [
		"from voxel_humanoid_rig import",
		"from voxel_creature_rig import",
		"bpy.ops.import_scene",
		"build_humanoid_rig",
		"build_creature_rig",
		"create_voxel_humanoid_armature",
		"create_creature_armature",
		"CHAR_DIR",
		"MODEL_ID",
		"MODEL_REGISTRY",
		"HUMANOID_RIGS",
		"CREATURE_CONFIGS",
		"RAT_BONES",
		"SLIME_BONES",
		"DRAGON_BONES",
		"SPIDER_BONES",
		"sys.argv",
		"if __name__",
	]:
		assert_str(source) \
			.override_failure_message("humanoid action mechanics contain model reconstruction or mixed species: %s" % forbidden_marker) \
			.not_contains(forbidden_marker)


func test_polluted_shared_model_sources_remain_removed() -> void:
	assert_bool(FileAccess.file_exists("res://tools/voxel_remake_lib.py")).is_false()
	assert_bool(FileAccess.file_exists("res://tools/voxel_creature_rig.py")).is_false()


func test_dragon_passes_its_exact_static_output_to_mechanical_primitives() -> void:
	var source := _source(DRAGON_GENERATOR_PATH)
	assert_str(source).contains("from voxel_model_primitives import")
	assert_str(source).contains("reset_scene()")
	assert_str(source).contains("finish_model(")
	assert_str(source).contains("output_path=STATIC_OUTPUT")
	assert_str(source).contains('render_stem="voxel_dragon"')
	assert_str(source).not_contains("STATIC_OUTPUT.stem")
	assert_str(source).not_contains("voxel_remake_lib")
	assert_str(source).not_contains("voxel_creature_rig")
