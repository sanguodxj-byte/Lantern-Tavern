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


# ── helpers ──────────────────────────────────────────────────
func _make_3x3_floor_layout() -> DungeonLayout:
	var layout := DungeonLayout.new()
	layout.width = 3
	layout.height = 3
	layout.grid = [[1,1,1],[1,1,1],[1,1,1]]
	layout.heights = [[3.0,3.0,3.0],[3.0,3.0,3.0],[3.0,3.0,3.0]]
	layout.tile_size = 3.0
	return layout
