extends GdUnitTestSuite

func test_flame_vent_trap_scene_is_interactive_area() -> void:
	var scene := load("res://scenes/traps/flame_vent_trap.tscn") as PackedScene
	assert_object(scene).is_not_null()
	var trap := scene.instantiate()

	assert_bool(trap is Area3D).is_true()
	assert_object(trap.get_script()).is_not_null()
	assert_object((trap as Node).find_child("CollisionShape3D", true, false)).is_not_null()
	assert_object((trap as Node).find_child("VentMesh", true, false)).is_not_null()

	trap.free()
