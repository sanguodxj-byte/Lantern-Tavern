extends GdUnitTestSuite

# Tests for GameState-like key management logic
# GameState is an autoload singleton, so we test the script directly




func test_register_player_ignores_equipment_preview_player() -> void:
	var gs = load("res://globals/core/game_state.gd").new()
	var real_player := Player.new()
	var preview_player := Player.new()
	preview_player.set_meta("equipment_preview", true)

	gs.register_player(real_player)
	gs.register_player(preview_player)

	assert_object(gs.current_player).is_equal(real_player)
	preview_player.free()
	real_player.free()
	gs.free()
