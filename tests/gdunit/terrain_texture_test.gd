extends GdUnitTestSuite

const ATLAS_PATH := "res://assets/textures/terrain/level0_dungeon/level0_dungeon_terrain_atlas_32px.png"
const META_PATH := "res://assets/textures/terrain/level0_dungeon/level0_dungeon_terrain_atlas_32px.json"
const SOURCE_DIR := "res://assets/textures/terrain/level0_dungeon/source_tiles/"


func test_level0_dungeon_atlas_has_expected_grid() -> void:
	assert_bool(FileAccess.file_exists(ATLAS_PATH)) \
		.override_failure_message("关卡0地牢 terrain atlas 缺失: %s" % ATLAS_PATH) \
		.is_true()

	var image := Image.load_from_file(ATLAS_PATH)
	assert_int(image.get_width()).is_equal(256)
	assert_int(image.get_height()).is_equal(128)
	assert_int(image.get_width() / 32).is_equal(8)
	assert_int(image.get_height() / 32).is_equal(4)


func test_level0_dungeon_atlas_metadata_defines_required_tiles() -> void:
	var meta := _load_meta()
	assert_int(int(meta["tile_px"][0])).is_equal(32)
	assert_int(int(meta["tile_px"][1])).is_equal(32)
	assert_int(int(meta["grid"][0])).is_equal(8)
	assert_int(int(meta["grid"][1])).is_equal(4)
	assert_int(int(meta["size_px"][0])).is_equal(256)
	assert_int(int(meta["size_px"][1])).is_equal(128)

	var tiles: Dictionary = meta["tiles"]
	for tile_name in [
		"wall_stone_brick",
		"floor_rough_stone",
		"ceiling_stone_slab",
		"lintel_cut_stone",
		"pillar_stone_side",
		"door_oak_iron",
		"boss_skull_double_door",
		"door_edge_side",
		"door_edge_top",
		"decor_iron_grate",
		"decor_rubble",
		"overlay_cracks",
		"overlay_moss",
		"overlay_grime",
		"overlay_blood",
		"overlay_torch_scorch",
	]:
		assert_bool(tiles.has(tile_name)) \
			.override_failure_message("level0 atlas metadata 缺少 tile: %s" % tile_name) \
			.is_true()


func test_level0_dungeon_source_tiles_have_locked_sizes() -> void:
	var expected_sizes := {
		"wall_stone_brick": Vector2i(32, 32),
		"floor_rough_stone": Vector2i(32, 32),
		"ceiling_stone_slab": Vector2i(32, 32),
		"lintel_cut_stone": Vector2i(32, 32),
		"pillar_stone_side": Vector2i(32, 32),
		"door_oak_iron": Vector2i(32, 64),
		"boss_skull_double_door": Vector2i(64, 64),
		"door_edge_side": Vector2i(32, 32),
		"door_edge_top": Vector2i(32, 32),
		"decor_iron_grate": Vector2i(32, 32),
		"decor_rubble": Vector2i(32, 32),
	}
	for tile_name in expected_sizes.keys():
		var image := Image.load_from_file(SOURCE_DIR + tile_name + ".png")
		var expected: Vector2i = expected_sizes[tile_name]
		assert_int(image.get_width()) \
			.override_failure_message("%s 宽度必须锁定" % tile_name) \
			.is_equal(expected.x)
		assert_int(image.get_height()) \
			.override_failure_message("%s 高度必须锁定" % tile_name) \
			.is_equal(expected.y)


func test_level0_dungeon_door_uses_one_by_two_uv_tiles() -> void:
	var meta := _load_meta()
	var door: Dictionary = meta["tiles"]["door_oak_iron"]
	assert_int(int(door["col"])).is_equal(7)
	assert_int(int(door["row"])).is_equal(1)
	assert_int(int(door["span"][0])).is_equal(1)
	assert_int(int(door["span"][1])).is_equal(2)
	assert_int(int(door["pixel_rect"][2])).is_equal(32)
	assert_int(int(door["pixel_rect"][3])).is_equal(64)

	var mat := load("res://scenes/expedition/level0_dungeon_door_mat.tres") as ShaderMaterial
	assert_object(mat).is_not_null()
	assert_str((mat.get_shader_parameter("atlas") as Texture2D).resource_path).is_equal(ATLAS_PATH)
	assert_object(mat.get_shader_parameter("tile_col_row")).is_equal(Vector2(7, 1))
	assert_object(mat.get_shader_parameter("tile_span")).is_equal(Vector2(1, 2))
	assert_object(mat.get_shader_parameter("atlas_grid")).is_equal(Vector2(8, 4))


