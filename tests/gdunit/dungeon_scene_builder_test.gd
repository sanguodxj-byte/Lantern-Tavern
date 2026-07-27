extends GdUnitTestSuite

# 阶段 7 测试：DungeonSceneBuilder 集中节点实例化，产 DungeonBuildResult 分 root。
# 覆盖：分 root 创建、hazard prefab 映射、chest prefab 映射、节点不挂 parent 根、
#       streamed 注册、dispose 清理、集成 isaac。

var _parent: Node3D

func before() -> void:
	load("res://scenes/expedition/dungeon_scene_builder.gd")
	load("res://scenes/expedition/dungeon_build_result.gd")
	load("res://scenes/expedition/dungeon_layout.gd")
	load("res://scenes/expedition/dungeon_generation_config.gd")
	load("res://scenes/expedition/dungeon_generator.gd")
	load("res://scenes/expedition/dungeon_hazard_planner.gd")
	load("res://scenes/expedition/dungeon_spawn_planner.gd")
	_parent = Node3D.new()
	add_child(_parent)

func after() -> void:
	if is_instance_valid(_parent):
		_parent.queue_free()

func test_build_empty_layout_returns_unbuilt_result() -> void:
	var builder := DungeonSceneBuilder.new()
	var result := builder.build(DungeonLayout.new(), _parent)
	assert_bool(result.is_built()).is_false()

func test_build_null_parent_returns_unbuilt_result() -> void:
	var builder := DungeonSceneBuilder.new()
	var layout := _make_3x3_floor_layout()
	var result := builder.build(layout, null)
	assert_bool(result.is_built()).is_false()

func test_build_creates_all_roots() -> void:
	var builder := DungeonSceneBuilder.new()
	var layout := _make_3x3_floor_layout()
	var result := builder.build(layout, _parent)
	assert_bool(result.is_built()).is_true()
	assert_object(result.terrain_root).is_not_null()
	assert_object(result.collision_root).is_not_null()
	assert_object(result.doors_root).is_not_null()
	assert_object(result.hazards_root).is_not_null()
	assert_object(result.decor_root).is_not_null()
	assert_object(result.spawn_root).is_not_null()
	assert_object(result.interaction_root).is_not_null()
	assert_object(result.streamed_visual_root).is_not_null()
	assert_object(result.streamed_physics_root).is_not_null()
	# 每个 root 都是 _parent 的直接子节点
	for root in [result.terrain_root, result.collision_root, result.doors_root,
				result.hazards_root, result.decor_root, result.spawn_root,
				result.interaction_root, result.streamed_visual_root, result.streamed_physics_root]:
		assert_object(root.get_parent()).is_equal(_parent)

func test_build_hazard_anchor_instantiates_prefab() -> void:
	var builder := DungeonSceneBuilder.new()
	var layout := _make_3x3_floor_layout()
	layout.hazard_anchors.append({
		"hazard_type": "spikes", "anchor_cell": Vector2i(1, 1),
		"direction": Vector2i(1, 0), "room_index": 0,
		"safe_approach_cells": [], "kick_lane_index": 0,
	})
	var result := builder.build(layout, _parent)
	# hazards_root 下应有 1 个子节点
	assert_int(result.hazards_root.get_child_count()).is_equal(1)
	var trap := result.hazards_root.get_child(0) as Node3D
	assert_object(trap).is_not_null()
	assert_bool(trap.get_meta("hazard_anchor", false)).is_true()
	# streamed_physics 注册了
	assert_bool(result.streamed_physics_nodes.has(trap)).is_true()

