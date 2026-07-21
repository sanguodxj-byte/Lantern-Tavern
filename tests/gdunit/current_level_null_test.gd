extends GdUnitTestSuite

func test_current_level_starts_null() -> void:
	assert_bool(GameState.current_level == null).is_true()

func test_register_level_sets_current_level() -> void:
	var node := Node3D.new()
	GameState.register_level(node)
	assert_bool(GameState.current_level != null).is_true()
	GameState.current_level = null
	node.free()



func test_accepts_node3d() -> void:
	var node := Node3D.new()
	GameState.register_level(node)
	assert_bool(GameState.current_level == node).is_true()
	GameState.current_level = null
	node.free()
