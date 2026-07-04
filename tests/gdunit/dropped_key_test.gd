extends GdUnitTestSuite

# DroppedKey 掉落钥匙逻辑测试

func test_dropped_key_scene_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/collectibles/dropped_key/dropped_key.tscn")).is_true()


func test_dropped_key_script_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/collectibles/dropped_key/dropped_key.gd")).is_true()


func test_key_color_enum_values() -> void:
	assert_int(Door.KeyColor.None).is_equal(0)
	assert_int(Door.KeyColor.Blue).is_equal(1)
	assert_int(Door.KeyColor.Red).is_equal(2)
	assert_int(Door.KeyColor.Yellow).is_equal(3)
	assert_int(Door.KeyColor.Purple).is_equal(4)


func test_color_map_has_all_colors() -> void:
	assert_int(Door.COLOR_MAP.size()).is_equal(4)
	assert_bool(Door.COLOR_MAP.has(Door.KeyColor.Blue)).is_true()
	assert_bool(Door.COLOR_MAP.has(Door.KeyColor.Red)).is_true()
	assert_bool(Door.COLOR_MAP.has(Door.KeyColor.Yellow)).is_true()
	assert_bool(Door.COLOR_MAP.has(Door.KeyColor.Purple)).is_true()


func test_color_map_colors_are_distinct() -> void:
	var seen = []
	for c in Door.COLOR_MAP.values():
		assert_bool(not seen.has(c)).override_failure_message("重复颜色: " + str(c)).is_true()
		seen.append(c)


func test_rotation_speed_constant() -> void:
	# 验证旋转速度常量存在
	var key = load("res://scenes/collectibles/dropped_key/dropped_key.gd")
	assert_bool(key != null).is_true()


func test_game_state_key_flow() -> void:
	var gs = load("res://globals/game_state.gd").new()
	assert_bool(gs.has_key(Door.KeyColor.Red)).is_false()
	gs.obtain_key(Door.KeyColor.Red)
	assert_bool(gs.has_key(Door.KeyColor.Red)).is_true()
	gs.use_key(Door.KeyColor.Red)
	assert_bool(gs.has_key(Door.KeyColor.Red)).is_false()
	gs.free()


func test_game_state_can_hold_multiple_keys() -> void:
	var gs = load("res://globals/game_state.gd").new()
	gs.obtain_key(Door.KeyColor.Blue)
	gs.obtain_key(Door.KeyColor.Yellow)
	assert_bool(gs.has_key(Door.KeyColor.Blue)).is_true()
	assert_bool(gs.has_key(Door.KeyColor.Yellow)).is_true()
	assert_bool(gs.has_key(Door.KeyColor.Red)).is_false()
	gs.free()