func test_build_hazard_prefab_mapping() -> void:
	var builder := DungeonSceneBuilder.new()
	# 验证 hazard_type 字符串 ID 映射到正确 prefab（spikes/acid/flame_vent 各 1 个锚点）
	var layout := _make_3x3_floor_layout()
	layout.hazard_anchors.append({"hazard_type": "spikes", "anchor_cell": Vector2i(0, 0), "direction": Vector2i(1,0), "room_index": 0, "safe_approach_cells": [], "kick_lane_index": 0})
	layout.hazard_anchors.append({"hazard_type": "flame_vent", "anchor_cell": Vector2i(1, 0), "direction": Vector2i(1,0), "room_index": 0, "safe_approach_cells": [], "kick_lane_index": 0})
	layout.hazard_anchors.append({"hazard_type": "acid", "anchor_cell": Vector2i(2, 0), "direction": Vector2i(1,0), "room_index": 0, "safe_approach_cells": [], "kick_lane_index": 0})
	var result := builder.build(layout, _parent)
	assert_int(result.hazards_root.get_child_count()).is_equal(3)
	# 未知 hazard_type 不应崩，跳过
	layout.hazard_anchors.append({"hazard_type": "lava", "anchor_cell": Vector2i(0, 1), "direction": Vector2i(1,0), "room_index": 0, "safe_approach_cells": [], "kick_lane_index": 0})
	# 重新 build 一次看未知 type 跳过
	var result2 := builder.build(layout, _parent)
	# hazards_root 下仍是 3 个（lava 跳过）——但 build 新建了 root，旧 result 不复用
	assert_int(result2.hazards_root.get_child_count()).is_equal(3)
	# 清理 result2（避免泄漏）
	result2.dispose()

func test_build_hazard_prefabs_receive_placement_semantics() -> void:
	var builder := DungeonSceneBuilder.new()
	var layout := _make_3x3_floor_layout()
	layout.hazard_anchors.append({"hazard_type": "spikes", "anchor_cell": Vector2i(1, 0), "direction": Vector2i(1, 0), "room_index": 0})
	layout.hazard_anchors.append({"hazard_type": "acid", "anchor_cell": Vector2i(1, 2), "direction": Vector2i(0, -1), "room_index": 0})
	var result := builder.build(layout, _parent)
	var spikes := result.hazards_root.get_child(0) as SpikesTrap
	var acid := result.hazards_root.get_child(1) as AcidTrap
	assert_str(String(spikes.get_meta("spike_mount", ""))).is_equal("floor")
	assert_float(absf(absf(spikes.rotation_degrees.x) - 90.0)).is_less_equal(0.1)
	assert_float(spikes.position.y).is_less_equal(0.2)
	assert_bool(bool(acid.get_meta("acid_ground_only", false))).is_true()
	assert_bool(bool(acid.get_meta("acid_pit", false))).is_true()
	assert_object(acid.find_child("AcidPit", true, false)).is_not_null()

func test_build_chest_instantiates_prefab() -> void:
	var builder := DungeonSceneBuilder.new()
	var layout := _make_3x3_floor_layout()
	layout.chest_spawn_specs.append({"chest_type": "normal_chest", "cell": Vector2i(0, 0), "room_index": 0})
	layout.chest_spawn_specs.append({"chest_type": "boss_chest", "cell": Vector2i(2, 2), "room_index": 0})
	var result := builder.build(layout, _parent)
	# interaction_root 下应有 2 个子节点
	assert_int(result.interaction_root.get_child_count()).is_equal(2)
	for chest in result.interaction_root.get_children():
		assert_bool(chest.get_meta("topdown_kind", "") == "chest").is_true()

func test_build_nodes_not_directly_on_parent_root() -> void:
	# 阶段 7 核心约束：节点不直接 add 到 parent 根，全走分 root
	# NavigationRegion3D 允许作为 parent 直接子节点
	var parent := Node3D.new()
	add_child(parent)
	var builder := DungeonSceneBuilder.new()
	var layout := _make_3x3_floor_layout()
	layout.hazard_anchors.append({"hazard_type": "spikes", "anchor_cell": Vector2i(1,1), "direction": Vector2i(1,0), "room_index": 0, "safe_approach_cells": [], "kick_lane_index": 0})
	var result := builder.build(layout, parent)
	var root_count := 0
	var allowed_extra := 0
	for c in parent.get_children():
		if str(c.name).ends_with("Root"):
			root_count += 1
		elif str(c.name) == "DungeonNavigationRegion" or c is NavigationRegion3D:
			allowed_extra += 1
		else:
			assert_bool(false).override_failure_message("parent 下出现非 root 节点: %s" % c.name).is_true()
	assert_int(root_count).is_equal(9)
	assert_int(parent.get_child_count()).is_equal(root_count + allowed_extra)
	result.dispose()
	parent.queue_free()

