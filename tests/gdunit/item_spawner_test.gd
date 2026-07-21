extends GdUnitTestSuite

# Tests for ItemSpawner autoload logic
# Note: These tests create a mock ItemSpawner instance (not the real autoload)
# to avoid depending on the full scene tree.

var _spawner: Node = null

const PLACEMENT_DATA := preload("res://data/item_placement_data.gd")
const TAGS := preload("res://data/item_tags.gd")

class BatchParent:
	extends Node3D

	var requested_paths: Array[String] = []
	var requested_positions: Array[Vector3] = []

	func _spawn_batched_decor(path: String, pos: Vector3) -> bool:
		requested_paths.append(path)
		requested_positions.append(pos)
		var shell := StaticBody3D.new()
		shell.name = "BatchedCollisionShell"
		shell.position = pos
		add_child(shell)
		return true

# 辅助方法：创建一个测试用 ItemSpawner 实例
func _make_spawner() -> Node:
	var script: GDScript = load("res://globals/equipment/item_spawner.gd")
	var s: Node = script.new()
	return s

func before_test() -> void:
	_spawner = _make_spawner()

func after_test() -> void:
	if is_instance_valid(_spawner):
		for child in _spawner.get_children():
			child.free()
		_spawner.free()
	_spawner = null


# ── Config Loading ───────────────────────────────────────────

func test_spawner_initializes_empty() -> void:
	assert_object(_spawner).is_not_null()


func test_load_config_populates_tags_from_json() -> void:
	_spawner._load_config()

	var tags: Array[String] = _spawner.get_all_tags()
	assert_int(tags.size()).is_greater(0)
	assert_array(tags).contains(TAGS.MATERIAL)
	assert_array(tags).contains(TAGS.CONTAINER)
	assert_array(tags).contains(TAGS.TREASURE)

	var container: Resource = _spawner.get_tag_config(TAGS.CONTAINER)
	assert_object(container).is_not_null()
	assert_float(container.get_effective_probability(3)).is_equal_approx(0.156, 0.001)
	var material: Resource = _spawner.get_tag_config(TAGS.MATERIAL)
	assert_object(material).is_not_null()
	assert_float(material.base_probability).is_equal_approx(0.008, 0.001)


# ── get_tag_config ───────────────────────────────────────────

func test_get_tag_config_by_default_returns_null() -> void:
	var cfg = _spawner.get_tag_config(TAGS.MATERIAL)
	# Before _ready, configs are not loaded; null expected
	assert_bool(cfg == null).is_true()


func test_register_tag_config() -> void:
	var data: Resource = PLACEMENT_DATA.new()
	data.tag = "test_register"
	data.base_probability = 0.42
	_spawner.register_tag_config(data)

	var retrieved = _spawner.get_tag_config("test_register")
	assert_object(retrieved).is_not_null()
	assert_float(retrieved.base_probability).is_equal_approx(0.42, 0.001)


func test_register_tag_config_empty_tag_ignored() -> void:
	var data: Resource = PLACEMENT_DATA.new()
	data.tag = ""
	_spawner.register_tag_config(data)

	assert_bool(_spawner.get_tag_config("") == null).is_true()


func test_register_tag_config_overwrites_existing() -> void:
	var data1: Resource = PLACEMENT_DATA.new()
	data1.tag = "overwrite_test"
	data1.base_probability = 0.1
	_spawner.register_tag_config(data1)

	var data2: Resource = PLACEMENT_DATA.new()
	data2.tag = "overwrite_test"
	data2.base_probability = 0.9
	_spawner.register_tag_config(data2)

	assert_float(_spawner.get_tag_config("overwrite_test").base_probability).is_equal_approx(0.9, 0.001)


# ── unregister_tag ───────────────────────────────────────────

func test_unregister_tag() -> void:
	var data: Resource = PLACEMENT_DATA.new()
	data.tag = "temp_tag"
	_spawner.register_tag_config(data)
	assert_object(_spawner.get_tag_config("temp_tag")).is_not_null()

	_spawner.unregister_tag("temp_tag")
	assert_bool(_spawner.get_tag_config("temp_tag") == null).is_true()


