extends GdUnitTestSuite

const PROBE_SCRIPT := "res://tools/dungeon_view_perf_probe.gd"


func test_dungeon_view_perf_probe_exposes_angle_metrics() -> void:
	var source := FileAccess.get_file_as_string(PROBE_SCRIPT)
	assert_str(source).contains("DUNGEON_VIEW_PROBE")
	assert_str(source).contains("frustum_terrain_instances")
	assert_str(source).contains("visible_lights")
	assert_str(source).contains("occluders")
	assert_str(source).contains("monitoring_areas")
	assert_str(source).contains("enemy_spawns")
	assert_str(source).contains("imposter_captures")
	assert_str(source).contains("RENDER_TOTAL_PRIMITIVES_IN_FRAME")
	assert_str(source).contains("--angles=")
	assert_str(source).contains("dungeon_view_perf_probe_metrics.txt")
	assert_str(source).contains("_flush_output")


func test_dungeon_view_perf_probe_isolates_dungeon_rendering_from_player_runtime() -> void:
	var source := FileAccess.get_file_as_string(PROBE_SCRIPT)
	assert_bool(source.contains("DungeonGenerator")).is_true()
	assert_bool(source.contains("DungeonSceneBuilder")).is_true()
	assert_bool(source.contains("DungeonStreamingController")).is_true()
	assert_bool(source.contains("_build_probe_dungeon")).is_true()
	assert_bool(source.contains("_create_probe_observer")).is_true()
	assert_bool(source.contains("procedural_dungeon.tscn")).is_false()


func test_dungeon_view_perf_probe_scene_loads() -> void:
	var scene := load("res://tools/dungeon_view_perf_probe_scene.tscn") as PackedScene
	assert_object(scene).is_not_null()