func test_level0_dungeon_door_reads_as_medieval_oak_and_black_iron() -> void:
	var image := Image.load_from_file(SOURCE_DIR + "door_oak_iron.png")
	var dark_iron_pixels := 0
	var warm_wood_pixels := 0
	var overly_bright_pixels := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			var lum := _luminance(color)
			if lum < 70:
				dark_iron_pixels += 1
			elif color.r > color.g and color.g >= color.b and lum < 120:
				warm_wood_pixels += 1
			if lum > 175:
				overly_bright_pixels += 1

	assert_int(dark_iron_pixels) \
		.override_failure_message("中世纪地牢门需要明显黑铁边框、铆钉和加固条") \
		.is_greater(360)
	assert_int(warm_wood_pixels) \
		.override_failure_message("中世纪地牢门需要低饱和旧橡木主体") \
		.is_greater(700)
	assert_int(overly_bright_pixels) \
		.override_failure_message("关卡0门不能出现过亮、现代感的干净高光") \
		.is_less(24)


func test_level0_boss_door_is_double_door_with_skull_marker() -> void:
	var meta := _load_meta()
	var boss_door: Dictionary = meta["tiles"]["boss_skull_double_door"]
	assert_int(int(boss_door["col"])).is_equal(0)
	assert_int(int(boss_door["row"])).is_equal(2)
	assert_int(int(boss_door["span"][0])).is_equal(2)
	assert_int(int(boss_door["span"][1])).is_equal(2)
	assert_int(int(boss_door["pixel_rect"][2])).is_equal(64)
	assert_int(int(boss_door["pixel_rect"][3])).is_equal(64)

	var image := Image.load_from_file(SOURCE_DIR + "boss_skull_double_door.png")
	var seam_pixels := 0
	var black_iron_skull_pixels := 0
	var purple_eye_pixels := 0
	var asymmetric_marker_pairs := 0
	var wood_pixels_around_marker := 0
	var wood_pixels := 0
	for y in range(image.get_height()):
		if _luminance(image.get_pixel(31, y)) < 70 and _luminance(image.get_pixel(32, y)) < 70:
			seam_pixels += 1
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if color.r > color.g and color.g >= color.b and _luminance(color) < 120:
				wood_pixels += 1
			if abs(color.r - color.g) < 0.08 and abs(color.g - color.b) < 0.08 and _luminance(color) >= 45 and _luminance(color) < 145:
				black_iron_skull_pixels += 1
			if color.b > color.r and color.r > color.g and _luminance(color) < 65:
				purple_eye_pixels += 1
	for y in range(12, 38):
		for x in range(22, 32):
			var left_is_marker := _is_boss_marker_pixel(image.get_pixel(x, y))
			var right_is_marker := _is_boss_marker_pixel(image.get_pixel(63 - x, y))
			if left_is_marker != right_is_marker:
				asymmetric_marker_pairs += 1
	for y in range(11, 33):
		for x in range(20, 44):
			if _is_old_wood_pixel(image.get_pixel(x, y)):
				wood_pixels_around_marker += 1
	for point in [
		Vector2i(31, 11),
		Vector2i(32, 11),
		Vector2i(26, 17),
		Vector2i(37, 17),
		Vector2i(28, 21),
		Vector2i(35, 21),
		Vector2i(27, 25),
		Vector2i(36, 25),
	]:
		assert_bool(_is_boss_marker_pixel(image.get_pixel(point.x, point.y))) \
			.override_failure_message("Boss 门骷髅装饰层必须覆盖原门纹理: %s" % point) \
			.is_true()
		assert_bool(_is_old_wood_pixel(image.get_pixel(point.x, point.y))) \
			.override_failure_message("Boss 门骷髅装饰层采样点不能露出木纹: %s" % point) \
			.is_false()

	assert_int(seam_pixels) \
		.override_failure_message("Boss 房门必须有明显中央双开门缝") \
		.is_greater(48)
	assert_int(black_iron_skull_pixels) \
		.override_failure_message("Boss 房门骷髅标识必须使用黑铁色") \
		.is_greater(50)
	assert_int(purple_eye_pixels) \
		.override_failure_message("Boss 房门骷髅瞳孔必须使用深紫色") \
		.is_greater_equal(4)
	assert_int(asymmetric_marker_pairs) \
		.override_failure_message("Boss 房门骷髅标识必须是以中缝为轴的对称几何图形") \
		.is_equal(0)
	assert_int(wood_pixels_around_marker) \
		.override_failure_message("Boss 房门骷髅应是独立装饰层，不能再用矩形黑底整块盖住门") \
		.is_greater(80)
	assert_int(wood_pixels) \
		.override_failure_message("Boss 房门色调应与普通旧橡木门一致") \
		.is_greater(1200)

	var mat := load("res://scenes/expedition/level0_boss_door_mat.tres") as ShaderMaterial
	assert_object(mat).is_not_null()
	assert_str((mat.get_shader_parameter("atlas") as Texture2D).resource_path).is_equal(ATLAS_PATH)
	assert_object(mat.get_shader_parameter("tile_col_row")).is_equal(Vector2(0, 2))
	assert_object(mat.get_shader_parameter("tile_span")).is_equal(Vector2(2, 2))
	assert_object(mat.get_shader_parameter("atlas_grid")).is_equal(Vector2(8, 4))


