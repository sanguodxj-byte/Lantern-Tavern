extends GdUnitTestSuite

const SHADER_PATH := "res://scenes/tavern/materials/tavern_atlas_world_32px.gdshader"
const VOXEL_SHADER_PATH := "res://assets/shaders/dungeon_terrain.gdshader"
const WALL_MATERIAL_PATH := "res://scenes/tavern/materials/tavern_wall_mat.tres"
const WALL_TEXTURE_PATH := "res://assets/textures/tavern/tavern_wall_stone_variants_32px.png"
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
	assert_str(shader_source).contains("uniform vec2 atlas_grid")
	assert_str(shader_source).contains("/ max(atlas_grid, vec2(1.0))")
	assert_str(shader_source).contains("uniform float atlas_inset_px")
	assert_str(shader_source).contains("tile_size - inset * 2.0")
	assert_str(shader_source).contains("uniform float atlas_continuous_region")
	assert_str(shader_source).contains("region_size - abs(wrapped - region_size)")


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
	assert_str(shader_source).contains("vec3(0.68)")


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


func test_tavern_wall_uses_continuous_generated_macro_texture() -> void:
	var material := load(WALL_MATERIAL_PATH) as ShaderMaterial
	var texture := material.get_shader_parameter("atlas_texture") as Texture2D
	var atlas_grid: Vector2 = material.get_shader_parameter("atlas_grid")
	var atlas_region: Vector4 = material.get_shader_parameter("atlas_region_tiles")
	var albedo_tint: Color = material.get_shader_parameter("albedo_tint")

	assert_str(texture.resource_path).is_equal(WALL_TEXTURE_PATH)
	assert_vector(atlas_grid).is_equal(Vector2(4, 4))
	assert_float(atlas_region.z).is_equal(4.0)
	assert_float(atlas_region.w).is_equal(3.0)
	assert_float(float(material.get_shader_parameter("atlas_inset_px"))).is_equal(0.0)
	assert_float(float(material.get_shader_parameter("atlas_continuous_region"))).is_equal(1.0)
	assert_float(float(material.get_shader_parameter("atlas_mirror_repeat"))).is_equal(1.0)
	assert_float(albedo_tint.r).is_greater(1.2)

	var image := texture.get_image()
	if image.is_compressed():
		assert_int(image.decompress()).is_equal(OK)
	assert_int(image.get_width()).is_equal(128)
	assert_int(image.get_height()).is_equal(128)

	var transparent_bottom := 0
	var opaque_wall := 0
	var green_wall_pixels := 0
	for y in range(128):
		for x in range(128):
			var color := image.get_pixel(x, y)
			if y >= 96 and color.a <= 0.001:
				transparent_bottom += 1
			elif y < 96 and color.a >= 0.999:
				opaque_wall += 1
				if color.g > 0.8 and color.g > color.r * 1.5 and color.g > color.b * 1.5:
					green_wall_pixels += 1
	assert_int(transparent_bottom).is_equal(128 * 32)
	assert_int(opaque_wall).is_equal(128 * 96)
	assert_int(green_wall_pixels).is_equal(0)

	var unique_tiles := {}
	for row in range(3):
		for column in range(4):
			var tile := image.get_region(Rect2i(column * 32, row * 32, 32, 32))
			unique_tiles[hash(tile.get_data())] = true
	assert_int(unique_tiles.size()).is_equal(12)

	for boundary in [32, 64, 96]:
		var seam_luminance := (_column_luminance(image, boundary - 1) \
			+ _column_luminance(image, boundary)) * 0.5
		var neighbor_luminance := (_column_luminance(image, boundary - 2) \
			+ _column_luminance(image, boundary + 1)) * 0.5
		assert_float(seam_luminance / neighbor_luminance).is_greater(0.75)
	for boundary in [32, 64]:
		var seam_luminance := (_row_luminance(image, boundary - 1) \
			+ _row_luminance(image, boundary)) * 0.5
		var neighbor_luminance := (_row_luminance(image, boundary - 2) \
			+ _row_luminance(image, boundary + 1)) * 0.5
		assert_float(seam_luminance / neighbor_luminance).is_greater(0.75)


func _column_luminance(image: Image, column: int) -> float:
	var total := 0.0
	for y in range(96):
		var color := image.get_pixel(column, y)
		total += color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
	return total / 96.0


func _row_luminance(image: Image, row: int) -> float:
	var total := 0.0
	for x in range(128):
		var color := image.get_pixel(x, row)
		total += color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
	return total / 128.0
