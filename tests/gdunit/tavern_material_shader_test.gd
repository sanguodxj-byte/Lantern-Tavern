extends GdUnitTestSuite

const SHADER_PATH := "res://scenes/tavern/materials/tavern_atlas_world_32px.gdshader"
const VOXEL_SHADER_PATH := "res://assets/shaders/dungeon_terrain.gdshader"
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


func test_tavern_shader_disables_material_specular_highlights() -> void:
	var shader_source := FileAccess.get_file_as_string(SHADER_PATH)
	assert_str(shader_source) \
		.override_failure_message("酒馆环境材质必须禁用镜面高光，避免火光在所有台面/墙面形成白色倒影") \
		.contains("specular_disabled")
	assert_str(shader_source) \
		.override_failure_message("酒馆环境材质必须显式输出 SPECULAR=0，防止镜面高光保护层被移除后回归") \
		.contains("SPECULAR = 0.0")


func test_voxel_shader_caps_accumulated_diffuse_light() -> void:
	var shader_source := FileAccess.get_file_as_string(VOXEL_SHADER_PATH)
	assert_str(shader_source) \
		.override_failure_message("体素道具 Shader 必须限制多光源累计漫反射，避免材质受光过曝") \
		.contains("DIFFUSE_LIGHT = min")
	assert_str(shader_source).contains("vec3(1.0)")


func test_tavern_materials_bind_noise_and_decal_parameters() -> void:
	for material_path in MATERIAL_PATHS:
		var material_source := FileAccess.get_file_as_string(material_path)
		assert_str(material_source).contains("shader_parameter/noise_strength")
		assert_str(material_source).contains("shader_parameter/decal_strength")
		assert_str(material_source).contains("shader_parameter/decal_tint")
		assert_str(material_source).contains("shader_parameter/roughness_variation")


func test_tavern_material_instances_follow_non_metallic_roughness_floor() -> void:
	for material_path in MATERIAL_PATHS:
		var material := load(material_path) as ShaderMaterial
		assert_object(material) \
			.override_failure_message("酒馆材质必须可加载为 ShaderMaterial: " + material_path) \
			.is_not_null()
		assert_float(float(material.get_shader_parameter("material_metallic"))) \
			.override_failure_message("酒馆普通结构材质必须为非金属: " + material_path) \
			.is_equal_approx(0.0, 0.001)
		assert_float(float(material.get_shader_parameter("material_roughness"))) \
			.override_failure_message("酒馆普通结构材质粗糙度不得低于 0.75: " + material_path) \
			.is_greater_equal(0.75)
