extends GdUnitTestSuite
## 武器材质适配回归：保留金属/木柄对比，缓存复用，装备路径走 weapon 模式。

const VOXEL_LIGHTING := preload("res://globals/visual/voxel_lighting_adapter.gd")


func before_test() -> void:
	VOXEL_LIGHTING.clear_cache()


func test_apply_weapon_tree_api_exists_in_source() -> void:
	var src := FileAccess.get_file_as_string("res://globals/visual/voxel_lighting_adapter.gd")
	assert_bool(src.contains("func apply_weapon_tree")).is_true()
	assert_bool(src.contains("material_tier: String")).is_true()
	assert_bool(src.contains("MODE_WEAPON")).is_true()
	assert_bool(src.contains("func adapt_standard_material")).is_true()


func test_equiped_item_uses_weapon_tree() -> void:
	var src := FileAccess.get_file_as_string("res://scenes/equipment/equiped_item.gd")
	assert_bool(src.contains("apply_weapon_tree")).is_true()


func test_view_model_uses_weapon_tree() -> void:
	var src := FileAccess.get_file_as_string("res://scenes/characters/player/view_model.gd")
	assert_bool(src.contains("apply_weapon_tree")).is_true()


func test_pickable_and_thrown_use_weapon_tree_for_weapons() -> void:
	var pickable := FileAccess.get_file_as_string("res://scenes/equipment/pickable_item.gd")
	assert_bool(pickable.contains("apply_weapon_tree")).is_true()
	var thrown := FileAccess.get_file_as_string("res://scenes/equipment/thrown_item.gd")
	assert_bool(thrown.contains("apply_weapon_tree")).is_true()


func test_default_mode_still_kills_metal() -> void:
	var mat := StandardMaterial3D.new()
	mat.metallic = 0.9
	mat.roughness = 0.2
	var adapted := VOXEL_LIGHTING.adapt_standard_material(mat, VOXEL_LIGHTING.MODE_DEFAULT)
	assert_float(adapted.metallic).is_equal_approx(0.0, 0.001)
	assert_float(adapted.roughness).is_greater_equal(0.85)


func test_weapon_mode_steel_vs_grip_contrast() -> void:
	var steel := StandardMaterial3D.new()
	steel.resource_name = "steel"
	steel.metallic = 0.9
	steel.roughness = 0.28
	steel.albedo_color = Color(0.62, 0.64, 0.68)
	var grip := StandardMaterial3D.new()
	grip.resource_name = "grip"
	grip.metallic = 0.0
	grip.roughness = 0.9
	grip.albedo_color = Color(0.3, 0.16, 0.08)
	var a_steel := VOXEL_LIGHTING.adapt_standard_material(steel, VOXEL_LIGHTING.MODE_WEAPON)
	var a_grip := VOXEL_LIGHTING.adapt_standard_material(grip, VOXEL_LIGHTING.MODE_WEAPON)
	assert_float(a_steel.metallic).is_greater(0.5)
	assert_float(a_grip.metallic).is_equal_approx(0.0, 0.001)
	assert_float(a_steel.roughness).is_less(a_grip.roughness)


func test_weapon_mode_detects_metal_by_name_when_metallic_low() -> void:
	# 部分导出可能丢失 metallic 字段，靠材质名识别
	var blade := StandardMaterial3D.new()
	blade.resource_name = "metal_bright"
	blade.metallic = 0.0
	blade.roughness = 0.3
	var adapted := VOXEL_LIGHTING.adapt_standard_material(blade, VOXEL_LIGHTING.MODE_WEAPON)
	assert_float(adapted.metallic).is_greater_equal(0.55)


func test_is_metal_helper_thresholds() -> void:
	var high := StandardMaterial3D.new()
	high.metallic = 0.8
	assert_bool(VOXEL_LIGHTING._is_metal_material(high)).is_true()
	var low := StandardMaterial3D.new()
	low.metallic = 0.0
	low.resource_name = "wood"
	assert_bool(VOXEL_LIGHTING._is_metal_material(low)).is_false()


func test_weapon_material_cache_reuses_instance() -> void:
	VOXEL_LIGHTING.clear_cache()
	var steel := StandardMaterial3D.new()
	steel.resource_name = "blade_steel"
	steel.metallic = 0.85
	steel.roughness = 0.3
	steel.albedo_color = Color(0.55, 0.55, 0.58)
	var a1 := VOXEL_LIGHTING.adapt_standard_material(steel, VOXEL_LIGHTING.MODE_WEAPON)
	var a2 := VOXEL_LIGHTING.adapt_standard_material(steel, VOXEL_LIGHTING.MODE_WEAPON)
	assert_bool(a1 == a2).is_true()
	var stats: Dictionary = VOXEL_LIGHTING.get_cache_stats()
	assert_int(int(stats["hits"])).is_greater_equal(1)