# ── get_all_tags ─────────────────────────────────────────────

func test_get_all_tags_after_registration() -> void:
	var before_tags = _spawner.get_all_tags()
	var count_before = before_tags.size()

	var data: Resource = PLACEMENT_DATA.new()
	data.tag = "new_tag_for_list"
	_spawner.register_tag_config(data)

	var after_tags = _spawner.get_all_tags()
	assert_int(after_tags.size()).is_equal(count_before + 1)
	assert_array(after_tags).contains("new_tag_for_list")


# ── spawn_item_by_tag (without scene tree) ───────────────────

func test_spawn_item_by_tag_unknown_tag_returns_null() -> void:
	var result = _spawner.spawn_item_by_tag("nonexistent", Vector3.ZERO, _spawner, 0)
	assert_bool(result == null).is_true()


func test_spawn_item_by_tag_material_with_config() -> void:
	# Register a material tag with a valid scene
	var data: Resource = PLACEMENT_DATA.new()
	data.tag = TAGS.MATERIAL
	data.base_probability = 1.0
	data.item_scene_paths = [
		{"path": "res://scenes/equipment/pickable_item.tscn", "weight": 100}
	]
	data.preload_scenes()
	_spawner.register_tag_config(data)

	# We can't fully instantiate the scene without a scene tree,
	# so this may return null in headless. We test the logic path.
	var result = _spawner.spawn_item_by_tag(TAGS.MATERIAL, Vector3.ZERO, _spawner, 0)
	# With the fallback, material should try the _spawn_material_fallback path
	# which needs ZoneManager autoload. In unit test without scene tree,
	# it'll still return a pickable_item instance or null.
	# The key test is that it doesn't crash.
	assert_bool(result == null or result is Node).is_true()
	if result != null:
		result.free()


func test_spawn_item_by_tag_decor_uses_parent_batching_when_available() -> void:
	var data: Resource = PLACEMENT_DATA.new()
	data.tag = TAGS.DECOR
	data.base_probability = 1.0
	data.item_scene_paths = [
		{"path": "res://scenes/props/decor/bench.tscn", "weight": 100}
	]
	data.preload_scenes()
	_spawner.register_tag_config(data)
	var parent := BatchParent.new()
	var spawn_pos := Vector3(1.0, 0.0, 2.0)

	var result = _spawner.spawn_item_by_tag(TAGS.DECOR, spawn_pos, parent, 0)

	assert_object(result).is_not_null()
	assert_int(parent.requested_paths.size()).is_equal(1)
	assert_str(parent.requested_paths[0]).is_equal("res://scenes/props/decor/bench.tscn")
	assert_bool(parent.requested_positions[0].is_equal_approx(spawn_pos)).is_true()
	assert_int(parent.get_child_count()).is_equal(1)
	assert_object(result).is_equal(parent.get_child(0))
	assert_str(result.get_meta("item_tag")).is_equal(TAGS.DECOR)
	assert_int(result.get_meta("spawn_zone")).is_equal(0)
	parent.free()


# ── _pick_weighted ───────────────────────────────────────────

func test_pick_weighted_empty_dict() -> void:
	var result = _spawner._pick_weighted({})
	assert_str(result).is_equal("")


func test_pick_weighted_single_entry() -> void:
	var result = _spawner._pick_weighted({"only": 100})
	assert_str(result).is_equal("only")


func test_pick_weighted_distribution() -> void:
	var weights := {"a": 80, "b": 20}
	var results := {"a": 0, "b": 0}
	var trials := 1000
	for i in range(trials):
		var pick = _spawner._pick_weighted(weights)
		results[pick] += 1

	# a should be chosen more often than b (80:20 ratio)
	assert_bool(results["a"] > results["b"]).override_failure_message(
		"Expected 'a' (%d) > 'b' (%d) over %d trials" % [results["a"], results["b"], trials]
	).is_true()


func test_pick_weighted_zero_weights() -> void:
	var result = _spawner._pick_weighted({"a": 0, "b": 0})
	assert_str(result).is_equal("")


