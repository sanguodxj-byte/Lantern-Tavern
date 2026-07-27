extends GdUnitTestSuite

const GENERATOR := preload("res://scenes/expedition/dungeon_generator.gd")
const CONFIG := preload("res://scenes/expedition/dungeon_generation_config.gd")
const PLANNER := preload("res://scenes/expedition/dungeon_room_focus_planner.gd")

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

func test_focus_planner_keeps_start_room_clear() -> void:
	var config := CONFIG.new()
	config.seed = 271828
	var layout: DungeonLayout = GENERATOR.new().generate(config)
	PLANNER.new().plan(layout)
	for spec in layout.room_focus_specs:
		assert_bool(not layout.is_start_room_cell(spec["cell"])) \
			.override_failure_message("出生房不能生成焦点建筑: %s" % spec["cell"]).is_true()
