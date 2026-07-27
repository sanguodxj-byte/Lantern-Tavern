extends GdUnitTestSuite

func test_jump_edge_is_handled_by_player_boundary() -> void:
	var player_source := FileAccess.get_file_as_string("res://scenes/characters/player/player.gd")
	var moving_source := FileAccess.get_file_as_string("res://scenes/characters/player/state/player_state_moving.gd")
	assert_str(player_source).contains("_handle_jump_input()")
	assert_str(player_source).contains('Input.is_action_just_pressed("jump")')
	assert_str(player_source).contains("func _handle_jump_input()")
	assert_str(player_source).contains("do_jump()")
	assert_str(moving_source).not_contains('Input.is_action_just_pressed("jump")')


func test_jump_boundary_does_not_require_moving_state() -> void:
	var player_source := FileAccess.get_file_as_string("res://scenes/characters/player/player.gd")
	var handler_start := player_source.find("func _handle_jump_input()")
	var handler_end := player_source.find("\nfunc ", handler_start + 1)
	if handler_end == -1:
		handler_end = player_source.length()
	var handler := player_source.substr(handler_start, handler_end - handler_start)
	assert_bool(handler.contains("state == State.MOVING")).is_false()
	assert_bool(handler.contains("state == State.DYING")).is_true()


func test_jump_action_is_declared_as_space() -> void:
	var has_space_binding := false
	for event in InputMap.action_get_events("jump"):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_SPACE:
			has_space_binding = true
	assert_bool(has_space_binding).is_true()
