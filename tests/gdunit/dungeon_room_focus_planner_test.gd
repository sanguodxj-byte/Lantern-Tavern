extends GdUnitTestSuite

const GENERATOR := preload("res://scenes/expedition/dungeon_generator.gd")
const CONFIG := preload("res://scenes/expedition/dungeon_generation_config.gd")
const PLANNER := preload("res://scenes/expedition/dungeon_room_focus_planner.gd")
const RUNTIME_CONFIG := preload("res://scenes/expedition/dungeon_runtime_config.gd")

func test_focus_planner_creates_thematic_landmarks_without_key_cell_overlap() -> void:
	var config := CONFIG.new()
	config.seed = 94021
	var layout: DungeonLayout = GENERATOR.new().generate(config)
	PLANNER.new().plan(layout)

	assert_int(layout.room_focus_specs.size()) \
		.override_failure_message("地牢普通房间缺少主题焦点建筑").is_greater_equal(6)
	var seen_cells := {}
	for spec in layout.room_focus_specs:
		var cell: Vector2i = spec["cell"]
		assert_bool(layout.is_floor_cell(cell)).is_true()
		assert_bool(not seen_cells.has(cell)) \
			.override_failure_message("焦点建筑不能重叠: %s" % cell).is_true()
		seen_cells[cell] = true
		for key_cell in [layout.player_spawn_cell, layout.extraction_cell, layout.boss_cell, layout.stairs_cell, layout.reward_cell]:
			if not layout.is_key_cell_missing(key_cell):
				assert_bool(cell != key_cell) \
					.override_failure_message("焦点建筑不能占用关键交互格: %s" % cell).is_true()

func test_focus_planner_is_deterministic_for_same_seed() -> void:
	var config := CONFIG.new()
	config.seed = 71231
	var layout_a: DungeonLayout = GENERATOR.new().generate(config)
	var layout_b: DungeonLayout = GENERATOR.new().generate(config)
	PLANNER.new().plan(layout_a)
	PLANNER.new().plan(layout_b)
	assert_int(layout_a.room_focus_specs.size()).is_equal(layout_b.room_focus_specs.size())
	for index in range(layout_a.room_focus_specs.size()):
		assert_bool(layout_a.room_focus_specs[index] == layout_b.room_focus_specs[index]) \
			.override_failure_message("同 seed 焦点建筑不一致: index=%d" % index).is_true()

func test_planned_voxel_decor_is_deterministic_and_keeps_safe_cells_clear() -> void:
	var config := CONFIG.new()
	config.seed = 71231
	var layout_a: DungeonLayout = GENERATOR.new().generate(config)
	var layout_b: DungeonLayout = GENERATOR.new().generate(config)
	DungeonHazardPlanner.new().plan(layout_a)
	DungeonHazardPlanner.new().plan(layout_b)
	PLANNER.new().plan(layout_a)
	PLANNER.new().plan(layout_b)
	assert_array(layout_a.decor_specs).is_not_empty()
	assert_bool(layout_a.decor_specs == layout_b.decor_specs).is_true()
	assert_bool(layout_a.terrain_features == layout_b.terrain_features).is_true()
	for spec in layout_a.decor_specs:
		var cell: Vector2i = spec["cell"]
		assert_bool(String(spec["scene_path"]).begins_with("res://scenes/props/")).is_true()
		assert_bool(not layout_a.is_start_room_cell(cell)).is_true()
		for key_cell in [layout_a.player_spawn_cell, layout_a.extraction_cell, layout_a.boss_cell, layout_a.stairs_cell, layout_a.reward_cell]:
			if not layout_a.is_key_cell_missing(key_cell):
				assert_bool(cell != key_cell).is_true()
		for anchor in layout_a.hazard_anchors:
			var hazard_cell: Vector2i = anchor["anchor_cell"]
			assert_bool(maxi(absi(cell.x - hazard_cell.x), absi(cell.y - hazard_cell.y)) > 1).is_true()

func test_focus_planner_never_plans_tavern_scene_objects() -> void:
	var config := CONFIG.new()
	config.seed = 94021
	var layout: DungeonLayout = GENERATOR.new().generate(config)
	PLANNER.new().plan(layout)
	var tavern_only_paths := [
		"res://scenes/props/decor/lit_candles.tscn",
		"res://scenes/props/decor/table.tscn",
		"res://scenes/props/decor/chair.tscn",
		"res://scenes/props/decor/bench.tscn",
		"res://scenes/props/decor/weapon_rack.tscn",
		"res://scenes/props/decor/bucket.tscn",
	]
	for spec in layout.decor_specs:
		var path := String(spec.get("scene_path", ""))
		assert_bool(RUNTIME_CONFIG.is_allowed_dungeon_scene_path(path)).is_true()
		assert_bool(not tavern_only_paths.has(path)) \
			.override_failure_message("地牢计划装饰混入酒馆场景物体: %s" % path).is_true()