func test_canonical_material_tiers_produce_distinct_weapon_variants() -> void:
	VOXEL_LIGHTING.clear_cache()
	var blade := StandardMaterial3D.new()
	blade.resource_name = "blade_steel"
	blade.metallic = 0.85
	blade.roughness = 0.3
	blade.albedo_color = Color(0.55, 0.58, 0.62)
	var variants: Array[StandardMaterial3D] = []
	for material_tier in ["wood", "iron", "steel", "meteoric", "mithril", "adamantite"]:
		variants.append(VOXEL_LIGHTING.adapt_standard_material(
			blade,
			VOXEL_LIGHTING.MODE_WEAPON,
			material_tier,
		))
	for index in range(variants.size()):
		for other_index in range(index + 1, variants.size()):
			var distance := _color_distance(variants[index].albedo_color, variants[other_index].albedo_color)
			assert_bool(distance > 0.08) \
				.override_failure_message("material tiers are visually too close: %d vs %d (%s vs %s)" % [index, other_index, variants[index].albedo_color, variants[other_index].albedo_color]).is_true()
	assert_float(variants[0].metallic).is_equal_approx(0.58, 0.001)
	assert_float(variants[5].metallic).is_equal_approx(0.94, 0.001)
	assert_float(variants[0].roughness).is_greater(variants[4].roughness)
	assert_float(variants[4].roughness).is_less(variants[1].roughness)


func test_embedded_shield_material_variants_receive_runtime_tier_without_losing_identity() -> void:
	var shield_material := StandardMaterial3D.new()
	shield_material.resource_name = "shield_material_meteoric"
	shield_material.albedo_texture = ImageTexture.create_from_image(Image.create(2, 2, false, Image.FORMAT_RGBA8))
	shield_material.metallic = 0.91
	shield_material.albedo_color = Color(0.15, 0.18, 0.20)
	var baseline := VOXEL_LIGHTING.adapt_standard_material(
		shield_material,
		VOXEL_LIGHTING.MODE_WEAPON,
	)
	var adapted := VOXEL_LIGHTING.adapt_standard_material(
		shield_material,
		VOXEL_LIGHTING.MODE_WEAPON,
		"adamantite",
	)
	assert_bool(adapted.albedo_color != baseline.albedo_color).is_true()
	assert_float(adapted.metallic).is_equal_approx(0.94, 0.001)
	var wood := VOXEL_LIGHTING.adapt_standard_material(
		shield_material,
		VOXEL_LIGHTING.MODE_WEAPON,
		"wood",
	)
	# shield_material_meteoric 是原生背面硬件，不应在木盾档被刷成木头。
	assert_float(wood.metallic).is_greater(0.5)
	assert_float(wood.roughness).is_equal_approx(0.55, 0.001)
	assert_object(wood.albedo_texture).is_not_null()


func test_staff_textured_body_switches_to_high_tier_surface_color() -> void:
	var staff_body := StandardMaterial3D.new()
	staff_body.resource_name = "staff_wine_leather_crosshatch"
	staff_body.albedo_texture = ImageTexture.create_from_image(Image.create(2, 2, false, Image.FORMAT_RGBA8))
	var wood := VOXEL_LIGHTING.adapt_standard_material(
		staff_body,
		VOXEL_LIGHTING.MODE_WEAPON,
		"wood",
	)
	var mithril := VOXEL_LIGHTING.adapt_standard_material(
		staff_body,
		VOXEL_LIGHTING.MODE_WEAPON,
		"mithril",
	)
	assert_object(wood.albedo_texture).is_not_null()
	assert_object(mithril.albedo_texture).is_not_null()
	assert_float(mithril.metallic).is_equal_approx(0.96, 0.001)
	assert_bool(mithril.albedo_color != wood.albedo_color).is_true()


func test_crossbow_wood_grain_is_preserved_and_upgrades_become_metal() -> void:
	var stock := StandardMaterial3D.new()
	stock.resource_name = "crossbow_walnut_grain"
	stock.albedo_texture = ImageTexture.create_from_image(Image.create(2, 2, false, Image.FORMAT_RGBA8))
	stock.roughness = 0.88
	var wood := VOXEL_LIGHTING.adapt_standard_material(
		stock,
		VOXEL_LIGHTING.MODE_WEAPON,
		"wood",
	)
	var adamantite := VOXEL_LIGHTING.adapt_standard_material(
		stock,
		VOXEL_LIGHTING.MODE_WEAPON,
		"adamantite",
	)
	assert_object(wood.albedo_texture).is_not_null()
	assert_float(wood.metallic).is_equal_approx(0.0, 0.001)
	assert_float(wood.roughness).is_equal_approx(0.88, 0.001)
	assert_object(adamantite.albedo_texture).is_not_null()
	assert_float(adamantite.metallic).is_equal_approx(0.94, 0.001)
	assert_bool(adamantite.albedo_color != wood.albedo_color).is_true()


