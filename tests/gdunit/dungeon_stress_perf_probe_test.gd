extends GdUnitTestSuite

const PROBE_SCRIPT := "res://tools/dungeon_stress_perf_probe.gd"
const PROBE_SCENE := "res://tools/dungeon_stress_perf_probe_scene.tscn"


func test_stress_probe_declares_required_scenarios_and_frame_gate() -> void:
	var source := FileAccess.get_file_as_string(PROBE_SCRIPT)
	assert_str(source).contains("dense_monsters")
	assert_str(source).contains("multi_room_population")
	assert_str(source).contains("cross_room_traversal")
	assert_str(source).contains("P95_FRAME_MS")
	assert_str(source).contains("MAX_FRAME_MS")
	assert_str(source).contains("RENDER_TOTAL_OBJECTS_IN_FRAME")
	assert_str(source).contains("TIME_PHYSICS_PROCESS")
	assert_str(source).contains("item_spawner")
	assert_str(source).contains("instantiate_enemy_descriptor")


func test_stress_probe_uses_real_procedural_dungeon_and_player() -> void:
	var source := FileAccess.get_file_as_string(PROBE_SCRIPT)
	assert_str(source).contains("procedural_dungeon.tscn")
	assert_str(source).contains("generation_seed")
	assert_str(source).contains("spawn_population_enabled")
	assert_str(source).contains("GameState.current_player")


func test_stress_probe_disables_vsync_before_sampling() -> void:
	var source := FileAccess.get_file_as_string(PROBE_SCRIPT)
	assert_str(source).contains("DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)")
	assert_str(source).contains("frame_started_usec")


func test_stress_probe_scene_loads() -> void:
	var scene := load(PROBE_SCENE) as PackedScene
	assert_object(scene).is_not_null()
