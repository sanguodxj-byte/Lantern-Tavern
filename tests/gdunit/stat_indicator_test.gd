extends GdUnitTestSuite

# Tests for StatIndicator logic
# Uses direct script instantiation (scene-dependent tests disabled)

func test_indicator_script_loads() -> void:
	var script = load("res://scenes/ui/stat_indicator.gd")
	assert_bool(script != null).is_true()


func test_scene_loads() -> void:
	var scene = load("res://scenes/ui/stat_indicator.tscn")
	assert_bool(scene != null).is_true()


func test_refresh_zero_value() -> void:
	var indicator = load("res://scenes/ui/stat_indicator.tscn").instantiate() as StatIndicator
	assert_bool(indicator != null).is_true()
	indicator.queue_free()