func test_grimoire_parchment_and_leather_follow_material_tiers() -> void:
	for material_name in ["grimoire_parchment_pages", "grimoire_leather_spine"]:
		var source := StandardMaterial3D.new()
		source.resource_name = material_name
		source.albedo_texture = ImageTexture.create_from_image(Image.create(2, 2, false, Image.FORMAT_RGBA8))
		var wood := VOXEL_LIGHTING.adapt_standard_material(
			source,
			VOXEL_LIGHTING.MODE_WEAPON,
			"wood",
		)
		var adamantite := VOXEL_LIGHTING.adapt_standard_material(
			source,
			VOXEL_LIGHTING.MODE_WEAPON,
			"adamantite",
		)
		assert_float(wood.metallic).is_equal_approx(0.0, 0.001)
		assert_object(wood.albedo_texture).is_not_null()
		assert_float(adamantite.metallic).is_equal_approx(0.94, 0.001)
		assert_object(adamantite.roughness_texture).is_not_null()
		assert_object(adamantite.normal_texture).is_not_null()
		assert_bool(adamantite.albedo_color != wood.albedo_color).is_true()


func test_metal_finish_texture_has_visible_surface_variation() -> void:
	for material_tier in ["iron", "steel", "meteoric", "mithril", "adamantite"]:
		var source := StandardMaterial3D.new()
		source.resource_name = "crossbow_walnut_grain"
		var adapted := VOXEL_LIGHTING.adapt_standard_material(
			source,
			VOXEL_LIGHTING.MODE_WEAPON,
			material_tier,
		)
		assert_object(adapted.albedo_texture).is_not_null()
		assert_object(adapted.roughness_texture).is_not_null()
		assert_object(adapted.normal_texture).is_not_null()
		assert_float(adapted.normal_scale).is_equal_approx(0.35, 0.001)
		var finish := adapted.albedo_texture.get_image()
		var min_luma := 1.0
		var max_luma := 0.0
		for y in range(finish.get_height()):
			for x in range(finish.get_width()):
				var pixel := finish.get_pixel(x, y)
				var luma := (pixel.r + pixel.g + pixel.b) / 3.0
				min_luma = minf(min_luma, luma)
				max_luma = maxf(max_luma, luma)
		assert_bool(max_luma - min_luma > 0.04) \
			.override_failure_message("flat finish texture for tier: %s" % material_tier).is_true()


func test_wood_grain_contrast_is_reduced_without_removing_texture() -> void:
	var grain := Image.create(2, 1, false, Image.FORMAT_RGBA8)
	grain.set_pixel(0, 0, Color(0.08, 0.04, 0.02, 1.0))
	grain.set_pixel(1, 0, Color(0.92, 0.70, 0.35, 1.0))
	var stock := StandardMaterial3D.new()
	stock.resource_name = "crossbow_walnut_grain"
	stock.albedo_texture = ImageTexture.create_from_image(grain)
	var wood := VOXEL_LIGHTING.adapt_standard_material(
		stock,
		VOXEL_LIGHTING.MODE_WEAPON,
		"wood",
	)
	assert_object(wood.albedo_texture).is_not_null()
	var adapted_image := wood.albedo_texture.get_image()
	var source_contrast := _color_distance(grain.get_pixel(0, 0), grain.get_pixel(1, 0))
	var adapted_contrast := _color_distance(adapted_image.get_pixel(0, 0), adapted_image.get_pixel(1, 0))
	assert_bool(adapted_contrast < source_contrast).is_true()


func test_shield_surface_roles_keep_tone_separation_on_metal_upgrade() -> void:
	var role_colors: Array[Color] = []
	for material_name in [
		"shield_material_wood_grain",
		"shield_material_wood_shadow",
		"shield_material_wood_endgrain",
		"shield_material_wood_leather_grip",
	]:
		var source := StandardMaterial3D.new()
		source.resource_name = material_name
		source.albedo_color = Color.WHITE
		var adapted := VOXEL_LIGHTING.adapt_standard_material(
			source,
			VOXEL_LIGHTING.MODE_WEAPON,
			"adamantite",
		)
		role_colors.append(adapted.albedo_color)
	for index in range(role_colors.size()):
		for other_index in range(index + 1, role_colors.size()):
			assert_bool(_color_distance(role_colors[index], role_colors[other_index]) > 0.035) \
				.override_failure_message("shield surface roles collapsed: %d vs %d" % [index, other_index]).is_true()


func _color_distance(left: Color, right: Color) -> float:
	return absf(left.r - right.r) + absf(left.g - right.g) + absf(left.b - right.b)
