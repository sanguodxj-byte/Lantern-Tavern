extends GdUnitTestSuite

const ALLOWED_EMISSIVE_SCENES := [
	"res://scenes/props/dungeon/decor/floor_candelabrum.tscn",
	"res://scenes/props/dungeon/decor/wall_candelabrum.tscn",
	"res://scenes/props/decor/lit_candles.tscn",
	"res://scenes/traps/acid_trap.tscn",
	"res://fx/rune_hit_burst.tscn",
	"res://fx/status_aura.tscn",
]

const GENERATOR_EMISSION_ALLOWLIST := [
	# No current Blender generator represents an active in-world light source.
]

const NON_LIGHT_GLB_CONTRACT := [
	"res://assets/models/props/props_ritual_totem.glb",
	"res://assets/meshes/weapons/weapons_voxel_staff.glb",
	"res://assets/meshes/weapons/weapons_voxel_grimoire.glb",
	"res://assets/meshes/traps/traps_spikes_trap.glb",
	"res://assets/meshes/traps/traps_acid_trap.glb",
	"res://assets/meshes/traps/traps_flame_vent.glb",
]


func test_non_light_generators_do_not_author_emission() -> void:
	var directory := DirAccess.open("res://tools")
	assert_object(directory).is_not_null()
	for file_name in directory.get_files():
		if not file_name.begins_with("generate_voxel_") or not file_name.ends_with(".py"):
			continue
		if GENERATOR_EMISSION_ALLOWLIST.has(file_name):
			continue
		var source := FileAccess.get_file_as_string("res://tools/%s" % file_name)
		assert_str(source) \
			.override_failure_message("旧资产生成器禁止 emission 参数: %s" % file_name) \
			.not_contains("emission=")


func test_checked_non_light_glbs_have_no_emissive_extensions() -> void:
	for path in NON_LIGHT_GLB_CONTRACT:
		_assert_glb_has_no_emission(path)


func test_all_legacy_character_material_trap_and_weapon_glbs_are_non_emissive() -> void:
	for directory_path in [
		"res://assets/models/materials",
		"res://assets/meshes/characters",
		"res://assets/meshes/traps",
		"res://assets/meshes/weapons",
	]:
		var directory := DirAccess.open(directory_path)
		assert_object(directory).is_not_null()
		for file_name in directory.get_files():
			if file_name.ends_with(".glb"):
				_assert_glb_has_no_emission("%s/%s" % [directory_path, file_name])


func test_emissive_scene_resources_are_explicit_light_sources() -> void:
	for path in ALLOWED_EMISSIVE_SCENES:
		var source := FileAccess.get_file_as_string(path)
		assert_str(source).contains("emission_enabled = true")
		assert_bool(source.contains("OmniLight3D") or source.contains("SpotLight3D")) \
			.override_failure_message("允许发光的场景必须同时包含真实 Light3D: %s" % path) \
			.is_true()


func test_static_material_resources_are_non_emissive() -> void:
	for path in [
		"res://materials/fire_bloom_mat.tres",
		"res://materials/glow_material.tres",
		"res://materials/portal_mat.tres",
		"res://materials/troll_blood_mat.tres",
		"res://materials/wild_glowcap_mat.tres",
	]:
		var source := FileAccess.get_file_as_string(path)
		assert_str(source).not_contains("emission_enabled = true")
		assert_str(source).not_contains("emission_energy_multiplier")


func test_imported_and_first_person_material_adapters_disable_emission() -> void:
	var adapter_source := FileAccess.get_file_as_string("res://globals/visual/voxel_lighting_adapter.gd")
	assert_str(adapter_source).contains("copy.emission_enabled = false")
	assert_str(adapter_source).contains("copy.emission_texture = null")
	var view_source := FileAccess.get_file_as_string("res://scenes/characters/player/view_model.gd")
	assert_str(view_source).contains("copy.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL")
	assert_str(view_source).contains("copy.emission_enabled = false")


func _assert_glb_has_no_emission(path: String) -> void:
	var text := FileAccess.get_file_as_bytes(path).get_string_from_utf8()
	assert_str(text).override_failure_message("非光源 GLB 禁止 emissiveFactor: %s" % path).not_contains("emissiveFactor")
	assert_str(text).override_failure_message("非光源 GLB 禁止 emissive strength: %s" % path).not_contains("KHR_materials_emissive_strength")
