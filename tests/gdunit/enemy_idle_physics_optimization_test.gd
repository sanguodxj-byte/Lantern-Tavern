extends GdUnitTestSuite

const MOVING_STATE_PATH := "res://scenes/characters/enemies/state/enemy_state_moving.gd"


func test_far_settled_enemy_skips_move_and_slide() -> void:
	var source := FileAccess.get_file_as_string(MOVING_STATE_PATH)
	assert_bool(source.contains("func _requires_idle_physics_step")).is_true()
	assert_bool(source.contains("if _requires_idle_physics_step():")).is_true() \
		.override_failure_message("远距静止且已落地的敌人不应每物理帧调用 move_and_slide")
	assert_bool(source.contains("enemy.pushback_force.length_squared()")) \
		.override_failure_message("受击或投掷中的远敌仍必须保留物理步进").is_true()
