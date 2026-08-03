extends GdUnitTestSuite

const STANDARD: AnimationLibrary = preload("res://scenes/characters/player/weapon_animations/sword/standard.tres")
const ALTERNATE: AnimationLibrary = preload("res://scenes/characters/player/weapon_animations/sword/alternate.tres")
const HEAVY: AnimationLibrary = preload("res://scenes/characters/player/weapon_animations/sword/heavy.tres")
const VIEW_MODEL_SCENE: PackedScene = preload("res://scenes/characters/player/view_model.tscn")

const ACTION_PIVOT_POSITION := NodePath("ActionPivot:position")
const ACTION_PIVOT_ROTATION := NodePath("ActionPivot:rotation")
const WEAPON_SOCKET_ROTATION := NodePath("ActionPivot/WeaponSocket:rotation")

func test_longsword_variants_have_authored_six_phase_attack_arcs() -> void:
	for library in [STANDARD, ALTERNATE, HEAVY]:
		var animation: Animation = library.get_animation(&"vm_sword_slash")
		assert_object(animation).is_not_null()
		if animation == null:
			continue
		for path in [ACTION_PIVOT_POSITION, ACTION_PIVOT_ROTATION, WEAPON_SOCKET_ROTATION]:
			var track: int = animation.find_track(path, Animation.TYPE_VALUE)
			assert_int(track).is_greater_equal(0)
			if track >= 0:
				assert_int(animation.track_get_key_count(track)).is_equal(6)
				assert_float(animation.track_get_key_time(track, 3)).is_greater(0.5 * animation.length)
				assert_float(animation.track_get_key_time(track, 3)).is_less(0.75 * animation.length)

func test_longsword_standard_slash_stays_readable_during_the_diagonal_commitment() -> void:
	var animation: Animation = STANDARD.get_animation(&"vm_sword_slash")
	var position_track: int = animation.find_track(ACTION_PIVOT_POSITION, Animation.TYPE_VALUE)
	var rotation_track: int = animation.find_track(ACTION_PIVOT_ROTATION, Animation.TYPE_VALUE)
	var windup_position: Vector3 = animation.track_get_key_value(position_track, 2)
	var strike_position: Vector3 = animation.track_get_key_value(position_track, 3)
	var windup_rotation: Vector3 = animation.track_get_key_value(rotation_track, 2)
	var strike_rotation: Vector3 = animation.track_get_key_value(rotation_track, 3)
	assert_bool(windup_position.y - strike_position.y > 0.2).is_true()
	assert_bool(strike_position.z > -0.2).is_true()
	assert_bool(windup_rotation.x < -0.8).is_true()
	assert_bool(strike_rotation.x > 0.15).is_true()
	assert_int(animation.get_track_count()).is_equal(3)
	for track_index in animation.get_track_count():
		assert_int(animation.track_get_interpolation_type(track_index)).is_equal(Animation.INTERPOLATION_CUBIC)
		assert_str(String(animation.track_get_path(track_index))).not_contains("Skeleton3D")


func test_longsword_standard_slash_moves_from_safe_rear_windup_to_center_in_depth() -> void:
	var animation: Animation = STANDARD.get_animation(&"vm_sword_slash")
	var position_track: int = animation.find_track(ACTION_PIVOT_POSITION, Animation.TYPE_VALUE)
	var rotation_track: int = animation.find_track(ACTION_PIVOT_ROTATION, Animation.TYPE_VALUE)
	var windup_position: Vector3 = animation.track_get_key_value(position_track, 2)
	var strike_position: Vector3 = animation.track_get_key_value(position_track, 3)
	var follow_position: Vector3 = animation.track_get_key_value(position_track, 4)
	var windup_rotation: Vector3 = animation.track_get_key_value(rotation_track, 2)
	var strike_rotation: Vector3 = animation.track_get_key_value(rotation_track, 3)
	var lateral_travel := absf(windup_position.x - strike_position.x)
	var depth_travel := absf(windup_position.z - strike_position.z)
	assert_bool(windup_position.x >= -0.19 and windup_position.x <= -0.15) \
		.override_failure_message("rear windup must stay centered after the blade retreats in depth") \
		.is_true()
	assert_bool(windup_position.z >= -0.22 and windup_position.z <= -0.18) \
		.override_failure_message("rear windup needs enough depth to keep the full blade inside the safe frame") \
		.is_true()
	assert_bool(strike_position.x >= -0.23 and strike_position.x <= -0.17).is_true()
	assert_bool(follow_position.x >= -0.21 and follow_position.x <= -0.15).is_true()
	assert_bool(depth_travel > lateral_travel * 0.9).is_true()
	assert_bool(windup_rotation.y < -0.45) \
		.override_failure_message("right-rear windup must yaw the blade into depth instead of laying it across the screen") \
		.is_true()
	assert_bool(windup_rotation.z >= -0.9 and windup_rotation.z <= -0.7) \
		.override_failure_message("windup roll must preserve a readable diagonal silhouette") \
		.is_true()
	assert_bool(absf(strike_rotation.x - windup_rotation.x) > 0.8).is_true()
	assert_bool(absf(strike_rotation.z - windup_rotation.z) < 1.2).is_true()


