extends GdUnitTestSuite

# Tests for props/traps: Door, Chest, SpikesTrap, AcidTrap

# ── Door ─────────────────────────────────────────────────────────────────

func test_door_keycolor_none_is_zero() -> void:
	assert_int(Door.KeyColor.None).is_equal(0)


func test_door_color_map_contains_all_non_none_keys() -> void:
	assert_bool(Door.COLOR_MAP.has(Door.KeyColor.Blue)).is_true()
	assert_bool(Door.COLOR_MAP.has(Door.KeyColor.Red)).is_true()
	assert_bool(Door.COLOR_MAP.has(Door.KeyColor.Yellow)).is_true()
	assert_bool(Door.COLOR_MAP.has(Door.KeyColor.Purple)).is_true()
	assert_int(Door.COLOR_MAP.size()).is_equal(4)


func test_door_color_map_does_not_contain_none() -> void:
	assert_bool(Door.COLOR_MAP.has(Door.KeyColor.None)).is_false()


func test_door_color_map_values_are_colors() -> void:
	for color_val in Door.COLOR_MAP.values():
		assert_bool(typeof(color_val) == TYPE_COLOR).is_true()


func test_door_color_map_blue_is_dark_blue() -> void:
	var blue = Door.COLOR_MAP[Door.KeyColor.Blue]
	# Verify it's a blue-ish color (B channel dominates)
	assert_bool(blue.b > blue.r and blue.b > blue.g).is_true()


func test_door_color_map_red_is_dark_red() -> void:
	var red = Door.COLOR_MAP[Door.KeyColor.Red]
	# Verify it's a red-ish color (R channel dominates)
	assert_bool(red.r > red.g and red.r > red.b).is_true()


# ── Chest ────────────────────────────────────────────────────────────────

func test_chest_starts_closed() -> void:
	var chest := Chest.new()
	assert_bool(chest.is_opened).is_false()


func test_chest_open_sets_opened() -> void:
	var chest := Chest.new()
	chest.open_chest()
	assert_bool(chest.is_opened).is_true()


func test_chest_double_open_does_not_error() -> void:
	var chest := Chest.new()
	chest.open_chest()
	assert_bool(chest.is_opened).is_true()
	# Second open should return early without error
	chest.open_chest()
	assert_bool(chest.is_opened).is_true()


# ── SpikesTrap ───────────────────────────────────────────────────────────

func test_spikes_trap_class_exists() -> void:
	var trap := SpikesTrap.new()
	assert_object(trap).is_not_null()
	assert_object(trap).is_instanceof(SpikesTrap)
	assert_object(trap).is_instanceof(Area3D)


# ── AcidTrap ─────────────────────────────────────────────────────────────

func test_acid_trap_class_exists() -> void:
	var trap := AcidTrap.new()
	assert_object(trap).is_not_null()
	assert_object(trap).is_instanceof(AcidTrap)
	assert_object(trap).is_instanceof(Area3D)
