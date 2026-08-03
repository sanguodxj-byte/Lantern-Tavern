extends GdUnitTestSuite

## 符文之语图标契约：华丽圣匣卡面必须与普通符文卡视觉分层不同。

const RWG := preload("res://data/rune_word_glyphs.gd")
const RWD := preload("res://globals/combat/rune_word_data.gd")


func test_all_rune_words_generate_128_textures() -> void:
	for word_id in RWD.get_all_rune_word_ids():
		var tex: Texture2D = RWG.get_texture(String(word_id))
		assert_object(tex).override_failure_message("符文之语图标为空: %s" % word_id).is_not_null()
		assert_int(tex.get_width()).is_equal(128)
		assert_int(tex.get_height()).is_equal(128)


func test_logical_image_uses_octagon_and_opaque_reliquary_center() -> void:
	var image: Image = RWG.get_logical_image("thunder_run")
	assert_int(image.get_width()).is_equal(32)
	assert_int(image.get_height()).is_equal(32)
	for corner in [Vector2i(0, 0), Vector2i(31, 0), Vector2i(0, 31), Vector2i(31, 31), Vector2i(1, 1), Vector2i(30, 1), Vector2i(1, 30), Vector2i(30, 30)]:
		assert_bool(is_zero_approx(image.get_pixelv(corner).a)) \
			.override_failure_message("圣匣外部应保留透明切角: %s" % corner).is_true()
	assert_bool(is_equal_approx(image.get_pixelv(Vector2i(16, 16)).a, 1.0)).is_true()
	assert_bool(is_equal_approx(image.get_pixelv(Vector2i(5, 16)).a, 1.0)).is_true()


func test_only_recipe_gems_use_square_node_primitive() -> void:
	var source: String = (load("res://data/rune_word_glyphs.gd") as GDScript).source_code
	var recipe_start := source.find("static func _draw_recipe_gems")
	var recipe_end := source.find("static func _draw_ornaments")
	assert_bool(recipe_start >= 0 and recipe_end > recipe_start).is_true()
	var before_recipe := source.substr(0, recipe_start)
	var recipe_section := source.substr(recipe_start, recipe_end - recipe_start)
	assert_bool(not before_recipe.contains("_node(img")) \
		.override_failure_message("底部配方区之前禁止绘制叠加方块节点").is_true()
	assert_bool(recipe_section.contains("_node(img, center")) \
		.override_failure_message("底部配方宝石必须保留方块节点").is_true()
	assert_int(source.count("_node(img")).is_equal(2)


func test_reliquary_uses_hard_edge_opaque_pixels() -> void:
	var image: Image = RWG.get_logical_image("dipasamrakshana")
	for y in image.get_height():
		for x in image.get_width():
			var alpha := image.get_pixel(x, y).a
			assert_bool(is_zero_approx(alpha) or is_equal_approx(alpha, 1.0)) \
				.override_failure_message("禁止半透明像素: %d,%d alpha=%f" % [x, y, alpha]).is_true()


func test_theme_and_recipe_make_word_styles_distinct() -> void:
	var kinetic: Dictionary = RWG.get_style("thunder_run")
	var holy: Dictionary = RWG.get_style("dipasamrakshana")
	var dark: Dictionary = RWG.get_style("raudrabhaya")
	assert_str(String(kinetic.get("theme", ""))).is_equal("kinetic")
	assert_str(String(holy.get("theme", ""))).is_equal("holy")
	assert_str(String(dark.get("theme", ""))).is_equal("dark")
	assert_bool(kinetic != holy and holy != dark).is_true()


func test_128_texture_uses_nearest_neighbor_blocks() -> void:
	var image: Image = RWG.get_texture("vajraparajala").get_image()
	for block_y in 32:
		for block_x in 32:
			var expected := image.get_pixel(block_x * 4, block_y * 4)
			for local_y in 4:
				for local_x in 4:
					assert_bool(image.get_pixel(block_x * 4 + local_x, block_y * 4 + local_y).is_equal_approx(expected)) \
						.override_failure_message("非 4px 整块: %d,%d" % [block_x, block_y]).is_true()


func test_all_word_images_are_not_identical() -> void:
	var signatures: Dictionary = {}
	for word_id in RWD.get_all_rune_word_ids():
		var image: Image = RWG.get_logical_image(String(word_id))
		var key := str(hash(image.get_data()))
		assert_bool(not signatures.has(key)) \
			.override_failure_message("符文之语完整卡面重复: %s 与 %s" % [signatures.get(key, ""), word_id]).is_true()
		signatures[key] = String(word_id)


func test_glyphs_are_deterministic_and_cache_by_size() -> void:
	var first: Image = RWG.get_texture("echoing").get_image()
	RWG.clear_cache()
	var second: Image = RWG.get_texture("echoing").get_image()
	for p in [Vector2i(16, 16), Vector2i(5, 16), Vector2i(16, 3), Vector2i(11, 25)]:
		assert_bool(first.get_pixelv(p).is_equal_approx(second.get_pixelv(p))).is_true()
	var small: Texture2D = RWG.get_texture("echoing", 32)
	assert_int(small.get_width()).is_equal(32)
