extends GdUnitTestSuite

# Tests for Door enum and static data (pure logic, no scene needed)

func test_key_color_none_is_zero() -> void:
	assert_int(Door.KeyColor.None).is_equal(0)


func test_color_map_contains_all_non_none_keys() -> void:
	assert_bool(Door.COLOR_MAP.has(Door.KeyColor.Blue)).is_true()
	assert_bool(Door.COLOR_MAP.has(Door.KeyColor.Red)).is_true()
	assert_bool(Door.COLOR_MAP.has(Door.KeyColor.Yellow)).is_true()
	assert_bool(Door.COLOR_MAP.has(Door.KeyColor.Purple)).is_true()
	assert_int(Door.COLOR_MAP.size()).is_equal(4)


func test_color_map_not_contains_none() -> void:
	assert_bool(Door.COLOR_MAP.has(Door.KeyColor.None)).is_false()


func test_color_map_values_are_colors() -> void:
	for color in Door.COLOR_MAP.values():
		assert_bool(color is Color).is_true()
