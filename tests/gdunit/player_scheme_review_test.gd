extends GdUnitTestSuite

## Review assets for five independent player redesign schemes (A-E).
## Production player remains unchanged until a scheme is selected.

const SCHEMES := [
	{"id": "player_scheme_a", "title": "Lantern Keeper"},
	{"id": "player_scheme_b", "title": "Road Freeblade"},
	{"id": "player_scheme_c", "title": "Lantern Initiate"},
	{"id": "player_scheme_d", "title": "Cellar Bruiser"},
	{"id": "player_scheme_e", "title": "Roofrunner Scout"},
]

const BODY_ONLY_FORBIDDEN_TOKENS := [
	"weapon_", "shield_", "sword_", "axe_", "staff_", "bow_", "crossbow_",
]


func test_each_scheme_has_independent_generator_and_static_glb() -> void:
	for scheme in SCHEMES:
		var id := String(scheme["id"])
		var gen_path := "res://tools/generate_voxel_%s.py" % id
		var glb_path := "res://assets/meshes/characters/voxel_%s.glb" % id
		assert_bool(FileAccess.file_exists(gen_path)) \
			.override_failure_message("missing generator: %s" % gen_path).is_true()
		assert_bool(FileAccess.file_exists(glb_path)) \
			.override_failure_message("missing glb: %s" % glb_path).is_true()
		var source := FileAccess.get_file_as_string(gen_path)
		assert_str(source).contains('MODEL_ID = "%s"' % id)
		assert_str(source).contains("reject_target_override(MODEL_ID)")
		assert_str(source).contains("assert_parts_no_positive_volume_overlap")
		assert_str(source).contains("assert_parts_single_face_connected_component")
		for forbidden in ["MODEL_REGISTRY", "for model_id in", "--all", "voxel_single_humanoid", "generic_body"]:
			assert_str(source).not_contains(forbidden)
		var glb_size := FileAccess.get_file_as_bytes(glb_path).size()
		assert_int(glb_size).is_greater(2000)


func test_each_scheme_has_real_render_views() -> void:
	for scheme in SCHEMES:
		var id := String(scheme["id"])
		for view in ["preview", "front", "side", "top"]:
			var path := "res://reports/characters_preview/voxel_%s_render_%s.png" % [id, view]
			assert_bool(FileAccess.file_exists(path)) \
				.override_failure_message("missing render: %s" % path).is_true()
			var img := Image.new()
			assert_int(img.load(path)).is_equal(OK)
			assert_int(img.get_width()).is_greater_equal(256)
			var lit := 0
			var step := maxi(1, img.get_width() / 32)
			for y in range(0, img.get_height(), step):
				for x in range(0, img.get_width(), step):
					var c := img.get_pixel(x, y)
					if c.a > 0.05 and (c.r + c.g + c.b) > 0.08:
						lit += 1
			assert_int(lit).is_greater(8)


func test_scheme_glbs_are_body_only_without_baked_weapons() -> void:
	for scheme in SCHEMES:
		var id := String(scheme["id"])
		var gen_path := "res://tools/generate_voxel_%s.py" % id
		var glb_path := "res://assets/meshes/characters/voxel_%s.glb" % id
		var source := FileAccess.get_file_as_string(gen_path)
		for token in BODY_ONLY_FORBIDDEN_TOKENS:
			assert_bool(source.to_lower().contains(token)) \
				.override_failure_message("%s generator mentions forbidden token: %s" % [id, token]) \
				.is_false()
		assert_bool(source.contains("hand_l") or source.contains("hand_r")).is_true()
		var bytes := FileAccess.get_file_as_bytes(glb_path)
		assert_int(bytes.size()).is_greater(2000)
		assert_int(bytes[0]).is_equal(0x67)
		assert_int(bytes[1]).is_equal(0x6C)
		assert_int(bytes[2]).is_equal(0x54)
		assert_int(bytes[3]).is_equal(0x46)


func test_scheme_generators_declare_distinct_identities() -> void:
	var titles: Dictionary = {}
	for scheme in SCHEMES:
		var id := String(scheme["id"])
		var source := FileAccess.get_file_as_string("res://tools/generate_voxel_%s.py" % id)
		var title := String(scheme["title"])
		var key := title.split(" ")[0].to_lower()
		assert_str(source.to_lower()).contains(key)
		titles[title] = true
	assert_int(titles.size()).is_equal(5)
