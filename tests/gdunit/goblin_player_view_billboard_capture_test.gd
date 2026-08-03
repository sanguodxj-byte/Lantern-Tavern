extends GdUnitTestSuite

const CAPTURE_SCRIPT := "res://tools/goblin_player_view_billboard_capture.gd"

func test_player_view_capture_uses_real_player_and_goblin_scenes() -> void:
	var source := FileAccess.get_file_as_string(CAPTURE_SCRIPT)
	assert_bool(source.contains('const PLAYER_PATH := "res://scenes/characters/player/player.tscn"')).is_true()
	assert_bool(source.contains('const GOBLIN_PATH := "res://scenes/characters/enemies/goblin.tscn"')).is_true()
	assert_bool(source.contains('get_node_or_null("MainCamera") as Camera3D')).is_true()
	assert_bool(source.contains('get_node_or_null("character") as Node3D')).is_true()
	assert_bool(source.contains('get_node_or_null("MainCamera/ViewModel") as Node3D')).is_true()
	assert_bool(source.contains('goblin.set_meta("player_ref", player)')).is_true()
	assert_bool(source.contains('goblin.set_meta("enemy_base_type", "goblin")')).is_true()
	assert_bool(source.contains('goblin.position = Vector3(0.0, 0.0, -19.0)')).is_true() \
		.override_failure_message("玩家视角截图必须把哥布林放在远距 LOD 阈值之外")

func test_player_view_capture_asserts_billboard_visibility_and_source_mesh_hidden() -> void:
	var source := FileAccess.get_file_as_string(CAPTURE_SCRIPT)
	assert_bool(source.contains("imposter.texture == null or not imposter.visible")).is_true()
	assert_bool(source.contains("Goblin source mesh remains visible while billboard is active.")).is_true()
	assert_bool(source.contains("SAVED_PLAYER_VIEW_BILLBOARD")).is_true()