# ── _pick_weighted_from_dict ─────────────────────────────────

func test_pick_weighted_from_dict_empty() -> void:
	var result = _spawner._pick_weighted_from_dict({})
	assert_str(result).is_equal("")


func test_pick_weighted_from_dict_single() -> void:
	var result = _spawner._pick_weighted_from_dict({"only": 100})
	assert_str(result).is_equal("only")


# ── _get_zone_probability ────────────────────────────────────

func test_get_zone_probability_null_config() -> void:
	var prob = _spawner._get_zone_probability(null, 0)
	assert_float(prob).is_equal_approx(0.0, 0.001)


func test_get_zone_probability_with_config() -> void:
	var data: Resource = PLACEMENT_DATA.from_dict({
		"base_probability": 0.2,
		"zone_probabilities": {"1": 2.0}
	})
	assert_float(_spawner._get_zone_probability(data, 0)).is_equal_approx(0.2, 0.001)
	assert_float(_spawner._get_zone_probability(data, 1)).is_equal_approx(0.4, 0.001)


# ── _has_physics_body ────────────────────────────────────────

func test_has_physics_body_static_finds_physics() -> void:
	var body := StaticBody3D.new()
	assert_bool(_spawner._has_physics_body(body)).is_true()
	body.free()


func test_has_physics_body_rigid_finds_physics() -> void:
	var body := RigidBody3D.new()
	assert_bool(_spawner._has_physics_body(body)).is_true()
	body.free()


func test_has_physics_body_node_without_physics() -> void:
	var node := Node3D.new()
	assert_bool(_spawner._has_physics_body(node)).is_false()
	node.free()

func test_scene_object_collision_uses_child_mesh_transform() -> void:
	var prop := Node3D.new()
	prop.name = "TestProp"
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(1.0, 1.0, 1.0)
	mesh.mesh = box_mesh
	mesh.position = Vector3(0.0, 1.25, 0.0)
	prop.add_child(mesh)

	_spawner._ensure_scene_object_collision(prop)

	var body := prop.get_node_or_null("TestPropBody") as StaticBody3D
	assert_object(body).is_not_null()
	if body == null:
		prop.free()
		return
	var col := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	assert_object(col).is_not_null()
	if col == null:
		prop.free()
		return
	assert_float(col.position.y) \
		.override_failure_message("补全碰撞必须包含子 Mesh 的局部位移，避免交互/物理盒悬空或下沉") \
		.is_equal_approx(1.25, 0.001)
	assert_float((col.shape as BoxShape3D).size.y).is_equal_approx(1.0, 0.001)
	prop.free()


# ── spawn_items_for_level (edge cases) ───────────────────────

func test_spawn_items_for_level_empty_grid() -> void:
	var result = _spawner.spawn_items_for_level([], 0, Vector3.ZERO, 3.0, Vector3.ZERO, _spawner)
	assert_array(result).is_empty()


func test_spawn_items_for_level_all_walls() -> void:
	var grid := [[2, 2], [2, 2]]
	var result = _spawner.spawn_items_for_level(grid, 0, Vector3.ZERO, 3.0, Vector3.ZERO, _spawner)
	# No floor cells, so no items
	assert_array(result).is_empty()


# ── Metadata ─────────────────────────────────────────────────

func test_set_tag_meta_on_instance() -> void:
	var node := Node3D.new()
	var data: Resource = PLACEMENT_DATA.from_dict({"tag": "test", "location_preference": 2, "physics_mode": 1})
	_spawner._set_tag_meta(node, "weapon", data, 3)

	assert_str(node.get_meta("item_tag")).is_equal("weapon")
	assert_int(node.get_meta("spawn_zone")).is_equal(3)
	assert_int(node.get_meta("location_preference")).is_equal(2)
	assert_int(node.get_meta("physics_mode")).is_equal(1)
	node.free()


# ── _spawn_items_for_level with zone 3 (volcano, higher probability) ──

