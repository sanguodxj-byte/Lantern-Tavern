extends GdUnitTestSuite

# Tests for GameState-like key management logic
# GameState is an autoload singleton, so we test the script directly

func test_has_key_returns_false_initially() -> void:
	var gs = load("res://globals/game_state.gd").new()
	assert_bool(gs.has_key(Door.KeyColor.Red)).is_false()
	assert_bool(gs.has_key(Door.KeyColor.Blue)).is_false()
	assert_bool(gs.has_key(Door.KeyColor.Yellow)).is_false()
	assert_bool(gs.has_key(Door.KeyColor.Purple)).is_false()
	gs.free()


func test_obtain_key_sets_true() -> void:
	var gs = load("res://globals/game_state.gd").new()
	gs.obtain_key(Door.KeyColor.Blue)
	assert_bool(gs.has_key(Door.KeyColor.Blue)).is_true()
	assert_bool(gs.has_key(Door.KeyColor.Red)).is_false()
	gs.free()


func test_use_key_sets_false() -> void:
	var gs = load("res://globals/game_state.gd").new()
	gs.obtain_key(Door.KeyColor.Yellow)
	assert_bool(gs.has_key(Door.KeyColor.Yellow)).is_true()

	gs.use_key(Door.KeyColor.Yellow)
	assert_bool(gs.has_key(Door.KeyColor.Yellow)).is_false()
	gs.free()


func test_use_unobtained_key_does_not_error() -> void:
	var gs = load("res://globals/game_state.gd").new()
	gs.use_key(Door.KeyColor.Purple)
	assert_bool(gs.has_key(Door.KeyColor.Purple)).is_false()
	gs.free()


func test_register_level_clears_keys() -> void:
	var gs = load("res://globals/game_state.gd").new()
	gs.obtain_key(Door.KeyColor.Red)
	gs.obtain_key(Door.KeyColor.Blue)
	assert_bool(gs.has_key(Door.KeyColor.Red)).is_true()

	gs.register_level(null)
	assert_bool(gs.has_key(Door.KeyColor.Red)).is_false()
	assert_bool(gs.has_key(Door.KeyColor.Blue)).is_false()
	gs.free()
