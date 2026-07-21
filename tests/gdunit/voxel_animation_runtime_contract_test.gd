extends GdUnitTestSuite

const ANIMATION_SPEC_PATH := "res://globals/visual/voxel_animation_spec.gd"
const PLAYER_SCRIPT_PATH := "res://scenes/characters/player/player.gd"
const ENEMY_SCRIPT_PATH := "res://scenes/characters/enemies/enemy.gd"

const REMOVED_RUNTIME_REPAIR_PATH := "res://globals/visual/animation_repair.gd"
const REMOVED_RIG_EXPERIMENT_PATHS := [
	"res://globals/visual/voxel_rig_spec.gd",
	"res://scenes/characters/component/voxel_rig_builder.gd",
	"res://scenes/characters/component/voxel_rig_animator.gd",
]

const FORBIDDEN_RUNTIME_REPAIR_MARKERS := [
	"animation_repair",
	"ANIM_REPAIR",
	"repair_all(",
	"add_track(",
	"add_animation(",
	"remove_animation(",
]


func _source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


func test_character_runtime_does_not_repair_missing_animation_tracks() -> void:
	assert_bool(FileAccess.file_exists(REMOVED_RUNTIME_REPAIR_PATH)) \
		.override_failure_message("runtime animation repair module must remain removed") \
		.is_false()
	for path in [PLAYER_SCRIPT_PATH, ENEMY_SCRIPT_PATH]:
		var source := _source(path)
		assert_bool(source.is_empty()) \
			.override_failure_message("character runtime source must be readable: %s" % path) \
			.is_false()
		for marker in FORBIDDEN_RUNTIME_REPAIR_MARKERS:
			assert_bool(source.contains(marker)) \
				.override_failure_message("%s must not synthesize animation data with %s" % [path, marker]) \
				.is_false()


func test_abandoned_runtime_rigid_rig_chain_is_removed() -> void:
	for path in REMOVED_RIG_EXPERIMENT_PATHS:
		assert_bool(FileAccess.file_exists(path)) \
			.override_failure_message("abandoned runtime rigid-rig file must remain removed: %s" % path) \
			.is_false()


func test_animation_spec_remains_a_general_validation_contract() -> void:
	var spec: Variant = load(ANIMATION_SPEC_PATH)
	assert_object(spec).is_not_null()
	var humanoid: PackedStringArray = spec.humanoid_required_animations()
	var creature: PackedStringArray = spec.creature_required_animations()
	assert_bool(humanoid.has("idle")).is_true()
	assert_bool(humanoid.has("slash_one_hand")).is_true()
	assert_bool(humanoid.has("hold_weapon")).is_true()
	assert_bool(creature.has("idle")).is_true()
	assert_bool(creature.has("claw_swipe")).is_true()
	assert_bool(creature.has("hold_weapon")).is_false()
	assert_bool(spec.is_weapon_bone("Hand.R")).is_true()
	assert_bool(spec.is_weapon_attack_animation("slash_heavy")).is_true()


func test_animation_spec_has_no_legacy_batch_generator_dependency() -> void:
	var source := _source(ANIMATION_SPEC_PATH)
	assert_bool(source.contains("generate_voxel_creature_rigs.py")) \
		.override_failure_message("animation spec must not reference the removed batch generator") \
		.is_false()
