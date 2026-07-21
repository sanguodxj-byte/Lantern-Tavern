extends GdUnitTestSuite

const GLB_PATH := "res://assets/meshes/characters/voxel_goblin_32px.glb"
const RIG_GLB_PATH := "res://assets/meshes/characters/voxel_goblin_32px_rig.glb"
const GENERATOR_PATH := "res://tools/generate_voxel_goblin.py"
const PREVIEW_FRONT := "res://reports/characters_preview/voxel_goblin_render_front.png"
const PREVIEW_SIDE := "res://reports/characters_preview/voxel_goblin_render_side.png"
const PREVIEW_TOP := "res://reports/characters_preview/voxel_goblin_render_top.png"

const TARGET_ENVELOPE_PX := Vector3(21.0, 35.0, 13.0)
const AUTHORED_PART_COUNT := 38


func test_asset_files_exist() -> void:
	assert_bool(FileAccess.file_exists(GLB_PATH)).is_true()
	assert_bool(FileAccess.file_exists(RIG_GLB_PATH)).is_true()
	assert_bool(FileAccess.file_exists(GENERATOR_PATH)).is_true()


func test_authored_spec_and_envelope() -> void:
	var global_script_path := ProjectSettings.globalize_path(GENERATOR_PATH)
	var file := FileAccess.open(global_script_path, FileAccess.READ)
	assert_object(file).is_not_null()
	var script_text := file.get_as_text()
	file.close()

	assert_bool(script_text.contains("AUTHORED_PART_COUNT = 38")).is_true()
	assert_bool(script_text.contains("TARGET_ENVELOPE_PX = (21.0, 35.0, 13.0)")).is_true()
	assert_bool(script_text.contains("MODEL_ID = \"goblin\"")).is_true()


func test_preview_images_exist() -> void:
	assert_bool(FileAccess.file_exists(PREVIEW_FRONT)).is_true()
	assert_bool(FileAccess.file_exists(PREVIEW_SIDE)).is_true()
	assert_bool(FileAccess.file_exists(PREVIEW_TOP)).is_true()
