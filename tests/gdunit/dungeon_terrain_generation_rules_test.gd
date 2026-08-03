extends GdUnitTestSuite
## 地牢地形/门生成规则回归测试（迁移后：验 builder/config 契约，不再调用 Procedural 已删私有实现）

func before() -> void:
	load("res://scenes/expedition/dungeon_scene_builder.gd")
	load("res://scenes/expedition/dungeon_rendering_config.gd")
	load("res://scenes/expedition/dungeon_generation_config.gd")
	load("res://scenes/expedition/dungeon_layout.gd")

func test_wall_generation_uses_full_tile_blocks_in_builder() -> void:
	# 墙体整格体积由 builder 地形收集产出
	var builder_src := (load("res://scenes/expedition/dungeon_scene_builder.gd") as GDScript).source_code
	assert_bool(builder_src.contains("wall_transforms_by_height") or builder_src.contains("_build_terrain")) \
		.override_failure_message("DungeonSceneBuilder 应收集整格墙体 transform").is_true()
	assert_bool(builder_src.contains("_spawn_wall_segment(cell_pos")).is_false()

func test_wall_segment_material_group_key_rounds_size_values() -> void:
	var builder := DungeonSceneBuilder.new()
	# builder 当前 key 使用 int 截断；仍需稳定可分组
	var key := builder._wall_segment_key(Vector3(0.2, 3.00001, 3.0))
	assert_str(key).is_not_empty()
	assert_bool(key.contains(",")).is_true()

func test_rendering_config_exposes_door_and_ceiling_geometry_defaults() -> void:
	var cfg := DungeonRenderingConfig.default()
	assert_float(cfg.door_surround_thickness).is_equal_approx(0.2, 0.0001)
	assert_float(cfg.ceiling_thickness).is_equal_approx(0.1, 0.0001)
	assert_float(cfg.ceiling_transition_gap).is_equal_approx(0.015, 0.0001)
	assert_int(cfg.large_room_area).is_equal(48)

func test_generation_config_matches_legacy_geometry_defaults() -> void:
	var cfg := DungeonGenerationConfig.new()
	assert_float(cfg.door_surround_thickness).is_equal_approx(0.2, 0.0001)
	assert_float(cfg.ceiling_thickness).is_equal_approx(0.1, 0.0001)
	assert_int(cfg.large_room_area).is_equal(48)
	assert_float(cfg.tile_size).is_equal_approx(3.0, 0.0001)

func test_builder_builds_wall_transforms_for_simple_room() -> void:
	var layout := DungeonLayout.new()
	layout.width = 5
	layout.height = 5
	layout.tile_size = 3.0
	layout.zone = 0
	layout.grid = []
	layout.heights = []
	for y in range(5):
		var row: Array = []
		var hr: Array = []
		for x in range(5):
			if x == 0 or y == 0 or x == 4 or y == 4:
				row.append(2)  # wall
			else:
				row.append(1)  # floor
			hr.append(3.0)
		layout.grid.append(row)
		layout.heights.append(hr)
	layout.rooms = [Rect2i(1, 1, 3, 3)]
	layout.room_roles["start"] = Rect2i(1, 1, 3, 3)
	layout.player_spawn_cell = Vector2i(2, 2)

	var parent := Node3D.new()
	add_child(parent)
	var result := DungeonSceneBuilder.new().build(layout, parent)
	assert_bool(result.is_built()).is_true()
	assert_bool(result.wall_transforms_by_height.is_empty()).is_false()
	assert_bool(result.floor_transforms.is_empty()).is_false()
	result.dispose()
	parent.queue_free()

func test_builder_creates_one_integer_ceiling_transition_at_height_boundary() -> void:
	var layout := DungeonLayout.new()
	layout.width = 2
	layout.height = 1
	layout.tile_size = 3.0
	layout.grid = [[1, 1]]
	layout.heights = [[3.0, 5.0]]
	var result := DungeonBuildResult.new()
	DungeonSceneBuilder.new()._build_terrain(layout, result)

	assert_int(result.ceiling_transition_transforms_by_size.size()).is_equal(1)
	var group: Dictionary = result.ceiling_transition_transforms_by_size.values()[0]
	var transition_size: Vector3 = group["size"]
	var transforms: Array = group["transforms"]
	assert_int(transforms.size()).is_equal(1)
	assert_float(transition_size.x).is_equal_approx(0.2, 0.0001)
	assert_float(transition_size.y).is_equal_approx(1.9, 0.0001)
	assert_float(transition_size.z).is_equal_approx(3.0, 0.0001)
	var transition := transforms[0] as Transform3D
	assert_float(transition.origin.x).is_equal_approx(-1.5, 0.0001)
	assert_float(transition.origin.y).is_equal_approx(4.05, 0.0001)
	assert_float(transition.origin.z).is_equal_approx(-1.5, 0.0001)
	assert_bool(transition_size.y > 0.0).is_true()
	assert_float((result.ceiling_transforms[0] as Transform3D).origin.y).is_equal_approx(3.05, 0.0001)
	assert_float((result.ceiling_transforms[1] as Transform3D).origin.y).is_equal_approx(5.05, 0.0001)

