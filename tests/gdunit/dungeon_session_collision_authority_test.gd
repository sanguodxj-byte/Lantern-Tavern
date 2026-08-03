extends GdUnitTestSuite

## 专服 authority collision-only 真实 seed 端到端门禁（架构审查 P1-4）：
##   * 真实 seed 地牢的 build_authority_collision_only 产出真实静态墙体碰撞；
##   * 服务器马达在真实地牢中持续向墙输入不穿墙（30Hz 5 秒）；
##   * 同一可通行单元内自由移动不受阻挡（碰撞约束正确性反例）。

const Controller := preload("res://scenes/multiplayer/dungeon_session_controller.gd")
const Motor := preload("res://globals/multiplayer/server_character_motor.gd")
const LayoutClass := preload("res://scenes/expedition/dungeon_layout.gd")

const SEED_A := 20260803
const WALL_CELL := 2

func _build(seed_value: int) -> Node:
	var c: Node = Controller.new()
	c.name = "CollisionAuthority_%d" % seed_value
	add_child(c)
	c.build_authority_collision_only(seed_value)
	return c

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

## 找一对「可通行格 + 相邻墙格」，返回 {walk_cell, wall_cell, walk_pos, wall_pos}。
func _find_wall_adjacent_cell(layout: LayoutClass) -> Dictionary:
	var grid: Array = layout.grid
	var neighbors: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for y in range(layout.height):
		for x in range(layout.width):
			if int(grid[y][x]) != WALL_CELL:
				continue
			for d in neighbors:
				var nb: Vector2i = Vector2i(x, y) + d
				if nb.x < 0 or nb.y < 0 or nb.x >= layout.width or nb.y >= layout.height:
					continue
				if layout.is_floor_at(nb.x, nb.y):
					return {
						"walk_cell": nb,
						"wall_cell": Vector2i(x, y),
						"walk_pos": layout.cell_to_world(nb),
						"wall_pos": layout.cell_to_world(Vector2i(x, y)),
					}
	return {}

func test_collision_only_builds_static_walls_for_real_seed() -> void:
	# 真实 seed：authority collision-only 必须产出静态墙体碰撞（≥1 个 StaticBody3D）。
	var c := _build(SEED_A)
	var collision_root: Node = c.get_node_or_null("AuthorityCollision_%d/CollisionRoot" % SEED_A)
	assert_object(collision_root).is_not_null()
	var static_count := 0
	for node in collision_root.find_children("*", "StaticBody3D", true, false):
		static_count += 1
	assert_int(static_count) \
		.override_failure_message("collision-only 地牢必须产出静态墙体碰撞体").is_greater(0)
	c.queue_free()

func test_motor_blocked_by_real_dungeon_wall() -> void:
	# 真实 seed 地牢 + 真实碰撞：向相邻墙持续输入 5 秒，马达不得穿墙。
	var c := _build(SEED_A)
	var layout: LayoutClass = c._layout
	var pair := _find_wall_adjacent_cell(layout)
	assert_bool(not pair.is_empty()).override_failure_message("种子 %d 应存在墙-可通行邻接对" % SEED_A).is_true()
	var body := _make_body(c, pair["walk_pos"])
	await get_tree().physics_frame
	var dir := (pair["wall_pos"] as Vector3 - pair["walk_pos"] as Vector3)
	dir.y = 0.0
	dir = dir.normalized()
	var motor: Motor = auto_free(Motor.new())
	var wall_half := layout.tile_size * 0.5
	var body_radius := 0.4
	var min_allowed_dist: float = wall_half - body_radius - 0.05
	var traveled := 0.0
	var start_pos: Vector3 = body.global_position
	for _i in range(150):
		var motion: Dictionary = motor.move_body(body, Vector2(dir.x, dir.z), false, 1.0 / 30.0, 4.0)
		traveled += (body.global_position - start_pos).length()
		start_pos = body.global_position
	var final_dist: float = body.global_position.distance_to(pair["wall_pos"] as Vector3)
	assert_float(traveled).is_greater(0.1) \
		.override_failure_message("马达应向墙产生位移（无位移说明碰撞或朝向错误）")
	assert_float(final_dist).is_greater_equal(min_allowed_dist) \
		.override_failure_message("持续向墙输入 5 秒不得穿墙（距墙心 %.2f < 允许 %.2f）" % [final_dist, min_allowed_dist])
	c.queue_free()

func test_motor_moves_freely_within_walkable_cell() -> void:
	# 反例：同单元内自由移动不受墙阻挡（马达只被真实墙体约束）。
	var c := _build(SEED_A)
	var layout: LayoutClass = c._layout
	var pair := _find_wall_adjacent_cell(layout)
	assert_bool(not pair.is_empty()).is_true()
	var body := _make_body(c, pair["walk_pos"])
	await get_tree().physics_frame
	var motor: Motor = auto_free(Motor.new())
	# 沿【离开墙】方向移动 1 秒——单元内无墙，位移应接近理论值（速度 × 时间）。
	var away := (pair["walk_pos"] as Vector3 - pair["wall_pos"] as Vector3)
	away.y = 0.0
	away = away.normalized()
	for _i in range(30):
		motor.move_body(body, Vector2(away.x, away.z), false, 1.0 / 30.0, 4.0)
	# 远离墙方向至少穿过本格一半以上（>1m）——证明碰撞世界只阻挡真实墙体、
	# 不产生额外障碍（延伸方向后续格可能仍有墙，故不断言完整 4m）。
	var actual: float = (body.global_position - (pair["walk_pos"] as Vector3)).length()
	assert_float(actual).is_greater(1.0) \
		.override_failure_message("单元内自由移动被意外阻挡（实际 %.2f m）" % actual)
	c.queue_free()

func test_collision_only_keeps_layout_fingerprint_identical() -> void:
	# collision-only 与真实构建共用同一 layout 管线：指纹与确定性一致。
	var c := _build(SEED_A)
	var fp: String = c.layout_fingerprint()
	assert_bool(fp != "none").is_true()
	# 同 seed 再次构建 → 同一指纹（确定性）。
	var c2 := _build(SEED_A)
	assert_str(c2.layout_fingerprint()).is_equal(fp)
	c.queue_free()
	c2.queue_free()
