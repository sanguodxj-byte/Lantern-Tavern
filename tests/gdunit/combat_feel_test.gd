extends GdUnitTestSuite

const ACCEPTED_HUMANOID_RIG := \
	"res://assets/meshes/characters/voxel_goblin_32px_rig.glb"
const PLAYER_VISUAL_ROUTE := \
	"res://scenes/characters/player/player_visual_model.tscn"

func test_hit_stop_low_impact_does_not_pause_tree() -> void:
	var source := _source("res://globals/core/hit_stop_server.gd")
	assert_bool(source.contains("GameEvents.ImpactIntensity.LOW: 25")).is_true()
	assert_bool(source.contains("if intensity == GameEvents.ImpactIntensity.LOW:")).is_true()
	assert_bool(source.contains("return")).is_true()

func test_no_backstep_or_attack_range_prompt_was_added() -> void:
	var player_source := _source("res://scenes/characters/player/player.gd")
	var moving_source := _source("res://scenes/characters/player/state/player_state_moving.gd")
	var blocking_source := _source("res://scenes/characters/player/state/player_state_blocking.gd")
	assert_bool(player_source.contains("try_backstep")).is_false()
	assert_bool(player_source.contains("ATTACK_RANGE_GUIDE")).is_false()
	assert_bool(moving_source.contains("try_backstep")).is_false()
	assert_bool(blocking_source.contains("try_backstep")).is_false()

func test_slash_damage_uses_active_hitbox_overlap_not_instant_raycast() -> void:
	var player_slash := _source("res://scenes/characters/player/state/player_state_slashing.gd")
	var enemy_slash := _source("res://scenes/characters/enemies/state/enemy_state_slashing.gd")
	assert_bool(player_slash.contains("prepare_attack_hitbox")).is_true()
	assert_bool(player_slash.contains("get_overlapping_bodies()")).is_true()
	assert_bool(player_slash.contains("weapon_reach_raycast.is_colliding()")).is_false()
	assert_bool(enemy_slash.contains("prepare_attack_hitbox")).is_true()
	assert_bool(enemy_slash.contains("get_overlapping_bodies()")).is_true()
	assert_bool(enemy_slash.contains("weapon_reach_raycast.is_colliding()")).is_false()

func test_combat_hitbox_builder_attaches_to_weapon_model_mesh() -> void:
	var source := _source("res://globals/combat/combat_hitbox_builder.gd")
	assert_bool(source.contains("class_name CombatHitboxBuilder")).is_true()
	assert_bool(source.contains("_combined_mesh_aabb(weapon_model)")).is_true()
	assert_bool(source.contains("find_children(\"*\", \"MeshInstance3D\"")).is_true()

func test_slash_animation_uses_tuned_progress_windows_and_weapon_arc() -> void:
	var animator_source := _source("res://globals/combat/combat_slash_animator.gd")
	var player_slash := _source("res://scenes/characters/player/state/player_state_slashing.gd")
	var enemy_slash := _source("res://scenes/characters/enemies/state/enemy_state_slashing.gd")
	assert_bool(animator_source.contains("PLAYER_SPEED_SCALE")).is_true()
	assert_bool(animator_source.contains("ENEMY_SPEED_SCALE")).is_true()
	assert_bool(animator_source.contains("player_animation_name")).is_true()
	assert_bool(animator_source.contains("bash_shield")).is_true()
	assert_bool(animator_source.contains("thrust_spear")).is_true()
	assert_bool(animator_source.contains("slash_heavy")).is_true()
	assert_bool(animator_source.contains("static func apply_weapon_arc")).is_true()
	assert_bool(animator_source.contains("TRAIL_SIZE")).is_true()
	assert_bool(animator_source.contains("TRAIL_MAX_ALPHA")).is_true()
	assert_bool(animator_source.contains("sin(strike * PI)")).is_true()
	assert_bool(animator_source.contains("StandardMaterial3D.TRANSPARENCY_ALPHA")).is_true()
	assert_bool(animator_source.contains("set_trail_visible(placeholder, false)")).is_true()
	assert_bool(player_slash.contains("SLASH_ANIM.player_animation_name")).is_true()
	assert_bool(player_slash.contains("SLASH_ANIM.play(player.animation_player")).is_true()
	assert_bool(player_slash.contains("SLASH_ANIM.is_player_hit_active")).is_true()
	assert_bool(player_slash.contains("SLASH_ANIM.apply_weapon_arc")).is_true()
	assert_bool(enemy_slash.contains("SLASH_ANIM.enemy_animation_name")).is_true()
	assert_bool(enemy_slash.contains("SLASH_ANIM.play(enemy.animation_player")).is_true()
	assert_bool(enemy_slash.contains("SLASH_ANIM.is_enemy_hit_active")).is_true()

func test_accepted_s_humanoid_fixture_contains_weapon_differentiated_actions() -> void:
	assert_bool(FileAccess.file_exists(ACCEPTED_HUMANOID_RIG)).is_true()
	var packed := load(ACCEPTED_HUMANOID_RIG) as PackedScene
	assert_object(packed).is_not_null()
	var instance := packed.instantiate()
	var animation_player := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert_object(animation_player).is_not_null()
	for action_name in [
		"slash_one_hand",
		"slash_dagger",
		"slash_heavy",
		"thrust_spear",
		"bash_shield",
		"claw_swipe",
	]:
		assert_bool(animation_player.has_animation(action_name)) \
			.override_failure_message("accepted goblin rig missing combat animation: %s" % action_name) \
			.is_true()
	for animation_name in animation_player.get_animation_list():
		var bare_name := String(animation_name).split("/")[-1]
		assert_bool(bare_name.begins_with("Armature") or bare_name.contains("动作")) \
			.override_failure_message("accepted goblin rig leaked locale animation name: %s" % bare_name) \
			.is_false()
	instance.free()

func test_player_visual_route_imports_weapon_differentiated_actions() -> void:
	var scene := load(PLAYER_VISUAL_ROUTE) as PackedScene
	assert_object(scene).is_not_null()
	var visual := scene.instantiate()
	var animation_player := visual.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert_object(animation_player).is_not_null()
	for action_name in ["slash_one_hand", "slash_dagger", "slash_heavy", "thrust_spear", "bash_shield", "claw_swipe"]:
		assert_bool(animation_player.has_animation(action_name)) \
			.override_failure_message("player scene missing imported combat animation: %s" % action_name) \
			.is_true()
	# 轨道验收：武器动画不能只剩 1-2 条空壳轨道
	for action_name in ["slash_one_hand", "slash_heavy", "slash"]:
		var anim := animation_player.get_animation(action_name)
		assert_object(anim).is_not_null()
		assert_int(anim.get_track_count()) \
			.override_failure_message("%s track count too low after import" % action_name) \
			.is_greater_equal(5)
	visual.free()

static func _source(path: String) -> String:
	return FileAccess.get_file_as_string(path)
