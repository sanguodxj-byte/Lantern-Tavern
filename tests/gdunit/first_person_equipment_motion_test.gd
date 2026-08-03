extends GdUnitTestSuite

const MOTION := preload("res://scenes/characters/player/first_person_equipment_motion.gd")


func test_motion_profiles_give_heavy_equipment_more_mass_than_light_equipment() -> void:
	var motion := MOTION.new()
	motion.set_profile(&"dagger")
	var dagger_mass := motion.get_profile_mass()
	motion.set_profile(&"warhammer")
	assert_float(motion.get_profile_mass()).is_greater(dagger_mass)


func test_running_produces_bounded_weapon_only_motion() -> void:
	var motion := MOTION.new()
	motion.set_profile(&"sword")
	motion.set_motion_state(Vector3(2.5, 0.0, -5.5), true, true)
	_step_many(motion, 45, 1.0 / 60.0)
	var transform := motion.get_transform()
	assert_bool(transform.is_finite()).is_true()
	assert_bool(transform.is_equal_approx(Transform3D.IDENTITY)).is_false()
	assert_float(transform.origin.length()).is_less(0.21)


func test_aiming_damps_locomotion_for_reticle_readability() -> void:
	var hip_motion := MOTION.new()
	var aimed_motion := MOTION.new()
	for motion in [hip_motion, aimed_motion]:
		motion.set_motion_state(Vector3(2.0, 0.0, -4.5), true, false)
	for _frame in 60:
		hip_motion.step(1.0 / 60.0, 0.0)
		aimed_motion.step(1.0 / 60.0, 1.0)
	assert_float(aimed_motion.get_position_offset().length()).is_less(hip_motion.get_position_offset().length())
	assert_float(aimed_motion.get_rotation_offset().length()).is_less(hip_motion.get_rotation_offset().length())


func test_look_sway_and_recoil_settle_without_permanent_pose_drift() -> void:
	var motion := MOTION.new()
	motion.set_profile(&"crossbow")
	motion.add_look_input(Vector2(48.0, -26.0))
	motion.add_recoil(1.0, 0.25)
	motion.step(1.0 / 60.0)
	var displaced := motion.get_transform()
	assert_bool(displaced.is_equal_approx(Transform3D.IDENTITY)).is_false()
	motion.set_motion_state(Vector3.ZERO, true, false)
	_step_many(motion, 240, 1.0 / 60.0, 1.0)
	assert_float(motion.get_position_offset().length()).is_less(0.004)
	assert_float(motion.get_rotation_offset().length()).is_less(0.01)


func test_landing_adds_a_short_equipment_dip() -> void:
	var motion := MOTION.new()
	motion.set_motion_state(Vector3(0.0, -7.0, 0.0), false, false)
	motion.step(1.0 / 60.0)
	motion.set_motion_state(Vector3.ZERO, true, false)
	motion.step(1.0 / 60.0)
	assert_float(motion.get_position_offset().y).is_less(0.0)
	_step_many(motion, 180, 1.0 / 60.0)
	assert_float(absf(motion.get_position_offset().y)).is_less(0.004)


func test_shield_impact_has_isolated_spring_recovery() -> void:
	var motion := MOTION.new()
	motion.add_shield_impact(1.0, 0.4)
	motion.step(1.0 / 60.0)
	assert_bool(motion.get_shield_impact_transform().is_equal_approx(Transform3D.IDENTITY)).is_false()
	assert_float(motion.get_transform().origin.length()).is_less(0.01)
	_step_many(motion, 180, 1.0 / 60.0)
	assert_float(motion.get_shield_impact_transform().origin.length()).is_less(0.002)


func test_shield_impact_can_be_cleared_without_residual_reapplication() -> void:
	var motion := MOTION.new()
	motion.add_shield_impact(1.0, -0.35)
	motion.step(1.0 / 60.0)
	assert_bool(motion.get_shield_impact_transform().is_equal_approx(Transform3D.IDENTITY)).is_false()
	motion.clear_shield_impact()
	motion.step(1.0 / 60.0)
	assert_bool(motion.get_shield_impact_transform().is_equal_approx(Transform3D.IDENTITY)).is_true()


func test_motion_is_stable_across_common_frame_rates() -> void:
	var at_sixty := MOTION.new()
	var at_one_twenty := MOTION.new()
	for motion in [at_sixty, at_one_twenty]:
		motion.set_profile(&"greatsword")
		motion.set_motion_state(Vector3(-1.5, 0.0, -4.0), true, false)
	_step_many(at_sixty, 60, 1.0 / 60.0)
	_step_many(at_one_twenty, 120, 1.0 / 120.0)
	assert_vector(at_sixty.get_position_offset()).is_equal_approx(at_one_twenty.get_position_offset(), Vector3.ONE * 0.008)
	assert_vector(at_sixty.get_rotation_offset()).is_equal_approx(at_one_twenty.get_rotation_offset(), Vector3.ONE * 0.012)


func _step_many(
	motion: RefCounted,
	frame_count: int,
	delta: float,
	aim_weight: float = 0.0
) -> void:
	for _frame in frame_count:
		motion.step(delta, aim_weight)
