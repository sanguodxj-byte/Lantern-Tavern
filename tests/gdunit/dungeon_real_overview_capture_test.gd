extends GdUnitTestSuite

func test_capture_scene_uses_production_dungeon_without_material_gallery() -> void:
	var source := (load("res://tools/dungeon_real_overview_capture.gd") as GDScript).source_code
	assert_bool(source.contains("procedural_dungeon.tscn")).is_true()
	assert_bool(source.contains("spawn_population_enabled = true")).is_true()
	assert_bool(source.contains("item_tag")).is_true()
	assert_bool(source.contains("room_focus")).is_true()
	assert_bool(source.contains("_disable_game_cameras")).is_true()
	assert_bool(source.contains("_configure_capture_lighting")).is_true()
	assert_bool(source.contains("_hide_game_hud")).is_true()
	assert_bool(source.contains("_activate_capture_room")).is_true()
	assert_bool(source.contains("streaming_controller.set_player")).is_true()
	assert_bool(source.contains("streaming_controller.update_streaming(true)")).is_true()
	assert_bool(source.contains("_force_enemy_visuals")).is_true()
	assert_bool(source.contains("enemy.visible = true")).is_true()
	assert_bool(source.contains("_camera.cull_mask = 0xFFFFF")).is_true()
	assert_bool(source.contains("await _wait_frames(8)\n\t_hide_ceilings()")).is_true()
	assert_bool(source.contains("_count_specs_in_room")).is_true()
	assert_bool(source.contains("spawn_material_visual")).is_false()
	assert_bool(source.contains("dungeon_procedural_materials")).is_false()

func test_capture_scene_file_exists_and_is_loadable() -> void:
	var scene := load("res://tools/dungeon_real_overview_capture.tscn") as PackedScene
	assert_object(scene).is_not_null()
	var root := scene.instantiate()
	assert_object(root).is_not_null()
	assert_str(String(root.name)).is_equal("DungeonRealOverviewCapture")
	root.free()