func test_ritual_rooms_receive_the_new_voxel_totem() -> void:
	var config := CONFIG.new()
	config.seed = 94021
	var layout: DungeonLayout = GENERATOR.new().generate(config)
	PLANNER.new().plan(layout)
	var ritual_room_indices := {}
	for room_index in range(layout.room_metadata.size()):
		if String(layout.room_metadata[room_index].get("theme", "")) == "ritual":
			ritual_room_indices[room_index] = true
	if ritual_room_indices.is_empty():
		return
	var found_totem := false
	for spec in layout.decor_specs:
		if ritual_room_indices.has(int(spec["room_index"])) and String(spec["decor_kind"]) == "ritual_totem":
			found_totem = true
			assert_str(String(spec["scene_path"])).is_equal("res://scenes/props/dungeon/decor/ritual_totem.tscn")
			assert_bool(bool(spec["blocks_navigation"])).is_true()
	assert_bool(found_totem).override_failure_message("仪式主题房必须生成至少一个仪式图腾身份锚点").is_true()


func test_decor_specs_use_edge_and_wall_placement_contracts() -> void:
	var config := CONFIG.new()
	config.seed = 94021
	var layout: DungeonLayout = GENERATOR.new().generate(config)
	PLANNER.new().plan(layout)
	var placement_counts := {}
	for spec in layout.decor_specs:
		var kind := String(spec["decor_kind"])
		var placement := String(spec.get("placement", RUNTIME_CONFIG.dungeon_decor_placement_for(kind)))
		placement_counts[placement] = int(placement_counts.get(placement, 0)) + 1
		if placement == "wall":
			var cell: Vector2i = spec["cell"]
			var direction: Vector2i = spec.get("wall_direction", Vector2i.ZERO)
			assert_bool(direction != Vector2i.ZERO) \
				.override_failure_message("墙挂装饰缺少墙向: %s" % kind).is_true()
			var neighbor := cell + direction
			assert_bool(int(layout.grid[neighbor.y][neighbor.x]) == 2) \
				.override_failure_message("墙挂装饰没有贴着墙格: %s %s" % [kind, cell]).is_true()
		if placement == "anchor":
			var focus_cell := Vector2i(-1, -1)
			for focus in layout.room_focus_specs:
				if int(focus.get("room_index", -1)) == int(spec["room_index"]):
					focus_cell = focus["cell"]
					break
			var decor_cell: Vector2i = spec["cell"]
			if focus_cell.x >= 0:
				assert_int(absi(focus_cell.x - decor_cell.x) + absi(focus_cell.y - decor_cell.y)) \
					.override_failure_message("重型锚点装饰不应压在房间焦点上: %s" % kind).is_greater_equal(2)
	assert_int(int(placement_counts.get("edge", 0))).is_greater_equal(1)
	assert_int(int(placement_counts.get("wall", 0))).is_greater_equal(1)


func test_ritual_totem_is_not_a_light_source_or_emissive_asset() -> void:
	const TOTEM_SCENE := "res://scenes/props/dungeon/decor/ritual_totem.tscn"
	const TOTEM_MODEL := "res://assets/models/props/props_ritual_totem.glb"
	const TOTEM_GENERATOR := "res://tools/generate_voxel_ritual_totem.py"
	var packed := load(TOTEM_SCENE) as PackedScene
	assert_object(packed).is_not_null()
	var instance := packed.instantiate()
	assert_int(instance.find_children("*", "Light3D", true, false).size()) \
		.override_failure_message("仪式图腾不是光源，场景内禁止 Light3D").is_equal(0)
	var generator_source := FileAccess.get_file_as_string(TOTEM_GENERATOR)
	assert_str(generator_source) \
		.override_failure_message("仪式图腾生成器禁止启用材质 emission") \
		.not_contains("emission=")
	var model_bytes := FileAccess.get_file_as_bytes(TOTEM_MODEL)
	var model_text := model_bytes.get_string_from_utf8()
	assert_str(model_text).not_contains("emissiveFactor")
	assert_str(model_text).not_contains("KHR_materials_emissive_strength")
	instance.free()

func test_focus_planner_keeps_start_room_clear() -> void:
	var config := CONFIG.new()
	config.seed = 271828
	var layout: DungeonLayout = GENERATOR.new().generate(config)
	PLANNER.new().plan(layout)
	for spec in layout.room_focus_specs:
		assert_bool(not layout.is_start_room_cell(spec["cell"])) \
			.override_failure_message("出生房不能生成焦点建筑: %s" % spec["cell"]).is_true()