func test_build_result_dispose_frees_roots() -> void:
	var builder := DungeonSceneBuilder.new()
	var layout := _make_3x3_floor_layout()
	var result := builder.build(layout, _parent)
	var terrain := result.terrain_root
	result.dispose()
	# 所有权：parent 拥有 root；dispose 只清空引用，不 queue_free
	assert_object(result.terrain_root).is_null()
	assert_bool(result.is_built()).is_false()
	assert_object(terrain).is_not_null()
	assert_bool(is_instance_valid(terrain)).is_true()
	assert_object(terrain.get_parent()).is_equal(_parent)


func test_downstairs_steps_use_non_metal_matte_material() -> void:
	var builder := DungeonSceneBuilder.new()
	var layout := _make_3x3_floor_layout()
	layout.room_roles["stairs"] = Rect2i(0, 0, 3, 3)
	var result := builder.build(layout, _parent)
	var stairs := result.interaction_root.get_node("DownstairsPortal")
	var step_mat := stairs.get_node("DownstairsStep1").material_override as StandardMaterial3D
	assert_object(step_mat).is_not_null()
	assert_int(step_mat.specular_mode).is_equal(BaseMaterial3D.SPECULAR_DISABLED)
	assert_float(step_mat.metallic).is_equal_approx(0.0, 0.001)
	assert_float(step_mat.roughness).is_greater_equal(0.75)
	result.dispose()


func test_dungeon_decor_uses_environment_material_profile() -> void:
	var source := (load("res://scenes/expedition/dungeon_scene_builder.gd") as GDScript).source_code
	assert_bool(source.contains("VOXEL_LIGHTING.apply_to_tree")) \
		.override_failure_message("地牢装饰必须统一经过非金属环境材质适配").is_true()
	var iron := StandardMaterial3D.new()
	iron.metallic = 0.9
	iron.roughness = 0.2
	var adapted := VoxelLightingAdapter.adapt_standard_material(iron)
	assert_int(adapted.specular_mode).is_equal(BaseMaterial3D.SPECULAR_DISABLED)
	assert_float(adapted.metallic).is_equal_approx(0.0, 0.001)
	assert_float(adapted.roughness).is_greater_equal(0.85)


func test_extraction_portal_materials_disable_specular() -> void:
	var portal_scene := load("res://scenes/expedition/extraction_portal.tscn") as PackedScene
	var portal := portal_scene.instantiate()
	add_child(portal)
	var material_count := 0
	for mesh_node in portal.find_children("*", "MeshInstance3D", true, false):
		var mesh := mesh_node as MeshInstance3D
		var material := mesh.material_override as StandardMaterial3D
		if material == null:
			continue
		material_count += 1
		assert_int(material.specular_mode).is_equal(BaseMaterial3D.SPECULAR_DISABLED)
		assert_float(material.metallic).is_equal_approx(0.0, 0.001)
		assert_float(material.roughness).is_greater_equal(0.75)
	assert_int(material_count).is_greater(0)
	portal.free()

func test_integration_isaac_layout_builds_hazards_and_chests() -> void:
	# isaac 真产出：hazard + chest planner 跑完后，scene builder 应能 instantiate
	var cfg := DungeonGenerationConfig.new()
	cfg.algorithm = "isaac"
	var gen := DungeonGenerator.new()
	var layout := gen.generate(cfg)
	DungeonHazardPlanner.new().plan(layout)
	var spawn_planner := DungeonSpawnPlanner.new()
	spawn_planner.plan_chest_spawns(layout)
	var builder := DungeonSceneBuilder.new()
	var result := builder.build(layout, _parent)
	assert_bool(result.is_built()).is_true()
	# hazards_root 下子节点数 == layout.hazard_anchors.size()
	assert_int(result.hazards_root.get_child_count()).is_equal(layout.hazard_anchors.size())
	# interaction_root 除 chest 外还可能有 downstairs / extraction portal，按 meta 分类统计
	var chest_count := 0
	var stairs_count := 0
	var extraction_count := 0
	for child in result.interaction_root.get_children():
		var kind := str(child.get_meta("topdown_kind", ""))
		if kind == "chest":
			chest_count += 1
		elif kind == "stairs":
			stairs_count += 1
		elif kind == "extraction" or child.name == "ExtractionPortal":
			extraction_count += 1
	assert_int(chest_count).is_equal(layout.chest_spawn_specs.size())
	if layout.room_roles.has("stairs"):
		assert_int(stairs_count).is_greater_equal(1)
	assert_int(result.interaction_root.get_child_count()) \
		.is_greater_equal(layout.chest_spawn_specs.size())
	result.dispose()


