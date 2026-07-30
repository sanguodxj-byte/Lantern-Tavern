extends GdUnitTestSuite

## 符文图标程序化生成器的单元测试。
## 验证：每个符文都能在运行时生成有效纹理、画出了专属色像素、且同一符文确定可复现。

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
	var sampled := Color(0, 0, 0, 0)
	for y in range(0, img.get_height()):
		for x in range(0, img.get_width()):
			var c := img.get_pixel(x, y)
			if c.a > 0.5:
				sampled = c
				break
		if sampled.a > 0.5:
			break
	assert_bool(sampled.a > 0.5).is_true()
	assert_bool(sampled.is_equal_approx(expected)) \
		.override_failure_message("符文图标未使用专属色 %s" % expected).is_true()


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
