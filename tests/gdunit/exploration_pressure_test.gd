extends GdUnitTestSuite

const PRESSURE_SCRIPT := preload("res://globals/dungeon/exploration_pressure.gd")


func test_opening_door_raises_threat_and_advances_time() -> void:
	var pressure := PRESSURE_SCRIPT.new()
	pressure.record_door_action(pressure.ACTION_OPEN_DOOR)

	assert_int(pressure.opened_doors).is_equal(1)
	assert_int(pressure.elapsed_minutes).is_equal(pressure.open_door_minutes)
	assert_float(pressure.threat_level).is_equal(1.0)

	pressure.free()


func test_breaking_door_is_more_pressure_than_opening() -> void:
	var opened := PRESSURE_SCRIPT.new()
	var broken := PRESSURE_SCRIPT.new()

	opened.record_door_action(opened.ACTION_OPEN_DOOR)
	broken.record_door_action(broken.ACTION_BREAK_DOOR)

	assert_bool(broken.threat_level > opened.threat_level).is_true()
	assert_float(broken.threat_level).is_equal(3.0)
	assert_int(broken.broken_doors).is_equal(1)
	assert_int(broken.elapsed_minutes).is_equal(broken.break_door_minutes)

	opened.free()
	broken.free()


func test_pressure_recommends_extraction_when_time_is_low() -> void:
	var pressure := PRESSURE_SCRIPT.new()
	pressure.advance_minutes(9 * 60)

	assert_bool(pressure.should_recommend_extraction()).is_true()
	assert_str(pressure.make_snapshot()["pressure_band"]).is_equal("leave_soon")

	pressure.free()


func test_overtime_result_marks_tavern_missed() -> void:
	var pressure := PRESSURE_SCRIPT.new()
	pressure.advance_minutes(10 * 60)
	var result := pressure.build_extraction_result(false)

	assert_bool(result["missed_tavern"]).is_true()
	assert_int(result["arrival_minutes"]).is_equal(18 * 60)
	assert_bool(result["voluntary"]).is_false()

	pressure.free()


func test_expedition_day_starts_at_eight_and_lasts_ten_game_hours() -> void:
	var pressure := PRESSURE_SCRIPT.new()

	assert_int(pressure.get_current_clock_minutes()).is_equal(8 * 60)
	assert_int(pressure.get_deadline_clock_minutes()).is_equal(18 * 60)
	assert_int(pressure.get_remaining_minutes()).is_equal(10 * 60)

	pressure.free()


func test_real_time_ratio_maps_thirty_minutes_to_ten_game_hours() -> void:
	var pressure := PRESSURE_SCRIPT.new()

	assert_float(pressure.minutes_per_real_second).is_equal_approx(1.0 / 3.0, 0.0001)

	pressure.free()


func test_pressure_outputs_sensory_and_environment_multipliers() -> void:
	var pressure := PRESSURE_SCRIPT.new()
	pressure.threat_level = 60.0

	assert_float(pressure.get_vision_range_multiplier()).is_equal(0.5)
	assert_bool(pressure.get_environment_activity_multiplier() > 1.0).is_true()

	pressure.free()


func test_dark_erosion_thresholds_dim_disable_and_force_hunt() -> void:
	var pressure := PRESSURE_SCRIPT.new()

	pressure.threat_level = 59.0
	assert_float(pressure.get_vision_range_multiplier()).is_equal(1.0)
	assert_bool(pressure.should_force_monster_hunt()).is_false()

	pressure.threat_level = 60.0
	assert_float(pressure.get_vision_range_multiplier()).is_equal(0.5)

	pressure.threat_level = 80.0
	assert_float(pressure.get_vision_range_multiplier()).is_equal(0.0)
	assert_bool(pressure.should_force_monster_hunt()).is_false()

	pressure.threat_level = 100.0
	assert_bool(pressure.should_force_monster_hunt()).is_true()
	assert_bool(pressure.make_snapshot()["force_monster_hunt"]).is_true()
	assert_float(pressure.make_snapshot()["dark_erosion"]).is_equal(100.0)

	pressure.free()
