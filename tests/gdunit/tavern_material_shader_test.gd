extends GdUnitTestSuite

const SHADER_PATH := "res://scenes/tavern/materials/tavern_atlas_world_32px.gdshader"
const MATERIAL_PATHS := [
	"res://scenes/tavern/materials/tavern_wall_mat.tres",
	"res://scenes/tavern/materials/tavern_floor_mat.tres",
	"res://scenes/tavern/materials/tavern_ceiling_mat.tres",
	"res://scenes/tavern/materials/tavern_door_mat.tres",
	"res://scenes/tavern/materials/tavern_bar_mat.tres",
	"res://scenes/tavern/materials/tavern_pillar_mat.tres",
]


func test_tavern_shader_exposes_noise_and_decal_layers() -> void:
	var shader_source := FileAccess.get_file_as_string(SHADER_PATH)
	for required_token in [
		"noise_strength",
		"noise_scale",
		"decal_strength",
		"decal_tint",
		"value_noise",
		"decal_mask",
		"roughness_variation",
		"decal_broad",
		"ROUGHNESS = clamp",
	]:
		assert_str(shader_source).contains(required_token)


func test_tavern_materials_bind_noise_and_decal_parameters() -> void:
	for material_path in MATERIAL_PATHS:
		var material_source := FileAccess.get_file_as_string(material_path)
		assert_str(material_source).contains("shader_parameter/noise_strength")
		assert_str(material_source).contains("shader_parameter/decal_strength")
		assert_str(material_source).contains("shader_parameter/decal_tint")
		assert_str(material_source).contains("shader_parameter/roughness_variation")