func test_room_compositions_define_tempo_terrain_and_battle_sectors() -> void:
	var config := CONFIG.new()
	config.seed = 94021
	var layout: DungeonLayout = GENERATOR.new().generate(config)
	DungeonHazardPlanner.new().plan(layout)
	PLANNER.new().plan(layout)

	assert_int(layout.room_composition_specs.size()) \
		.override_failure_message("非出生房必须有房间构成数据").is_greater_equal(6)
	var kinds := {}
	var elevated_cells := 0
	for spec in layout.room_composition_specs:
		var composition_kind := String(spec["composition_kind"])
		kinds[composition_kind] = true
		assert_bool(spec.has("cover_cells")).is_true()
		assert_bool(spec.has("enemy_sectors")).is_true()
		assert_bool((spec["enemy_sectors"] as Array).size() >= 2 or String(spec["composition_kind"]) == "boss").is_true()
		for cell in spec.get("platform_cells", []):
			elevated_cells += 1
			var expected_height := 1.5 if composition_kind == "cliff" else 1.0
			assert_float(layout.floor_height_at(cell)).is_equal(expected_height)
	assert_bool(kinds.has("boss")).is_true()
	assert_bool(kinds.has("ambush")).is_true()
	assert_bool(kinds.has("elevation")).is_true()
	assert_bool(kinds.has("trap")).is_true()
	assert_bool(kinds.has("reward")).is_true()
	assert_int(elevated_cells).is_greater_equal(1)

func test_elevation_composition_has_ramp_bridge_and_closed_boundary() -> void:
	var config := CONFIG.new()
	config.seed = 94021
	var layout: DungeonLayout = GENERATOR.new().generate(config)
	PLANNER.new().plan(layout)
	var found_elevation := false
	for spec in layout.room_composition_specs:
		if String(spec["composition_kind"]) != "elevation":
			continue
		found_elevation = true
		assert_array(spec["platform_cells"]).is_not_empty()
		assert_array(spec["ramp_specs"]).is_not_empty()
		assert_array(spec["bridge_cells"]).is_not_empty()
		assert_array(spec["boundary_edges"]).is_not_empty()
	assert_bool(found_elevation).is_true()


func test_cliff_is_room_scoped_contiguous_and_keeps_connectivity() -> void:
	var config := CONFIG.new()
	config.seed = 94021
	var layout: DungeonLayout = GENERATOR.new().generate(config)
	PLANNER.new().plan(layout)
	var found_cliff := false
	for spec in layout.room_composition_specs:
		if String(spec.get("composition_kind", "")) != "cliff":
			continue
		found_cliff = true
		var room_index := int(spec["room_index"])
		var room: Rect2i = layout.rooms[room_index]
		var cliff_cells: Array = spec.get("cliff_cells", [])
		assert_int(cliff_cells.size()).is_greater_equal(4)
		assert_array(spec.get("ramp_specs", [])).is_not_empty()
		assert_array(spec.get("cliff_edges", [])).is_not_empty()
		for index in range(cliff_cells.size()):
			var cell: Vector2i = cliff_cells[index]
			assert_bool(room.has_point(cell)).is_true()
			assert_bool(layout.is_floor_cell(cell)).is_true()
			assert_float(layout.floor_height_at(cell)).is_equal(1.5)
			assert_bool(not spec.get("door_transition_cells", []).has(cell)).is_true()
			if index > 0:
				var previous: Vector2i = cliff_cells[index - 1]
				assert_int(absi(cell.x - previous.x) + absi(cell.y - previous.y)) \
					.override_failure_message("悬崖格必须连续: %s -> %s" % [previous, cell]).is_equal(1)
		assert_bool(not layout.is_start_room_cell(cliff_cells[0])).is_true()
		assert_bool(PLANNER.new()._cliff_preserves_connectivity(layout, cliff_cells)).is_true()
	assert_bool(found_cliff).override_failure_message("固定种子未生成房间级悬崖").is_true()


func test_cliff_terrain_feature_has_one_room_owner_and_matching_length() -> void:
	var config := CONFIG.new()
	config.seed = 71231
	var layout: DungeonLayout = GENERATOR.new().generate(config)
	PLANNER.new().plan(layout)
	var cliff_features: Array = []
	for feature in layout.terrain_features:
		if String(feature.get("feature_kind", "")) == "cliff":
			cliff_features.append(feature)
	assert_int(cliff_features.size()).is_equal(1)
	var feature: Dictionary = cliff_features[0]
	var owner_index := int(feature["room_index"])
	assert_int(int(feature["length_cells"])).is_greater_equal(4)
	assert_array(feature.get("edges", [])).is_not_empty()
	for cell in feature["cells"]:
		var owners := 0
		for room in layout.rooms:
			if room.has_point(cell):
				owners += 1
		assert_int(owners).is_equal(1)
		assert_bool((layout.rooms[owner_index] as Rect2i).has_point(cell)).is_true()