func test_build_registers_every_door_visual_and_collision_for_streaming() -> void:
	var cfg := DungeonGenerationConfig.new()
	cfg.algorithm = "isaac"
	cfg.seed = 94021
	var layout := DungeonGenerator.new().generate(cfg)
	var result := DungeonSceneBuilder.new().build(layout, _parent)
	assert_int(result.doors_root.get_child_count()).is_greater(0)
	for child in result.doors_root.get_children():
		var registered := result.streamed_visual_nodes.has(child) \
			or result.streamed_physics_nodes.has(child)
		assert_bool(registered) \
			.override_failure_message("门节点未注册流送: %s" % child.name).is_true()
	for child in result.collision_root.get_children():
		assert_bool(result.streamed_physics_nodes.has(child)) \
			.override_failure_message("碰撞节点未注册流送: %s" % child.name).is_true()

func test_generated_doors_keep_wall_support_on_both_sides() -> void:
	var builder := DungeonSceneBuilder.new()
	for test_seed in [94021, 3401, 71231, 91811, 271828]:
		var cfg := DungeonGenerationConfig.new()
		cfg.algorithm = "isaac"
		cfg.seed = test_seed
		var layout := DungeonGenerator.new().generate(cfg)
		for room in layout.rooms:
			for spec in builder._collect_room_door_specs(layout, room):
				var cell: Vector2i = spec["inside"]
				var direction: Vector2i = spec["dir"]
				var side_a: Vector2i = Vector2i(-direction.y, direction.x)
				var side_b: Vector2i = -side_a
				assert_bool(builder._is_grid_wall(layout.grid, cell.x + side_a.x, cell.y + side_a.y)) \
					.override_failure_message("门的一侧缺少墙体支撑: seed=%d room=%s cell=%s dir=%s" % [test_seed, room, cell, direction]).is_true()
				assert_bool(builder._is_grid_wall(layout.grid, cell.x + side_b.x, cell.y + side_b.y)) \
					.override_failure_message("门的另一侧缺少墙体支撑: seed=%d room=%s cell=%s dir=%s" % [test_seed, room, cell, direction]).is_true()

func test_connected_wall_component_uses_one_integer_height() -> void:
	var layout := DungeonLayout.new()
	layout.width = 7
	layout.height = 7
	layout.tile_size = 3.0
	layout.grid = []
	layout.heights = []
	for y in range(7):
		var row: Array = []
		var height_row: Array = []
		for x in range(7):
			row.append(2 if x == 0 or y == 0 or x == 6 or y == 6 else 1)
			height_row.append(5.0 if Vector2i(x, y) == Vector2i(1, 3) else 3.0)
		layout.grid.append(row)
		layout.heights.append(height_row)
	layout.rooms = [Rect2i(1, 1, 5, 5)]
	layout.room_roles["start"] = Rect2i(1, 1, 5, 5)
	layout.room_roles["boss"] = Rect2i(1, 1, 1, 1)

	var result := DungeonBuildResult.new()
	DungeonSceneBuilder.new()._build_terrain(layout, result)
	assert_int(result.wall_h_map.size()).is_equal(24)
	for wall_height in result.wall_h_map.values():
		assert_float(float(wall_height)).is_equal(5.0)
		assert_bool(DungeonGenerationConfig.is_integer_height(float(wall_height))).is_true()
	assert_int(result.wall_transforms_by_height.size()).is_equal(1)

