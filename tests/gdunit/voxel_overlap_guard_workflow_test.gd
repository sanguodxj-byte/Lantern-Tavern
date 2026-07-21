extends GdUnitTestSuite
## Workflow gates for voxel overlap / remake honesty.


func test_overlap_guard_module_exists_and_exports_api() -> void:
	var source := FileAccess.get_file_as_string("res://tools/voxel_overlap_guard.py")
	assert_bool(source.is_empty()).is_false()
	assert_str(source).contains("assert_parts_no_positive_volume_overlap")
	assert_str(source).contains("assert_parts_single_face_connected_component")
	assert_str(source).contains("assert_parts_voxel_assembly_valid")
	assert_str(source).contains("exterior_plate_center")
	assert_str(source).contains("boxes_positive_volume_overlap")
	assert_str(source).contains("boxes_face_contact")


func test_docs17_forbids_positive_volume_overlap_and_defines_remake_gate() -> void:
	var doc := FileAccess.get_file_as_string("res://docs/17-体素建模工作流.md")
	assert_str(doc).contains("禁止正体积重叠")
	assert_str(doc).contains("只允许面接触")
	assert_str(doc).contains("character_voxel_overlap_test")
	assert_str(doc).contains("voxel_overlap_guard")
	assert_str(doc).contains("真·重做门槛")
	assert_str(doc).contains("exterior_plate_center")


func test_docs17_requires_symmetry_unless_asymmetry_has_design_meaning() -> void:
	var doc := FileAccess.get_file_as_string("res://docs/17-体素建模工作流.md")
	assert_str(doc).contains("默认对称原则")
	assert_str(doc).contains("明确的非对称语义")
	assert_str(doc).contains("禁止无意义的单侧突起")


func test_docs28_remake_gate_exists() -> void:
	assert_bool(FileAccess.file_exists("res://docs/28-体素真重做门槛与角色重叠守卫.md")).is_true()
	var doc := FileAccess.get_file_as_string("res://docs/28-体素真重做门槛与角色重叠守卫.md")
	assert_str(doc).contains("character_voxel_overlap_test")
	assert_str(doc).contains("voxel_overlap_guard")
	assert_str(doc).contains("模板 + 贴片")


func test_agents_md_forbids_intentional_overlap() -> void:
	var agents := FileAccess.get_file_as_string("res://AGENTS.md")
	assert_str(agents).contains("face contact only")
	assert_str(agents).contains("character_voxel_overlap_test")
	assert_bool(agents.contains("intentional overlap")).is_false()


func test_character_overlap_test_suite_is_accepted_only() -> void:
	assert_bool(FileAccess.file_exists("res://tests/gdunit/character_voxel_overlap_test.gd")).is_true()
	var source := FileAccess.get_file_as_string("res://tests/gdunit/character_voxel_overlap_test.gd")
	assert_str(source).contains("TIERS.accepted_model_ids()")
	assert_str(source).contains("test_accepted_static_and_rig_glbs_have_no_positive_volume_overlap")
	assert_str(source).contains("test_accepted_static_glbs_are_single_face_connected_components")
	assert_str(source).not_contains("STRICT_ROGUELIKE")
	assert_str(source).not_contains("KNOWN_SAME_MAT_DEBT")
	assert_str(source).not_contains("voxel_player_48px")
