extends GdUnitTestSuite

## 符文图标程序化生成器的契约测试。
## 验证：128×128、32×32 逻辑栅格、切角透明而中心卡面不透明、硬边像素层、专属色与确定性。

const RG := preload("res://data/rune_glyphs.gd")
const RD := preload("res://globals/combat/rune_data.gd")


func test_get_texture_returns_valid_128() -> void:
	var tex: Texture2D = RG.get_texture("ember")
	assert_object(tex).is_not_null()
	assert_int(tex.get_width()).is_equal(128)
	assert_int(tex.get_height()).is_equal(128)


func test_all_runes_have_procedural_texture() -> void:
	for rune_id in RD.get_all_rune_ids():
		var tex: Texture2D = RG.get_texture(String(rune_id))
		assert_object(tex).override_failure_message("符文程序化图标为空: %s" % rune_id).is_not_null()
		assert_bool(tex.get_width() == 128 and tex.get_height() == 128) \
			.override_failure_message("%s 图标非 128px" % rune_id).is_true()


func test_glyph_draws_colored_pixels() -> void:
	var tex: Texture2D = RG.get_texture("vajra")
	var img := tex.get_image()
	assert_object(img).is_not_null()
	var drawn := false
	for y in range(0, img.get_height(), 3):
		for x in range(0, img.get_width(), 3):
			if img.get_pixel(x, y).a > 0.5:
				drawn = true
				break
		if drawn:
			break
	assert_bool(drawn).override_failure_message("程序化图标未画出可见像素").is_true()


func test_glyph_uses_rune_color() -> void:
	var rune_id := "ember"
	var tex: Texture2D = RG.get_texture(rune_id)
	var img := tex.get_image()
	var expected := Color.from_string(RD.get_rune_color(rune_id), Color.WHITE)
	var found_expected := false
	for y in range(0, img.get_height()):
		for x in range(0, img.get_width()):
			if img.get_pixel(x, y).is_equal_approx(expected):
				found_expected = true
				break
		if found_expected:
			break
	assert_bool(found_expected) \
		.override_failure_message("符文图标未使用专属色 %s" % expected).is_true()


func test_logical_image_contract() -> void:
	var img: Image = RG.get_logical_image("ember")
	assert_int(img.get_width()).is_equal(32)
	assert_int(img.get_height()).is_equal(32)
	assert_int(img.get_format()).is_equal(Image.FORMAT_RGBA8)
	var visible_count := 0
	for y in img.get_height():
		for x in img.get_width():
			var alpha := img.get_pixel(x, y).a
			assert_bool(is_zero_approx(alpha) or is_equal_approx(alpha, 1.0)) \
				.override_failure_message("逻辑像素禁止半透明: %d,%d alpha=%f" % [x, y, alpha]).is_true()
			if alpha > 0.5:
				visible_count += 1
	assert_bool(visible_count > 400 and visible_count < 900) \
		.override_failure_message("完整卡面可见像素量异常: %d" % visible_count).is_true()


func test_card_uses_cut_corner_transparency_and_opaque_center() -> void:
	for rune_id in RD.get_all_rune_ids():
		var img: Image = RG.get_logical_image(String(rune_id))
		for p in [Vector2i(0, 0), Vector2i(31, 0), Vector2i(0, 31), Vector2i(31, 31), Vector2i(1, 16), Vector2i(30, 16)]:
			assert_bool(is_zero_approx(img.get_pixelv(p).a)) \
				.override_failure_message("%s 切角外必须透明: %s" % [rune_id, p]).is_true()
		assert_bool(is_equal_approx(img.get_pixelv(Vector2i(16, 16)).a, 1.0)) \
			.override_failure_message("%s 卡面中心不得透明" % rune_id).is_true()


func test_card_has_background_and_metal_frame() -> void:
	var img: Image = RG.get_logical_image("ember")
	var background := img.get_pixelv(Vector2i(8, 8))
	var frame := img.get_pixelv(Vector2i(5, 16))
	assert_bool(background.a > 0.5).is_true()
	assert_bool(frame.a > 0.5).is_true()
	assert_bool(not background.is_equal_approx(frame)) \
		.override_failure_message("背景与边框不能是同一色块").is_true()


func test_128_texture_uses_4px_nearest_neighbor_blocks() -> void:
	var img: Image = RG.get_texture("vajra").get_image()
	for block_y in 32:
		for block_x in 32:
			var expected := img.get_pixel(block_x * 4, block_y * 4)
			for local_y in 4:
				for local_x in 4:
					var actual := img.get_pixel(block_x * 4 + local_x, block_y * 4 + local_y)
					assert_bool(actual.is_equal_approx(expected)) \
						.override_failure_message("非 4px 整块: %d,%d" % [block_x, block_y]).is_true()


func test_default_size_fallback_and_cache_key_include_size() -> void:
	var fallback: Texture2D = RG.get_texture("ember", 0)
	var small: Texture2D = RG.get_texture("ember", 32)
	assert_int(fallback.get_width()).is_equal(128)
	assert_int(small.get_width()).is_equal(32)
	assert_bool(fallback != small).is_true()


func test_glyph_is_deterministic() -> void:
	var a := RG.get_glyph("krishna")
	var b := RG.get_glyph("krishna")
	assert_int(a.size()).is_equal(b.size())
	for i in range(a.size()):
		assert_dict(a[i]).is_equal(b[i])


func test_unknown_rune_still_draws() -> void:
	var tex: Texture2D = RG.get_texture("__nope__")
	assert_object(tex).is_not_null()
	assert_int(tex.get_width()).is_equal(128)
	assert_int(tex.get_height()).is_equal(128)