func test_merged_wall_collision_faces_point_outward() -> void:
	# ConcavePolygonShape3D uses triangle winding for one-sided collision. The
	# first wall face is the negative-Z face and must point toward negative Z;
	# inward winding lets a CharacterBody3D enter the wall from outside.
	var builder := DungeonSceneBuilder.new()
	var result := DungeonBuildResult.new()
	result.collision_root = Node3D.new()
	_parent.add_child(result.collision_root)
	builder._build_merged_collision_group(
		_make_3x3_floor_layout(), result, "WallCollision", [Transform3D.IDENTITY], Vector3(3.0, 3.0, 3.0))
	var body := result.collision_root.get_child(0) as StaticBody3D
	var collision := body.get_node("MergedCollision") as CollisionShape3D
	var shape := collision.shape as ConcavePolygonShape3D
	assert_bool(shape.backface_collision) \
		.override_failure_message("墙体是实体体积，必须启用背面碰撞以阻止从地牢内部穿入").is_true()
	var faces := shape.get_faces()
	assert_int(faces.size()).is_equal(36)
	var first_normal := Plane(faces[0], faces[1], faces[2]).normal
	assert_float(first_normal.z).is_less(-0.9)
	result.collision_root.queue_free()

func test_character_body_stops_at_merged_wall_collision() -> void:
	# Integration regression: use the same merged ConcavePolygon wall shape as
	# production and drive a player capsule into it for several physics frames.
	var builder := DungeonSceneBuilder.new()
	var result := DungeonBuildResult.new()
	result.collision_root = Node3D.new()
	_parent.add_child(result.collision_root)
	builder._build_merged_collision_group(
		_make_3x3_floor_layout(), result, "WallCollision", [Transform3D.IDENTITY], Vector3(3.0, 3.0, 3.0))

	var player := CharacterBody3D.new()
	player.collision_layer = 2
	player.collision_mask = 1
	var player_collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.25
	capsule.height = 1.7
	capsule.margin = 0.04
	player_collision.shape = capsule
	player_collision.position.y = 0.85
	player.add_child(player_collision)
	player.position = Vector3(-2.4, 0.0, 0.0)
	_parent.add_child(player)
	await get_tree().physics_frame
	for _frame in range(20):
		player.velocity = Vector3(5.0, 0.0, 0.0)
		player.move_and_slide()
		await get_tree().physics_frame
	assert_float(player.position.x).is_less_equal(-1.70)
	player.free()
	result.collision_root.queue_free()

func test_streamed_boundary_walls_stop_character_from_inside_on_all_sides() -> void:
	# Production-path regression: build the same wall border used by a dungeon,
	# register it through streaming, then approach every wall from a walkable cell.
	# The capsule must stop before its center crosses the wall's inner face.
	await get_tree().process_frame
	var stage := Node3D.new()
	add_child(stage)
	var layout := DungeonLayout.new()
	layout.width = 5
	layout.height = 5
	layout.tile_size = 3.0
	for y in range(5):
		var row: Array = []
		var heights: Array = []
		for x in range(5):
			row.append(2 if x == 0 or y == 0 or x == 4 or y == 4 else 1)
			heights.append(3.0)
		layout.grid.append(row)
		layout.heights.append(heights)
	layout.player_spawn_cell = Vector2i(2, 2)

	var result := DungeonSceneBuilder.new().build(layout, stage)
	var controller := DungeonStreamingController.new()
	stage.add_child(controller)
	controller.configure(layout, result)

	var player := CharacterBody3D.new()
	# This test only exercises the environment mask. Keep the player out of
	# unrelated trigger Areas left by other builder contract cases.
	player.collision_layer = 0
	player.collision_mask = PhysicsSetup.LAYER_ENVIRONMENT
	var player_collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.25
	capsule.height = 1.7
	capsule.margin = 0.04
	player_collision.shape = capsule
	player_collision.position.y = 0.85
	player.add_child(player_collision)
	stage.add_child(player)
	controller.set_player(player)
	await get_tree().physics_frame

	var cases := [
		{"start": Vector3(-4.5, 0.0, -1.5), "velocity": Vector3(-5.0, 0.0, 0.0), "min": -5.90, "max": -4.5},
		{"start": Vector3(1.5, 0.0, -1.5), "velocity": Vector3(5.0, 0.0, 0.0), "min": 1.5, "max": 2.90},
		{"start": Vector3(-1.5, 0.0, -4.5), "velocity": Vector3(0.0, 0.0, -5.0), "min": -5.90, "max": -4.5},
		{"start": Vector3(-1.5, 0.0, 1.5), "velocity": Vector3(0.0, 0.0, 5.0), "min": 1.5, "max": 2.90},
	]
	for test_case in cases:
		player.position = test_case["start"]
		player.velocity = Vector3.ZERO
		controller.update_streaming(true)
		await get_tree().physics_frame
		for _frame in range(20):
			player.velocity = test_case["velocity"]
			player.move_and_slide()
			await get_tree().physics_frame
		var position_axis := player.position.x if absf(test_case["velocity"].x) > 0.0 else player.position.z
		assert_float(position_axis).is_greater_equal(test_case["min"])
		assert_float(position_axis).is_less_equal(test_case["max"])

	controller.clear()
	controller.queue_free()
	player.queue_free()
	result.dispose()
	stage.queue_free()

