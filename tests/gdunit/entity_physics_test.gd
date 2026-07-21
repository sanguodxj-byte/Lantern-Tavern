extends GdUnitTestSuite

const PHYSICS_SETUP := preload("res://globals/core/physics_setup.gd")

func test_player_and_enemy_scripts_register_physics_setup() -> void:
	var player_script: GDScript = load("res://scenes/characters/player/player.gd")
	var enemy_script: GDScript = load("res://scenes/characters/enemies/enemy.gd")
	assert_bool(player_script.source_code.find("PhysicsSetup.setup_player(self)") != -1).is_true()
	assert_bool(enemy_script.source_code.find("PhysicsSetup.setup_enemy(self)") != -1).is_true()

func test_player_scene_uses_humanoid_collision_standard() -> void:
	var player: CharacterBody3D = load("res://scenes/characters/player/player.tscn").instantiate()
	add_child(player)
	var shape_node := player.get_node("CollisionShape3D") as CollisionShape3D
	var shape := shape_node.shape as CapsuleShape3D
	assert_float(shape.height).is_equal_approx(PHYSICS_SETUP.HUMANOID_COLLISION_HEIGHT, 0.001)
	assert_float(shape.radius).is_equal_approx(PHYSICS_SETUP.HUMANOID_COLLISION_RADIUS, 0.001)
	assert_float(shape.margin).is_equal_approx(PHYSICS_SETUP.CHARACTER_COLLISION_MARGIN, 0.001)
	assert_float(shape_node.position.y).is_equal_approx(PHYSICS_SETUP.HUMANOID_COLLISION_HEIGHT * 0.5, 0.001)
	player.queue_free()

func test_enemy_scene_body_sizes_are_multiplier_based() -> void:
	var physics_setup := auto_free(PHYSICS_SETUP.new())
	var cases := {
		"res://scenes/characters/enemies/goblin.tscn": "medium",
		"res://scenes/characters/enemies/rock_golem.tscn": "large",
		"res://scenes/characters/enemies/dragon.tscn": "huge",
	}
	for scene_path in cases.keys():
		var enemy: CharacterBody3D = load(scene_path).instantiate()
		add_child(enemy)
		var expected_size: String = cases[scene_path]
		var shape_node := enemy.get_node("CollisionShape") as CollisionShape3D
		var shape := shape_node.shape as CapsuleShape3D
		assert_float(shape.height) \
			.override_failure_message("%s 高度应来自 %s 倍率" % [scene_path, expected_size]) \
			.is_equal_approx(physics_setup.get_character_capsule_height(expected_size), 0.001)
		assert_float(shape.radius) \
			.override_failure_message("%s 半径应来自 %s 倍率" % [scene_path, expected_size]) \
			.is_equal_approx(physics_setup.get_character_capsule_radius(expected_size), 0.001)
		assert_float(shape_node.position.y).is_equal_approx(shape.height * 0.5, 0.001)
		enemy.queue_free()

func test_pickable_item_scene_gets_physics_shape() -> void:
	var item: PickableItem = load("res://scenes/equipment/pickable_item.tscn").instantiate()
	add_child(item)
	assert_bool(item is RigidBody3D).is_true()
	assert_int(item.collision_layer).is_equal(PHYSICS_SETUP.LAYER_PICKABLE)
	assert_int(item.collision_mask).is_equal(PHYSICS_SETUP.MASK_PICKABLE)
	assert_object(item.get_node("CollisionShape").shape).is_instanceof(BoxShape3D)
	item.queue_free()

func test_thrown_item_scene_gets_throwable_physics() -> void:
	var item: ThrownItem = load("res://scenes/equipment/thrown_item.tscn").instantiate()
	add_child(item)
	assert_int(item.collision_layer).is_equal(PHYSICS_SETUP.LAYER_THROWABLE)
	assert_int(item.collision_mask).is_equal(PHYSICS_SETUP.MASK_THROWABLE)
	assert_object(item.get_node("CollisionShape").shape).is_instanceof(BoxShape3D)
	item.queue_free()
