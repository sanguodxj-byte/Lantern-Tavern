extends GdUnitTestSuite

const PHYSICS_SETUP := preload("res://globals/core/physics_setup.gd")

func test_player_and_enemy_scripts_register_physics_setup() -> void:
	var player_script: GDScript = load("res://scenes/characters/player/player.gd")
	var enemy_script: GDScript = load("res://scenes/characters/enemies/enemy.gd")
	assert_bool(player_script.source_code.find("PhysicsSetup.setup_player(self)") != -1).is_true()
	assert_bool(enemy_script.source_code.find("PhysicsSetup.setup_enemy(self)") != -1).is_true()

func test_player_scene_uses_humanoid_collision_standard() -> void:
	var scene := load("res://scenes/characters/player/player.tscn") as PackedScene
	var shape := _scene_property(scene, "./CollisionShape3D", "shape") as CapsuleShape3D
	assert_object(shape).is_not_null()
	if shape == null:
		return
	assert_float(shape.height).is_equal_approx(PHYSICS_SETUP.HUMANOID_COLLISION_HEIGHT, 0.001)
	assert_float(shape.radius).is_equal_approx(PHYSICS_SETUP.HUMANOID_COLLISION_RADIUS, 0.001)
	assert_float(shape.margin).is_equal_approx(PHYSICS_SETUP.CHARACTER_COLLISION_MARGIN, 0.001)
	var collision_transform: Transform3D = _scene_property(scene, "./CollisionShape3D", "transform")
	assert_float(collision_transform.origin.y).is_equal_approx(PHYSICS_SETUP.HUMANOID_COLLISION_HEIGHT * 0.5, 0.001)

func test_enemy_scene_body_sizes_are_multiplier_based() -> void:
	var physics_setup: Node = auto_free(PHYSICS_SETUP.new())
	var cases := {
		"res://scenes/characters/enemies/goblin.tscn": "medium",
		"res://scenes/characters/enemies/rock_golem.tscn": "large",
		"res://scenes/characters/enemies/dragon.tscn": "huge",
	}
	for scene_path in cases.keys():
		var scene := load(scene_path) as PackedScene
		var expected_size: String = cases[scene_path]
		var shape := _scene_property(scene, "./CollisionShape", "shape") as CapsuleShape3D
		assert_object(shape).override_failure_message("%s 缺少场景碰撞胶囊" % scene_path).is_not_null()
		if shape == null:
			continue
		assert_float(shape.height) \
			.override_failure_message("%s 高度应来自 %s 倍率" % [scene_path, expected_size]) \
			.is_equal_approx(physics_setup.get_character_capsule_height(expected_size), 0.001)
		assert_float(shape.radius) \
			.override_failure_message("%s 半径应来自 %s 倍率" % [scene_path, expected_size]) \
			.is_equal_approx(physics_setup.get_character_capsule_radius(expected_size), 0.001)
		var collision_transform: Transform3D = _scene_property(scene, "./CollisionShape", "transform")
		assert_float(collision_transform.origin.y).is_equal_approx(shape.height * 0.5, 0.001)

func test_pickable_item_scene_gets_physics_shape() -> void:
	var source := (load("res://scenes/equipment/pickable_item.gd") as GDScript).source_code
	assert_str(source).contains("PhysicsSetup.setup_pickable(self)")
	var physics_setup: Node = PHYSICS_SETUP.new()
	var item := RigidBody3D.new()
	physics_setup.setup_pickable(item)
	assert_int(item.collision_layer).is_equal(PHYSICS_SETUP.LAYER_PICKABLE)
	assert_int(item.collision_mask).is_equal(PHYSICS_SETUP.MASK_PICKABLE)
	assert_object(item.get_child(0).shape).is_instanceof(BoxShape3D)
	item.free()
	physics_setup.free()

func test_thrown_item_scene_gets_throwable_physics() -> void:
	var source := (load("res://scenes/equipment/thrown_item.gd") as GDScript).source_code
	assert_str(source).contains("PhysicsSetup.setup_rigidbody(self)")
	var physics_setup: Node = PHYSICS_SETUP.new()
	var item := RigidBody3D.new()
	physics_setup.setup_rigidbody(item)
	assert_int(item.collision_layer).is_equal(PHYSICS_SETUP.LAYER_THROWABLE)
	assert_int(item.collision_mask).is_equal(PHYSICS_SETUP.MASK_THROWABLE)
	assert_object(item.get_child(0).shape).is_instanceof(BoxShape3D)
	item.free()
	physics_setup.free()

func _scene_property(scene: PackedScene, node_path: String, property_name: String) -> Variant:
	var state := scene.get_state()
	for node_index in state.get_node_count():
		var state_path := String(state.get_node_path(node_index))
		if state_path.trim_prefix("./") != node_path.trim_prefix("./"):
			continue
		for property_index in state.get_node_property_count(node_index):
			if String(state.get_node_property_name(node_index, property_index)) == property_name:
				return state.get_node_property_value(node_index, property_index)
	return null