func test_door_surrounds_fill_remaining_integer_tile_width() -> void:
	var builder := DungeonSceneBuilder.new()
	var layout := _make_3x3_floor_layout()
	var result := DungeonBuildResult.new()
	result.doors_root = Node3D.new()
	result.collision_root = Node3D.new()
	_parent.add_child(result.doors_root)
	_parent.add_child(result.collision_root)

	builder._spawn_door_wall_surround("StandardSurround", Vector3.ZERO, Vector2i(1, 1), Vector2i(1, 2), Vector2i(0, 1), false, 3.0, result, _parent, layout)
	var standard_left := result.doors_root.get_node("StandardSurroundLeftJamb") as MeshInstance3D
	var standard_right := result.doors_root.get_node("StandardSurroundRightJamb") as MeshInstance3D
	var standard_side_width := (standard_left.mesh as BoxMesh).size.x
	assert_float(standard_side_width).is_equal(1.0)
	assert_float(standard_side_width * 2.0 + DungeonDoor.STANDARD_SIZE.x).is_equal(3.0)

	builder._spawn_door_wall_surround("BossSurround", Vector3.ZERO, Vector2i(1, 1), Vector2i(1, 2), Vector2i(0, 1), true, 3.0, result, _parent, layout)
	var boss_left := result.doors_root.get_node("BossSurroundLeftJamb") as MeshInstance3D
	var boss_right := result.doors_root.get_node("BossSurroundRightJamb") as MeshInstance3D
	var boss_side_width := (boss_left.mesh as BoxMesh).size.x
	assert_float(boss_side_width).is_equal(0.5)
	assert_float(boss_side_width * 2.0 + DungeonDoor.BOSS_SIZE.x).is_equal(3.0)
	assert_object(standard_right).is_not_null()
	assert_object(boss_right).is_not_null()

	result.dispose()

func test_door_at_height_boundary_closes_full_transition_above_clearance() -> void:
	var builder := DungeonSceneBuilder.new()
	var layout := _make_3x3_floor_layout()
	for x in range(layout.width):
		layout.heights[1][x] = 5.0 if x >= 2 else 3.0
	var result := DungeonBuildResult.new()
	result.doors_root = Node3D.new()
	result.collision_root = Node3D.new()
	_parent.add_child(result.doors_root)
	_parent.add_child(result.collision_root)

	builder._spawn_door_wall_surround("HeightBoundary", Vector3.ZERO, Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 0), false, 3.0, result, _parent, layout)
	var left_jamb := result.doors_root.get_node("HeightBoundaryLeftJamb") as MeshInstance3D
	var lintel := result.doors_root.get_node("HeightBoundaryLintel") as MeshInstance3D
	var left_size := (left_jamb.mesh as BoxMesh).size
	var lintel_size := (lintel.mesh as BoxMesh).size
	assert_float(left_jamb.position.y + left_size.y * 0.5).is_equal_approx(5.0, 0.0001)
	assert_float(lintel.position.y + lintel_size.y * 0.5).is_equal_approx(5.0, 0.0001)
	assert_float(lintel.position.y - lintel_size.y * 0.5).is_greater_equal(2.0)
	result.dispose()

