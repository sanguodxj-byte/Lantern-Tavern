extends GdUnitTestSuite

func test_player_starts_with_formula_baseline_health() -> void:
	var packed := load("res://scenes/characters/player/player.tscn") as PackedScene
	var player := packed.instantiate() as Player
	add_child(player)
	await await_idle_frame()

	assert_object(player.health).is_not_null()
	assert_int(player.health.max_life).is_equal(155) \
		.override_failure_message("等级 1、体质 5 的玩家应使用 MaxHP=100+5*10+1*5=155")
	assert_int(player.health.current_life).is_equal(player.health.max_life)

	player.queue_free()
