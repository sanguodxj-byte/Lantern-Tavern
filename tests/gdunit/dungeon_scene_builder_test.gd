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
	# 用独立 parent 避免被共享 _parent 的累积子节点干扰
	var parent := Node3D.new()
	add_child(parent)
	var builder := DungeonSceneBuilder.new()
	var layout := _make_3x3_floor_layout()
	layout.hazard_anchors.append({"hazard_type": "spikes", "anchor_cell": Vector2i(1,1), "direction": Vector2i(1,0), "room_index": 0, "safe_approach_cells": [], "kick_lane_index": 0})
	var result := builder.build(layout, parent)
	# parent 的直接子节点应是 9 个 root，不应有陷阱节点
	var direct_children := []
	for c in parent.get_children():
		direct_children.append(c.name)
	assert_int(direct_children.size()).is_equal(9)
	for name in direct_children:
		assert_bool(name.ends_with("Root")).is_true()
	result.dispose()
	parent.queue_free()

func test_build_result_dispose_frees_roots() -> void:
	var builder := DungeonSceneBuilder.new()
	var layout := _make_3x3_floor_layout()
	var result := builder.build(layout, _parent)
	var terrain := result.terrain_root
	result.dispose()
	# queue_free 异步；判 invalid 由 is_instance_valid 给 false 需等帧
	# 这里至少 terrain_root 引用置空
	assert_object(result.terrain_root).is_null()
	assert_bool(result.is_built()).is_false()

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
	# interaction_root 下子节点数 == layout.chest_spawn_specs.size()
	assert_int(result.interaction_root.get_child_count()).is_equal(layout.chest_spawn_specs.size())
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