func test_level0_dungeon_overlay_tiles_are_transparent_layers() -> void:
	for tile_name in ["overlay_cracks", "overlay_moss", "overlay_grime", "overlay_blood", "overlay_torch_scorch", "decor_rubble"]:
		var image := Image.load_from_file(SOURCE_DIR + tile_name + ".png")
		var transparent_pixels := 0
		var opaque_pixels := 0
		for y in range(image.get_height()):
			for x in range(image.get_width()):
				if image.get_pixel(x, y).a <= 0.01:
					transparent_pixels += 1
				else:
					opaque_pixels += 1
		assert_int(transparent_pixels) \
			.override_failure_message("%s 应作为透明装饰/附加层，而不是完整基础材质" % tile_name) \
			.is_greater(500)
		assert_int(opaque_pixels).is_greater(0)


func test_level0_dungeon_base_tiles_are_seam_friendly() -> void:
	for tile_name in ["wall_stone_brick", "floor_rough_stone", "ceiling_stone_slab"]:
		var image := Image.load_from_file(SOURCE_DIR + tile_name + ".png")
		assert_int(_edge_delta(image, true)) \
			.override_failure_message("%s 左右边缘亮度差过大，会出现接缝" % tile_name) \
			.is_less(48)
		assert_int(_edge_delta(image, false)) \
			.override_failure_message("%s 上下边缘亮度差过大，会出现接缝" % tile_name) \
			.is_less(48)


func test_procedural_dungeon_uses_level0_dungeon_atlas_for_base_terrain() -> void:
	var dungeon := load("res://scenes/expedition/procedural_dungeon.tscn").instantiate() as ProceduralDungeon
	add_child(dungeon)
	await await_idle_frame()

	var expected_tex := load(ATLAS_PATH)
	var wall_tested := false
	var floor_tested := false
	for child in dungeon.get_children():
		if child is MultiMeshInstance3D:
			var mat := child.material_override as ShaderMaterial
			if mat == null:
				continue
			if String(child.name).begins_with("WallMultiMesh"):
				assert_object(mat.get_shader_parameter("atlas")).is_equal(expected_tex)
				assert_object(mat.get_shader_parameter("tile_col_row")).is_equal(Vector2(0, 0))
				assert_object(mat.get_shader_parameter("tile_span")).is_equal(Vector2(1, 1))
				assert_object(mat.get_shader_parameter("atlas_grid")).is_equal(Vector2(8, 4))
				wall_tested = true
			elif child.name == "FloorMultiMesh":
				assert_object(mat.get_shader_parameter("atlas")).is_equal(expected_tex)
				assert_object(mat.get_shader_parameter("tile_col_row")).is_equal(Vector2(1, 0))
				assert_object(mat.get_shader_parameter("tile_span")).is_equal(Vector2(1, 1))
				assert_object(mat.get_shader_parameter("tile_repeat")).is_equal(Vector2(3.0, 3.0))
				floor_tested = true
	assert_bool(wall_tested).is_true()
	assert_bool(floor_tested).is_true()

	remove_child(dungeon)
	dungeon.free()


func _load_meta() -> Dictionary:
	assert_bool(FileAccess.file_exists(META_PATH)) \
		.override_failure_message("关卡0地牢 terrain atlas metadata 缺失: %s" % META_PATH) \
		.is_true()
	var file := FileAccess.open(META_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert_bool(parsed is Dictionary).is_true()
	return parsed as Dictionary


func _edge_delta(image: Image, horizontal: bool) -> int:
	var total := 0
	var count := image.get_height() if horizontal else image.get_width()
	for i in range(count):
		var a := image.get_pixel(0, i) if horizontal else image.get_pixel(i, 0)
		var b := image.get_pixel(image.get_width() - 1, i) if horizontal else image.get_pixel(i, image.get_height() - 1)
		total += abs(_luminance(a) - _luminance(b))
	return int(round(float(total) / float(count)))


func _luminance(color: Color) -> int:
	return int(round((color.r * 0.299 + color.g * 0.587 + color.b * 0.114) * 255.0))


func _is_boss_marker_pixel(color: Color) -> bool:
	var lum := _luminance(color)
	var neutral_iron = abs(color.r - color.g) < 0.08 and abs(color.g - color.b) < 0.08 and lum >= 25 and lum < 145
	var purple_eye = color.b > color.r and color.r > color.g and lum < 65
	return neutral_iron or purple_eye


func _is_old_wood_pixel(color: Color) -> bool:
	var lum := _luminance(color)
	return color.r > color.g and color.g >= color.b and lum < 120
