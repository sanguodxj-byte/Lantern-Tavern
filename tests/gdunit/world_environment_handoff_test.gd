extends GdUnitTestSuite


func test_world_adopts_loaded_level_environment() -> void:
	var world := World.new()
	var target := WorldEnvironment.new()
	target.name = "WorldEnvironment"
	target.environment = Environment.new()
	world.add_child(target)
	var level := Node3D.new()
	var level_environment := WorldEnvironment.new()
	var expected := Environment.new()
	expected.ambient_light_color = Color(0.20, 0.23, 0.28)
	expected.ambient_light_energy = 0.50
	level_environment.environment = expected
	level.add_child(level_environment)

	world._adopt_level_environment(level)

	assert_object(target.environment).is_same(expected)
	assert_object(level_environment.environment).is_null()
	world.free()
	level.free()


func test_world_restores_default_environment_when_level_has_none() -> void:
	var world := World.new()
	var target := WorldEnvironment.new()
	target.name = "WorldEnvironment"
	target.environment = Environment.new()
	world.add_child(target)
	var expected_default := Environment.new()
	world._default_environment = expected_default
	var level := Node3D.new()

	world._adopt_level_environment(level)

	assert_object(target.environment).is_same(expected_default)
	world.free()
	level.free()
