extends GdUnitTestSuite

const AVATAR_SCENE := preload("res://scenes/multiplayer/multiplayer_avatar.tscn")
const ENTITY_SCENE := preload("res://scenes/multiplayer/multiplayer_entity.tscn")

func test_remote_avatar_interpolation_clamps_to_target() -> void:
	var avatar := AVATAR_SCENE.instantiate() as Node3D
	add_child(avatar)
	avatar.interp_speed = 20.0
	avatar.global_position = Vector3.ZERO
	avatar.apply_snapshot(Vector3(3.0, 0.0, 0.0), 0.0)
	avatar._physics_process(1.0)
	assert_float(avatar.global_position.x).is_equal_approx(3.0, 0.001)
	avatar.queue_free()

func test_remote_entity_interpolation_clamps_to_target() -> void:
	var entity := ENTITY_SCENE.instantiate() as Node3D
	add_child(entity)
	entity.interp_speed = 20.0
	entity.global_position = Vector3.ZERO
	entity.apply_snapshot({"position": Vector3(4.0, 0.0, 0.0)})
	entity._physics_process(1.0)
	assert_float(entity.global_position.x).is_equal_approx(4.0, 0.001)
	entity.queue_free()
