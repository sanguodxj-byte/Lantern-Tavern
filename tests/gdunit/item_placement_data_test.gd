extends GdUnitTestSuite

# Tests for ItemPlacementData Resource class

const PLACEMENT_DATA := preload("res://data/item_placement_data.gd")

# ── from_dict ────────────────────────────────────────────────

func test_from_dict_full_config() -> void:
	var data: Resource = PLACEMENT_DATA.from_dict({
		"tag": "test_tag",
		"base_probability": 0.15,
		"zone_probabilities": {"0": 1.0, "1": 0.5},
		"location_preference": 1,
		"physics_mode": 1,
		"spawn_min_dist_from_player": 5.0,
		"max_per_room": 3,
		"item_scene_paths": [
			{"path": "res://scenes/props/barrel/barrel.tscn", "weight": 50}
		]
	})

	assert_str(data.tag).is_equal("test_tag")
	assert_float(data.base_probability).is_equal(0.15)
	assert_float(data.get_effective_probability(0)).is_equal(0.15)
	assert_float(data.get_effective_probability(1)).is_equal(0.075)
	assert_int(data.location_preference).is_equal(1)
	assert_int(data.physics_mode).is_equal(1)
	assert_float(data.spawn_min_dist_from_player).is_equal(5.0)
	assert_int(data.max_per_room).is_equal(3)
	assert_int(data.item_scene_paths.size()).is_equal(1)


func test_from_dict_empty_dict() -> void:
	var data: Resource = PLACEMENT_DATA.from_dict({})

	assert_str(data.tag).is_equal("")
	assert_float(data.base_probability).is_equal_approx(0.05, 0.001)
	assert_int(data.location_preference).is_equal(0)
	assert_int(data.physics_mode).is_equal(0)
	assert_float(data.spawn_min_dist_from_player).is_equal(3.0)
	assert_int(data.max_per_room).is_equal(5)


# ── get_effective_probability ────────────────────────────────

func test_get_effective_probability_no_zone_override() -> void:
	var data: Resource = PLACEMENT_DATA.from_dict({
		"base_probability": 0.1
	})
	assert_float(data.get_effective_probability(0)).is_equal_approx(0.1, 0.001)
	assert_float(data.get_effective_probability(99)).is_equal_approx(0.1, 0.001)


func test_get_effective_probability_with_zone_mult() -> void:
	var data: Resource = PLACEMENT_DATA.from_dict({
		"base_probability": 0.1,
		"zone_probabilities": {"0": 2.0, "1": 0.5}
	})
	assert_float(data.get_effective_probability(0)).is_equal_approx(0.2, 0.001)
	assert_float(data.get_effective_probability(1)).is_equal_approx(0.05, 0.001)
	# Unconfigured zone uses multiplier 1.0
	assert_float(data.get_effective_probability(2)).is_equal_approx(0.1, 0.001)


# ── display names ────────────────────────────────────────────

func test_location_name() -> void:
	var data: Resource = PLACEMENT_DATA.from_dict({"location_preference": 0})
	assert_str(data.location_name()).is_equal("地面中心")

	data.location_preference = 3
	assert_str(data.location_name()).is_equal("散布")

	# Unknown value fallback
	data.location_preference = 99
	assert_str(data.location_name()).is_equal("未知")


func test_physics_mode_name() -> void:
	var data: Resource = PLACEMENT_DATA.from_dict({"physics_mode": 0})
	assert_str(data.physics_mode_name()).is_equal("静态")

	data.physics_mode = 1
	assert_str(data.physics_mode_name()).is_equal("刚体")


# ── pick_scene / preload_scenes ──────────────────────────────

func test_pick_scene_no_scenes_returns_null() -> void:
	var data: Resource = PLACEMENT_DATA.new()
	var scene: PackedScene = data.pick_scene()
	assert_bool(scene == null).is_true()


func test_pick_scene_single_scene() -> void:
	var data: Resource = PLACEMENT_DATA.from_dict({
		"item_scene_paths": [
			{"path": "res://scenes/props/barrel/barrel.tscn", "weight": 100}
		]
	})
	var scene: PackedScene = data.pick_scene()
	assert_object(scene).is_not_null()
	assert_object(scene).is_instanceof(PackedScene)


func test_pick_scene_weighted_distribution() -> void:
	var data: Resource = PLACEMENT_DATA.from_dict({
		"item_scene_paths": [
			{"path": "res://scenes/props/barrel/barrel.tscn", "weight": 90},
			{"path": "res://scenes/props/crates/small_crate.tscn", "weight": 10}
		]
	})
	# Run multiple picks to verify no crash
	for i in range(20):
		var scene: PackedScene = data.pick_scene()
		assert_object(scene).is_not_null()


# ── Edge Cases ───────────────────────────────────────────────

func test_from_dict_negative_probability() -> void:
	var data: Resource = PLACEMENT_DATA.from_dict({"base_probability": -0.1})
	# Should still store the value (validation happens at usage site)
	assert_float(data.base_probability).is_equal(-0.1)


func test_pick_scene_invalid_path() -> void:
	var data: Resource = PLACEMENT_DATA.from_dict({
		"item_scene_paths": [
			{"path": "res://nonexistent/scene.tscn", "weight": 100}
		]
	})
	var scene: PackedScene = data.pick_scene()
	assert_bool(scene == null).is_true()


func test_pick_scene_empty_path_skipped() -> void:
	var data: Resource = PLACEMENT_DATA.from_dict({
		"item_scene_paths": [
			{"path": "", "weight": 100}
		]
	})
	var scene: PackedScene = data.pick_scene()
	assert_bool(scene == null).is_true()
