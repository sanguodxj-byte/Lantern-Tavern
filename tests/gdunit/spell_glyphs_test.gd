extends GdUnitTestSuite
const Glyphs := preload("res://data/spell_glyphs.gd")
const Recipes := preload("res://globals/combat/spell_recipe_data.gd")

func test_all_spells_have_imagery_and_128_icons() -> void:
	for spell in Recipes.get_all_recipes():
		var id := String(spell.get("id", ""))
		assert_str(String(spell.get("imagery", ""))).is_not_empty()
		var tex: Texture2D = Glyphs.get_texture(id)
		assert_object(tex).is_not_null()
		assert_int(tex.get_width()).is_equal(128)
		assert_int(tex.get_height()).is_equal(128)

func test_all_spell_icons_are_independent() -> void:
	var seen: Dictionary = {}
	for id in Glyphs.get_all_spell_ids():
		var key := str(hash(Glyphs.get_logical_image(id).get_data()))
		assert_bool(not seen.has(key)).override_failure_message("法术图标重复: %s / %s" % [seen.get(key, ""), id]).is_true()
		seen[key] = id

func test_spell_icon_has_hard_alpha_and_nearest_blocks() -> void:
	var logical := Glyphs.get_logical_image("spell_fireball")
	for y in 32:
		for x in 32:
			var alpha := logical.get_pixel(x, y).a
			assert_bool(is_zero_approx(alpha) or is_equal_approx(alpha, 1.0)).is_true()
	var image := Glyphs.get_texture("spell_chain_lightning").get_image()
	for by in 32:
		for bx in 32:
			var expected := image.get_pixel(bx * 4, by * 4)
			for ly in 4:
				for lx in 4:
					assert_bool(image.get_pixel(bx * 4 + lx, by * 4 + ly).is_equal_approx(expected)).is_true()

func test_spell_interface_uses_spell_glyphs() -> void:
	var source := (load("res://scenes/ui/spell_interface.gd") as GDScript).source_code
	assert_bool(source.contains("SpellGlyphs.get_texture")).is_true()
