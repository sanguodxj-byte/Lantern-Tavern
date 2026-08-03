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

func test_unregister_player_only_clears_matching_player() -> void:
	var gs = load("res://globals/core/game_state.gd").new()
	var player_a := Player.new()
	var player_b := Player.new()
	gs.current_player = player_a
	gs.unregister_player(player_b)
	assert_object(gs.current_player).is_equal(player_a)
	gs.unregister_player(player_a)
	assert_object(gs.current_player).is_null()
	player_a.free()
	player_b.free()
	gs.free()

func test_dungeon_floor_starts_at_l1_and_advances_with_label() -> void:
	var gs = load("res://globals/core/game_state.gd").new()
	assert_int(gs.get_dungeon_floor()).is_equal(1)
	assert_str(gs.get_dungeon_floor_label()).is_equal("L1")
	assert_int(gs.advance_dungeon_floor()).is_equal(2)
	assert_str(gs.get_dungeon_floor_label()).is_equal("L2")
	gs.free()

func test_dungeon_floor_reset_and_serialization_are_safe() -> void:
	var gs = load("res://globals/core/game_state.gd").new()
	gs.set_dungeon_floor(4)
	assert_int(gs.serialize()["dungeon_floor"]).is_equal(4)
	gs.reset_dungeon_floor()
	assert_str(gs.get_dungeon_floor_label()).is_equal("L1")
	gs.deserialize({"dungeon_floor": 3})
	assert_str(gs.get_dungeon_floor_label()).is_equal("L3")
	gs.deserialize({"dungeon_floor": 0})
	assert_int(gs.get_dungeon_floor()).is_equal(1)
	gs.free()
