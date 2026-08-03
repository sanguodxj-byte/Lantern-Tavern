extends GdUnitTestSuite

# Tests for voxel trap models: verifies generator scripts, GLB assets,
# preview images, and scene integration for spikes_trap, acid_trap,
# and flame_vent traps.

const TRAP_DEFS := [
	{
		"model_id": "spikes_trap",
		"generator": "res://tools/generate_voxel_spikes_trap.py",
		"glb": "res://assets/meshes/traps/traps_spikes_trap.glb",
		"scene": "res://scenes/traps/spikes_trap.tscn",
		"preview_prefix": "voxel_spikes_trap_render",
	},
	{
		"model_id": "acid_trap",
		"generator": "res://tools/generate_voxel_acid_trap.py",
		"glb": "res://assets/meshes/traps/traps_acid_trap.glb",
		"scene": "res://scenes/traps/acid_trap.tscn",
		"preview_prefix": "voxel_acid_trap_render",
	},
	{
		"model_id": "flame_vent",
		"generator": "res://tools/generate_voxel_flame_vent.py",
		"glb": "res://assets/meshes/traps/traps_flame_vent.glb",
		"scene": "res://scenes/traps/flame_vent_trap.tscn",
		"preview_prefix": "voxel_flame_vent_render",
	},
]


# ── Generator Script Tests ──────────────────────────────────────────────

func test_spikes_trap_generator_exists_and_valid() -> void:
	_assert_generator_valid(TRAP_DEFS[0])


func test_acid_trap_generator_exists_and_valid() -> void:
	_assert_generator_valid(TRAP_DEFS[1])


func test_flame_vent_generator_exists_and_valid() -> void:
	_assert_generator_valid(TRAP_DEFS[2])


func _assert_generator_valid(def: Dictionary) -> void:
	assert_bool(FileAccess.file_exists(def.generator)).is_true()
	var source := FileAccess.get_file_as_string(def.generator)
	assert_str(source).contains('MODEL_ID = "%s"' % def.model_id)
	assert_str(source).contains("reject_target_override")
	# Enforce single-model workflow — no batch target override
	assert_str(source).contains("OUT_GLB")


# ── GLB Asset Tests ─────────────────────────────────────────────────────

func test_spikes_trap_glb_exists_and_loads() -> void:
	_assert_glb_valid(TRAP_DEFS[0])


func test_acid_trap_glb_exists_and_loads() -> void:
	_assert_glb_valid(TRAP_DEFS[1])


func test_flame_vent_glb_exists_and_loads() -> void:
	_assert_glb_valid(TRAP_DEFS[2])


func _assert_glb_valid(def: Dictionary) -> void:
	assert_bool(FileAccess.file_exists(def.glb)).is_true()
	var glb := load(def.glb)
	assert_object(glb).is_not_null()
	assert_object(glb).is_instanceof(PackedScene)


# ── Preview Image Tests ─────────────────────────────────────────────────

func test_spikes_trap_preview_images_exist() -> void:
	_assert_previews_exist(TRAP_DEFS[0])


func test_acid_trap_preview_images_exist() -> void:
	_assert_previews_exist(TRAP_DEFS[1])


func test_flame_vent_preview_images_exist() -> void:
	_assert_previews_exist(TRAP_DEFS[2])


func _assert_previews_exist(def: Dictionary) -> void:
	for view in ["front", "side", "top"]:
		var path := "res://reports/traps_preview/%s_%s.png" % [def.preview_prefix, view]
		assert_bool(FileAccess.file_exists(path)).is_true()


# ── Scene Integration Tests ─────────────────────────────────────────────

func test_spikes_trap_scene_uses_voxel_model() -> void:
	_assert_scene_has_voxel_model(TRAP_DEFS[0])


func test_acid_trap_scene_uses_voxel_model() -> void:
	_assert_scene_has_voxel_model(TRAP_DEFS[1])


func test_flame_vent_scene_uses_voxel_model() -> void:
	_assert_scene_has_voxel_model(TRAP_DEFS[2])


func _assert_scene_has_voxel_model(def: Dictionary) -> void:
	assert_bool(FileAccess.file_exists(def.scene)).is_true()
	var scene := load(def.scene) as PackedScene
	assert_object(scene).is_not_null()

	var trap: Node = auto_free(scene.instantiate()) as Node
	assert_bool(trap is Area3D).is_true()

	# VoxelModel child must exist (the GLB instance)
	var voxel_model := (trap as Node).find_child("VoxelModel", true, false)
	assert_object(voxel_model).is_not_null()

	# CollisionShape3D must exist for trap detection
	var col := (trap as Node).find_child("CollisionShape3D", true, false)
	assert_object(col).is_not_null()
	assert_object((col as CollisionShape3D).shape).is_not_null()


# ── Generator Independence Tests (one model per generator) ──────────────

func test_each_generator_has_unique_model_id() -> void:
	var ids: Array[String] = []
	for def in TRAP_DEFS:
		var source := FileAccess.get_file_as_string(def.generator)
		var id := 'MODEL_ID = "%s"' % def.model_id
		assert_str(source).contains(id)
		ids.append(def.model_id)
	# All model IDs must be unique
	var unique := {}
	for id in ids:
		assert_bool(not unique.has(id)).is_true()
		unique[id] = true
	assert_int(unique.size()).is_equal(TRAP_DEFS.size())


func test_trap_meshes_are_non_emissive_even_when_scene_has_real_lights() -> void:
	for def in TRAP_DEFS:
		var bytes := FileAccess.get_file_as_bytes(def.glb)
		var text := bytes.get_string_from_utf8()
		assert_str(text) \
			.override_failure_message("陷阱实体模型不是光源，GLB 禁止 emissiveFactor: %s" % def.glb) \
			.not_contains("emissiveFactor")
		assert_str(text) \
			.override_failure_message("陷阱实体模型不是光源，GLB 禁止 emissive strength: %s" % def.glb) \
			.not_contains("KHR_materials_emissive_strength")


func test_only_true_trap_light_sources_use_emissive_visuals() -> void:
	var acid_source := FileAccess.get_file_as_string("res://scenes/traps/acid_trap.tscn")
	assert_str(acid_source).contains("OmniLight3D")
	assert_str(acid_source).contains("emission_enabled = true")
	var flame_source := FileAccess.get_file_as_string("res://scenes/traps/flame_vent_trap.tscn")
	assert_str(flame_source).contains("FlameLight")
	var spikes_source := FileAccess.get_file_as_string("res://scenes/traps/spikes_trap.tscn")
	assert_str(spikes_source).not_contains("emission_enabled = true")
