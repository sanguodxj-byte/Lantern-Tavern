extends GdUnitTestSuite

## ServerCharacterMotor 单元测试（架构审查 P0-1）：
## 物理模式（真实 CharacterBody3D + StaticBody 墙）必须阻止穿墙；
## 无碰撞世界回退纯积分；MovementAuthority.resolve_input_frame 在绑定 body 时走物理碰撞。

const Motor := preload("res://globals/multiplayer/server_character_motor.gd")
const MovementAuthority := preload("res://globals/multiplayer/movement_authority.gd")
const CV := preload("res://globals/multiplayer/command_validator.gd")
const NP := preload("res://globals/multiplayer/network_protocol.gd")

const SERVER_REV := 100

## 构造带一面墙的世界：墙位于 x=1.5 处（厚度 0.5），玩家出生在原点。
func _world_with_wall() -> Dictionary:
	var world := Node3D.new()
	world.name = "MotorWorld"
	add_child(world)
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.collision_layer = 1
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = BoxShape3D.new()
	floor_shape.shape.size = Vector3(20, 0.5, 20)
	floor_shape.position = Vector3(0, -0.25, 0)
	floor_body.add_child(floor_shape)
	world.add_child(floor_body)
	var wall := StaticBody3D.new()
	wall.name = "Wall"
	wall.collision_layer = 1
	var wall_shape := CollisionShape3D.new()
	wall_shape.shape = BoxShape3D.new()
	wall_shape.shape.size = Vector3(0.5, 2.0, 20.0)
	wall_shape.position = Vector3(1.5, 1.0, 0.0)
	wall.add_child(wall_shape)
	world.add_child(wall)
	return {"world": world, "wall_x": 1.5}

func _make_body(world: Node, position: Vector3) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 101
	var shape := CollisionShape3D.new()
	shape.shape = CapsuleShape3D.new()
	shape.shape.radius = 0.4
	shape.shape.height = 1.6
	shape.position = Vector3(0, 0.9, 0)
	body.add_child(shape)
	world.add_child(body)
	body.global_position = position
	return body

func test_integrate_position_fallback_moves_free() -> void:
	var motor: Motor = auto_free(Motor.new())
	var pos: Vector3 = motor.integrate_position(Vector3.ZERO, Vector2(1.0, 0.0), 0.1, 4.0)
	assert_float(pos.x).is_equal_approx(0.4, 1e-4)

func test_move_body_free_motion_without_wall() -> void:
	var motor: Motor = auto_free(Motor.new())
	var world := Node3D.new()
	add_child(world)
	var body := _make_body(world, Vector3.ZERO)
	await get_tree().physics_frame
	var motion: Dictionary = motor.move_body(body, Vector2(1.0, 0.0), false, 1.0 / 30.0, 4.0)
	assert_float(float(motion["position"].x)).is_greater(0.0)
	assert_bool(bool(motion["collided"])).is_false()
	world.queue_free()

func test_move_body_wall_blocks_repeated_input() -> void:
	# 核心 P0-1 回归：持续向墙输入，位置不得越过墙体（墙体 x=1.5，胶囊半径 0.4 → 上限 ~1.1）。
	var motor: Motor = auto_free(Motor.new())
	var setup := _world_with_wall()
	var body := _make_body(setup["world"] as Node, Vector3.ZERO)
	await get_tree().physics_frame
	for _i in range(120):
		motor.move_body(body, Vector2(1.0, 0.0), false, 1.0 / 30.0, 4.0)
	var final_x: float = float(body.global_position.x)
	assert_float(final_x).is_less(1.4) \
		.override_failure_message("持续向墙输入 4 秒，物理马达不得穿墙（最终 x=%.2f）" % final_x)
	(setup["world"] as Node).queue_free()

func test_move_body_wall_detects_collision_flag() -> void:
	var motor: Motor = auto_free(Motor.new())
	var setup := _world_with_wall()
	var body := _make_body(setup["world"] as Node, Vector3.ZERO)
	await get_tree().physics_frame
	var collided := false
	for _i in range(30):
		var motion: Dictionary = motor.move_body(body, Vector2(1.0, 0.0), false, 1.0 / 30.0, 4.0)
		if bool(motion["collided"]):
			collided = true
	assert_bool(collided).is_true()
	(setup["world"] as Node).queue_free()

func test_resolve_input_frame_uses_collision_when_body_bound() -> void:
	# MovementAuthority + motor + body：权威位置受碰撞约束（≠ 纯积分穿墙结果）。
	var ma: MovementAuthority = auto_free(MovementAuthority.new())
	var motor: Motor = auto_free(Motor.new())
	var setup := _world_with_wall()
	var body := _make_body(setup["world"] as Node, Vector3.ZERO)
	await get_tree().physics_frame
	var tr := CV.SequenceTracker.new()
	var live := {"peer_id": 1, "is_alive": true, "position": Vector3.ZERO}
	var frame := {
		"protocol_version": NP.PROTOCOL_VERSION, "world_revision": SERVER_REV,
		"client_tick": 1001, "sequence": 1, "move": [1.0, 0.0], "look_yaw": 0.0,
		"look_pitch": 0.0, "jump": false, "sprint": false,
	}
	for i in range(120):
		frame["sequence"] = i + 1
		live["position"] = ma.resolve_input_frame(frame, live, SERVER_REV, tr, 1.0 / 30.0, motor, body)["event"]["position"]
	var bounded: float = float(live["position"].x)
	assert_float(bounded).is_less(1.4) \
		.override_failure_message("resolve_input_frame 绑定 body 后必须受碰撞约束（x=%.2f）" % bounded)
	(setup["world"] as Node).queue_free()

func test_resolve_input_frame_falls_back_to_integration_without_body() -> void:
	# 未绑定 body（headless 纯逻辑）：保持纯积分语义（既有行为不回退）。
	var ma: MovementAuthority = auto_free(MovementAuthority.new())
	var motor: Motor = auto_free(Motor.new())
	var tr := CV.SequenceTracker.new()
	var live := {"peer_id": 1, "is_alive": true, "position": Vector3.ZERO}
	var frame := {
		"protocol_version": NP.PROTOCOL_VERSION, "world_revision": SERVER_REV,
		"client_tick": 1001, "sequence": 1, "move": [1.0, 0.0], "look_yaw": 0.0,
		"look_pitch": 0.0, "jump": false, "sprint": false,
	}
	var out: Dictionary = ma.resolve_input_frame(frame, live, SERVER_REV, tr, 1.0 / 30.0, motor, null)
	assert_bool(out["success"]).is_true()
	assert_float(float(out["event"]["position"].x)).is_equal_approx(MovementAuthority.BASE_SPEED / 30.0, 1e-4)