func test_spawn_items_for_level_floor_cell_no_crash() -> void:
	# Just check that the spawner doesn't crash on valid grid input
	var grid := [[1, 0], [0, 1]]
	_spawner.register_tag_config(_make_material_config())
	_spawner.register_tag_config(_make_decor_config())
	var result = _spawner.spawn_items_for_level(grid, 0, Vector3.ZERO, 3.0, Vector3.ZERO, _spawner)
	# May return items or not depending on random, but should not crash
	assert_bool(result is Array).is_true()


func test_spawn_items_for_level_resource_cell_spawns_material() -> void:
	var parent := Node3D.new()
	var grid := [[4]]
	var result = _spawner.spawn_items_for_level(grid, 0, Vector3(999, 0, 999), 3.0, Vector3.ZERO, parent)

	assert_array(result).has_size(1)
	assert_str(result[0].get_meta("item_tag")).is_equal(TAGS.MATERIAL)
	assert_bool(result[0].has_meta("material_id")).is_true()
	parent.free()


func test_spawn_items_for_level_caps_materials_slightly_above_enemy_count() -> void:
	var parent := Node3D.new()
	var enemy_marker := Node3D.new()
	enemy_marker.set_meta("topdown_kind", "enemy")
	parent.add_child(enemy_marker)
	var grid := [
		[4, 4, 4, 4],
		[4, 4, 4, 4],
	]

	var result = _spawner.spawn_items_for_level(grid, 0, Vector3(999, 0, 999), 3.0, Vector3.ZERO, parent)

	var material_count := 0
	for item in result:
		if item.has_meta("item_tag") and String(item.get_meta("item_tag")) == TAGS.MATERIAL:
			material_count += 1
	assert_int(material_count).is_equal(6)
	parent.free()


# ── Material placement ───────────────────────────────────────

func test_find_wall_direction_returns_neighbor_wall_vector() -> void:
	var grid := [
		[0, 2, 0],
		[0, 1, 0],
		[0, 0, 0],
	]
	var direction: Vector3 = _spawner._find_wall_direction(grid, 1, 1)
	assert_bool(direction.is_equal_approx(Vector3(0, 0, -1))).is_true()


func test_position_for_near_wall_material_offsets_toward_wall() -> void:
	var pos: Vector3 = _spawner._position_for_material("glowshroom", Vector3.ZERO, 3.0, Vector3.RIGHT)
	assert_float(pos.x).is_equal_approx(1.08, 0.001)
	assert_bool(absf(pos.z) <= 0.24).is_true()


func test_position_for_scatter_material_stays_inside_floor_cell() -> void:
	var pos: Vector3 = _spawner._position_for_material("blackberry", Vector3.ZERO, 3.0, Vector3.RIGHT)
	assert_bool(absf(pos.x) <= 0.6).is_true()
	assert_bool(absf(pos.z) <= 0.6).is_true()


func test_spawn_material_instance_applies_wall_alignment_and_metadata() -> void:
	var parent := Node3D.new()
	var item: Node = _spawner._spawn_material_instance("glowshroom", Vector3(2, 0, 3), parent, 1, Vector3.RIGHT)
	assert_object(item).is_not_null()
	assert_str(item.get_meta("material_id")).is_equal("glowshroom")
	assert_str(item.get_meta("material_location_preference")).is_equal("near_wall")
	assert_bool(item.get_meta("material_align_to_wall")).is_true()
	assert_float((item as Node3D).rotation.y).is_equal_approx(PI * 0.5, 0.001)
	assert_float((item as Node3D).position.y).is_equal_approx(0.3, 0.001)
	parent.free()


# ── Helper ────────────────────────────────────────────────────

func _make_material_config() -> Resource:
	var data: Resource = PLACEMENT_DATA.new()
	data.tag = TAGS.MATERIAL
	data.base_probability = 0.0  # Set to 0 to avoid random spawns in test
	data.item_scene_paths = [
		{"path": "res://scenes/equipment/pickable_item.tscn", "weight": 100}
	]
	data.preload_scenes()
	return data

func _make_decor_config() -> Resource:
	var data: Resource = PLACEMENT_DATA.new()
	data.tag = TAGS.DECOR
	data.base_probability = 0.0
	return data
