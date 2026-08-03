extends GdUnitTestSuite

const LIBRARY := preload("res://scenes/characters/player/first_person_animation_library.gd")

func test_first_person_library_covers_every_style_hold_guard_attack_and_heavy_action() -> void:
	var library := LIBRARY.build()
	for action_name in LIBRARY.REQUIRED_ACTIONS:
		assert_bool(library.has_animation(action_name)) \
			.override_failure_message("missing first-person action: %s" % action_name).is_true()
		if not library.has_animation(action_name):
			continue
		assert_float(library.get_animation(action_name).length).is_greater(0.0)
		assert_int(library.get_animation(action_name).get_track_count()).is_greater(0)

func test_first_person_action_library_only_targets_visual_action_layer() -> void:
	var library := LIBRARY.build()
	for action_name in LIBRARY.REQUIRED_ACTIONS:
		var animation := library.get_animation(action_name)
		if animation == null:
			continue
		var expected_root := "ShieldActionPivot" if action_name in LIBRARY.CANONICAL_SHIELD_ACTIONS else "ActionPivot"
		for track_index in animation.get_track_count():
			assert_bool(String(animation.track_get_path(track_index)).begins_with(expected_root)) \
				.override_failure_message("first-person action writes outside its equipment pivot: %s" % action_name).is_true()

func test_each_first_person_style_has_distinct_attack_fingerprint() -> void:
	var library := LIBRARY.build()
	var attack_names: Array[StringName] = [
		&"vm_claw_swipe", &"vm_shortsword_thrust", &"vm_sword_slash", &"vm_stab_dagger",
		&"vm_greatsword_attack", &"vm_axe_attack", &"vm_warhammer_attack", &"vm_thrust_spear",
		&"vm_bow_release", &"vm_crossbow_fire", &"vm_staff_attack", &"vm_grimoire_attack",
		&"vm_bash_shield",
	]
	var fingerprints := {}
	for action_name in attack_names:
		var fingerprint := _fingerprint(library.get_animation(action_name))
		assert_bool(fingerprints.has(fingerprint)) \
			.override_failure_message("first-person attacks are identical: %s" % action_name).is_false()
		fingerprints[fingerprint] = action_name

func test_heavy_swing_actions_are_separate_first_person_clips() -> void:
	var library := LIBRARY.build()
	for profile in [&"greatsword", &"axe", &"warhammer", &"spear"]:
		var attack_name := StringName("vm_%s_attack" % profile)
		if profile == &"spear":
			attack_name = &"vm_thrust_spear"
		var attack := library.get_animation(attack_name)
		var heavy := library.get_animation(StringName("vm_%s_heavy_swing" % profile))
		assert_object(heavy).is_not_null()
		assert_bool(_fingerprint(attack) != _fingerprint(heavy)).is_true()

func test_every_style_hold_clip_has_a_ready_to_charge_transition() -> void:
	var library := LIBRARY.build()
	for profile in LIBRARY.STYLE_PROFILES:
		var hold := library.get_animation(StringName("vm_%s_hold" % profile))
		assert_object(hold).is_not_null()
		if hold == null:
			continue
		var root_path := "ShieldActionPivot" if profile == &"shield" else "ActionPivot"
		var position_track := hold.find_track("%s:position" % root_path, Animation.TYPE_VALUE)
		var rotation_track := hold.find_track("%s:rotation" % root_path, Animation.TYPE_VALUE)
		assert_int(position_track).is_greater_equal(0)
		assert_int(rotation_track).is_greater_equal(0)
		var first_pose := str(hold.track_get_key_value(position_track, 0)) + str(hold.track_get_key_value(rotation_track, 0))
		var charged_pose := str(hold.track_get_key_value(position_track, hold.track_get_key_count(position_track) - 1)) + str(hold.track_get_key_value(rotation_track, hold.track_get_key_count(rotation_track) - 1))
		assert_bool(first_pose != charged_pose) \
			.override_failure_message("first-person hold clip has no charge transition: %s" % profile).is_true()

func test_mount_rotation_matches_specific_two_hand_style_before_generic_sword_token() -> void:
	assert_float(LIBRARY._mount_rotation_z_for_action(&"vm_greatsword_attack")).is_equal_approx(-135.0, 0.001)
	assert_float(LIBRARY._mount_rotation_z_for_action(&"vm_sword_slash")).is_equal_approx(-140.0, 0.001)
	assert_float(LIBRARY._mount_rotation_z_for_action(&"vm_shield_block")).is_equal_approx(0.0, 0.001)


func test_runtime_weapon_library_replaces_legacy_shield_tracks_with_additive_canonical_motion() -> void:
	var library := LIBRARY.load_for_weapon("sword", "standard")
	for action_name in LIBRARY.CANONICAL_SHIELD_ACTIONS:
		var animation := library.get_animation(action_name)
		assert_object(animation).is_not_null()
		if animation == null:
			continue
		for track_index in animation.get_track_count():
			assert_bool(String(animation.track_get_path(track_index)).begins_with("ShieldActionPivot")).is_true()
	var block := library.get_animation(&"vm_shield_block")
	var position_track := block.find_track("ShieldActionPivot:position", Animation.TYPE_VALUE)
	assert_vector(block.track_get_key_value(position_track, 0)).is_equal(Vector3.ZERO)
	assert_float((block.track_get_key_value(position_track, 2) as Vector3).length()).is_greater(0.1)
	assert_int(block.loop_mode).is_equal(Animation.LOOP_NONE)
	assert_vector(block.track_get_key_value(position_track, 3)).is_equal(
		block.track_get_key_value(position_track, 2)
	)
	var bash := library.get_animation(&"vm_bash_shield")
	assert_int(bash.track_get_key_count(0)).is_greater_equal(6)
	var bash_windup: Vector3 = bash.track_get_key_value(0, 2)
	var bash_contact: Vector3 = bash.track_get_key_value(0, 3)
	assert_float(bash_windup.z).is_less(-0.1)
	assert_float(bash_contact.z).is_greater(bash_windup.z)
	assert_float(bash_contact.x).is_greater(0.15)

func _fingerprint(animation: Animation) -> String:
	var values: Array[String] = []
	for track_index in animation.get_track_count():
		values.append(String(animation.track_get_path(track_index)))
		for key_index in animation.track_get_key_count(track_index):
			values.append(str(animation.track_get_key_value(track_index, key_index)))
	return "|".join(values)