func test_longsword_standard_preparation_moves_monotonically_into_the_safe_rear_windup() -> void:
	var animation: Animation = STANDARD.get_animation(&"vm_sword_slash")
	var position_track: int = animation.find_track(ACTION_PIVOT_POSITION, Animation.TYPE_VALUE)
	var hold_position: Vector3 = animation.track_get_key_value(position_track, 0)
	var preparation_position: Vector3 = animation.track_get_key_value(position_track, 1)
	var windup_position: Vector3 = animation.track_get_key_value(position_track, 2)
	assert_bool(hold_position.x > preparation_position.x).is_true()
	assert_bool(preparation_position.x > windup_position.x) \
		.override_failure_message("preparation must move steadily away from the right capture edge") \
		.is_true()
	assert_bool(hold_position.z > preparation_position.z).is_true()
	assert_bool(preparation_position.z > windup_position.z).is_true()


func test_longsword_standard_follow_through_continues_weapon_momentum_in_depth() -> void:
	var animation: Animation = STANDARD.get_animation(&"vm_sword_slash")
	var position_track: int = animation.find_track(ACTION_PIVOT_POSITION, Animation.TYPE_VALUE)
	var strike_position: Vector3 = animation.track_get_key_value(position_track, 3)
	var follow_position: Vector3 = animation.track_get_key_value(position_track, 4)
	var recovery_position: Vector3 = animation.track_get_key_value(position_track, 5)
	assert_bool(follow_position.distance_to(strike_position) > 0.01).is_true()
	assert_float(follow_position.z).is_less(strike_position.z)
	assert_bool(recovery_position.distance_to(follow_position) > 0.08).is_true()

func test_longsword_alternate_and_heavy_clips_use_distinct_follow_throughs() -> void:
	var alternate: Animation = ALTERNATE.get_animation(&"vm_sword_slash")
	var heavy: Animation = HEAVY.get_animation(&"vm_sword_slash")
	var alternate_rotation_track: int = alternate.find_track(ACTION_PIVOT_ROTATION, Animation.TYPE_VALUE)
	var heavy_rotation_track: int = heavy.find_track(ACTION_PIVOT_ROTATION, Animation.TYPE_VALUE)
	var alternate_windup: Vector3 = alternate.track_get_key_value(alternate_rotation_track, 2)
	var alternate_strike: Vector3 = alternate.track_get_key_value(alternate_rotation_track, 3)
	var heavy_windup: Vector3 = heavy.track_get_key_value(heavy_rotation_track, 2)
	var heavy_strike: Vector3 = heavy.track_get_key_value(heavy_rotation_track, 3)
	assert_bool(alternate_windup.z > 1.8).is_true()
	assert_bool(alternate_strike.z < -0.8).is_true()
	assert_bool(heavy.length > STANDARD.get_animation(&"vm_sword_slash").length).is_true()
	assert_bool(heavy_windup.x > 0.9).is_true()
	assert_bool(heavy_strike.x < -1.1).is_true()

func test_iron_longsword_uses_the_authored_first_person_sword_strike() -> void:
	var view_model := auto_free(VIEW_MODEL_SCENE.instantiate()) as ViewModel
	add_child(view_model)
	await get_tree().process_frame
	var weapon := WeaponData.new()
	weapon.id = "sword"
	weapon.item_tag = "weapon"
	weapon.weapon_class = "one_hand_melee"
	weapon.skill_school = "one_hand_sword"
	weapon.view_model_profile = "sword"
	view_model.set_weapon(weapon)
	view_model.sample_action(&"vm_sword_slash", 0.285 / 0.48)
	assert_vector(view_model.action_pivot.position).is_equal_approx(Vector3(-0.2, -0.05, -0.14), Vector3.ONE * 0.001)
	assert_vector(view_model.action_pivot.rotation).is_equal_approx(Vector3(0.25, 0.15, -0.15), Vector3.ONE * 0.001)
	assert_bool(view_model.shield_action_pivot.transform.is_equal_approx(Transform3D.IDENTITY)).is_true()
	assert_object(view_model.find_child("Skeleton3D", true, false)).is_null()

func test_longsword_weapon_socket_rotation_never_interpolates_the_long_way_around() -> void:
	for library in [STANDARD, ALTERNATE, HEAVY]:
		var animation: Animation = library.get_animation(&"vm_sword_slash")
		var socket_track: int = animation.find_track(WEAPON_SOCKET_ROTATION, Animation.TYPE_VALUE)
		for key_index in range(1, animation.track_get_key_count(socket_track)):
			var previous: Vector3 = animation.track_get_key_value(socket_track, key_index - 1)
			var current: Vector3 = animation.track_get_key_value(socket_track, key_index)
			assert_float(absf(current.z - previous.z)) \
				.override_failure_message("weapon socket crosses the Euler wrap between keys %d and %d" % [key_index - 1, key_index]) \
				.is_less(PI)