func test_closed_door_is_added_to_navigation_obstacle_source() -> void:
	var builder := DungeonSceneBuilder.new()
	var layout := _make_3x3_floor_layout()
	var result := DungeonBuildResult.new()
	result.doors_root = Node3D.new()
	_parent.add_child(result.doors_root)
	var door := DungeonDoor.new()
	result.doors_root.add_child(door)
	door.configure(DungeonDoor.KIND_STANDARD, Vector2i(1, 0), StandardMaterial3D.new())

	var faces := builder._build_navigation_obstacle_faces(layout, result)

	assert_int(faces.size()).is_equal(36)
	assert_bool(door.get_node("NavigationLink3D").enabled).is_false()
	result.doors_root.queue_free()

func test_door_creates_navigation_link_on_first_configuration() -> void:
	var door := DungeonDoor.new()
	_parent.add_child(door)
	door.configure(DungeonDoor.KIND_STANDARD, Vector2i(1, 0), StandardMaterial3D.new())

	var link := door.get_node_or_null("NavigationLink3D") as NavigationLink3D
	assert_object(link).is_not_null()
	if link != null:
		assert_bool(link.enabled).is_false()
		assert_bool(link.bidirectional).is_true()
	door.queue_free()


func test_batched_decor_template_cache_reuses_bounds_and_mesh_parts() -> void:
	# 批处理装饰在每个实例上只需要一次模板实例化；后续实例应复用 bounds 与 mesh parts。
	var builder := DungeonSceneBuilder.new()
	var source := (load("res://scenes/expedition/dungeon_scene_builder.gd") as GDScript).source_code
	assert_bool(source.contains("_batched_decor_cache")) \
		.override_failure_message("builder 必须缓存批处理装饰的模板数据").is_true()
	assert_bool(source.contains("_get_batched_decor_cache")) \
		.override_failure_message("builder 必须通过统一 helper 获取批处理装饰模板缓存").is_true()
	assert_bool(source.contains("cached_data[\"bounds\"]")) \
		.override_failure_message("批处理装饰应复用缓存的 AABB").is_true()
	assert_bool(source.contains("cached_data[\"parts\"]")) \
		.override_failure_message("批处理装饰 MultiMesh 应复用缓存的 mesh parts").is_true()
	# builder 实例隔离缓存，避免跨地牢持有旧资源。
	assert_int(builder._batched_decor_cache.size()).is_equal(0)

func test_room_focus_visuals_have_no_player_collision() -> void:
	var builder := DungeonSceneBuilder.new()
	var layout := _make_3x3_floor_layout()
	layout.room_focus_specs.append({
		"focus_kind": "boss_altar",
		"cell": Vector2i(1, 1),
		"room_index": 0,
	})
	var result := DungeonBuildResult.new()
	result.decor_root = Node3D.new()
	_parent.add_child(result.decor_root)
	builder._build_room_focuses(layout, result)

	assert_int(result.decor_root.get_child_count()).is_equal(1)
	var focus := result.decor_root.get_child(0) as Node3D
	assert_bool(bool(focus.get_meta("room_focus", false))).is_true()
	assert_str(String(focus.get_meta("focus_kind", ""))).is_equal("boss_altar")
	assert_int(result.streamed_visual_nodes.size()).is_equal(1)
	assert_int(result.streamed_physics_nodes.size()).is_equal(0)
	assert_bool(focus.find_children("*", "PhysicsBody3D", true, false).is_empty()).is_true()
	result.dispose()


# ── helpers ──────────────────────────────────────────────────
func _make_3x3_floor_layout() -> DungeonLayout:
	var layout := DungeonLayout.new()
	layout.width = 3
	layout.height = 3
	layout.grid = [[1,1,1],[1,1,1],[1,1,1]]
	layout.heights = [[3.0,3.0,3.0],[3.0,3.0,3.0],[3.0,3.0,3.0]]
	layout.tile_size = 3.0
	return layout