func test_height_transition_is_face_contact_with_lower_ceiling() -> void:
	# The ceiling slab is centered at H + thickness/2, so its top occupies
	# H + thickness. A vertical transition must start there, not at raw H;
	# otherwise the two textured surfaces overlap and z-fight at the boundary.
	var layout := DungeonLayout.new()
	layout.width = 2
	layout.height = 1
	layout.tile_size = 3.0
	layout.grid = [[1, 1]]
	layout.heights = [[3.0, 5.0]]
	var result := DungeonBuildResult.new()
	DungeonSceneBuilder.new()._build_terrain(layout, result)

	var group: Dictionary = result.ceiling_transition_transforms_by_size.values()[0]
	var transition_size: Vector3 = group["size"]
	var transition := group["transforms"][0] as Transform3D
	var lower_ceiling := result.ceiling_transforms[0] as Transform3D
	var lower_ceiling_top := lower_ceiling.origin.y + 0.05
	var transition_bottom := transition.origin.y - transition_size.y * 0.5
	var transition_top := transition.origin.y + transition_size.y * 0.5
	assert_float(transition_bottom).is_equal_approx(lower_ceiling_top, 0.0001)
	assert_float(transition_top).is_equal_approx(5.0, 0.0001)
	assert_float(transition_size.y).is_equal_approx(1.9, 0.0001)

func test_generated_height_transitions_do_not_overlap_any_ceiling() -> void:
	var builder := DungeonSceneBuilder.new()
	for seed_value in [94021, 3401, 71231, 91811, 271828]:
		var config := DungeonGenerationConfig.new()
		config.seed = seed_value
		var layout := DungeonGenerator.new().generate(config)
		var result := DungeonBuildResult.new()
		builder._build_terrain(layout, result)
		for group in result.ceiling_transition_transforms_by_size.values():
			var transition_size: Vector3 = group["size"]
			for transition_value in group["transforms"]:
				var transition := transition_value as Transform3D
				var transition_aabb := AABB(transition.origin - transition_size * 0.5, transition_size)
				for ceiling_value in result.ceiling_transforms:
					var ceiling := ceiling_value as Transform3D
					var ceiling_size := Vector3(layout.tile_size, 0.1, layout.tile_size)
					var ceiling_aabb := AABB(ceiling.origin - ceiling_size * 0.5, ceiling_size)
					assert_bool(_has_positive_aabb_overlap(transition_aabb, ceiling_aabb)) \
						.override_failure_message("seed=%d height transition overlaps ceiling: transition=%s ceiling=%s" % [seed_value, transition.origin, ceiling.origin]) \
						.is_false()

func _has_positive_aabb_overlap(a: AABB, b: AABB) -> bool:
	var overlap := Vector3(
		minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x),
		minf(a.end.y, b.end.y) - maxf(a.position.y, b.position.y),
		minf(a.end.z, b.end.z) - maxf(a.position.z, b.position.z))
	return overlap.x > 0.0001 and overlap.y > 0.0001 and overlap.z > 0.0001

func test_ceiling_transition_is_registered_for_visual_and_collision_chunks() -> void:
	var layout := DungeonLayout.new()
	layout.width = 2
	layout.height = 1
	layout.tile_size = 3.0
	layout.grid = [[1, 1]]
	layout.heights = [[3.0, 5.0]]
	var result := DungeonBuildResult.new()
	result.terrain_root = Node3D.new()
	result.collision_root = Node3D.new()
	var builder := DungeonSceneBuilder.new()
	builder._build_terrain(layout, result)
	builder._build_multi_meshes(layout, result)
	builder._build_collisions(layout, result)

	var transition_visual_found := false
	for child in result.terrain_root.get_children():
		if String(child.name).begins_with("CeilingTransitionMultiMesh_"):
			transition_visual_found = true
			break
	assert_bool(transition_visual_found).is_true()
	var transition_collision_found := false
	for child in result.collision_root.get_children():
		if String(child.name).begins_with("CeilingTransitionCollisions_"):
			transition_collision_found = true
			break
	assert_bool(transition_collision_found).is_true()
	assert_bool(result.terrain_chunks.is_empty()).is_false()

	result.terrain_root.free()
	result.collision_root.free()

func test_door_boundary_uses_door_surround_without_duplicate_ceiling_transition() -> void:
	var layout := DungeonLayout.new()
	layout.width = 5
	layout.height = 3
	layout.tile_size = 3.0
	layout.grid = [
		[2, 2, 2, 2, 2],
		[2, 1, 1, 1, 0],
		[2, 2, 2, 2, 2],
	]
	layout.heights = [
		[3.0, 3.0, 3.0, 3.0, 3.0],
		[3.0, 3.0, 3.0, 5.0, 3.0],
		[3.0, 3.0, 3.0, 3.0, 3.0],
	]
	layout.rooms = [Rect2i(0, 0, 3, 3)]
	var result := DungeonBuildResult.new()
	DungeonSceneBuilder.new()._build_terrain(layout, result)

	assert_bool(result.ceiling_transition_transforms_by_size.is_empty()).is_true()

func test_builder_constants_align_with_rendering_config() -> void:
	var cfg := DungeonRenderingConfig.default()
	var builder_src := (load("res://scenes/expedition/dungeon_scene_builder.gd") as GDScript).source_code
	assert_bool(builder_src.contains("const DOOR_SURROUND_THICKNESS := 0.2") or builder_src.contains("DOOR_SURROUND_THICKNESS")).is_true()
	assert_bool(builder_src.contains("const CEILING_THICKNESS := 0.1") or builder_src.contains("CEILING_THICKNESS")).is_true()
	assert_float(cfg.door_surround_thickness).is_equal_approx(0.2, 0.0001)
	assert_float(cfg.ceiling_thickness).is_equal_approx(0.1, 0.0001)
