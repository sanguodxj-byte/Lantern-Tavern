extends GdUnitTestSuite

const QUALITY := preload("res://scenes/expedition/dungeon_layout_quality.gd")
const GENERATOR := preload("res://scenes/expedition/dungeon_generator.gd")
const CONFIG := preload("res://scenes/expedition/dungeon_generation_config.gd")

func test_quality_report_accepts_default_generated_layout() -> void:
	for test_seed in [94021, 3401, 71231, 91811, 271828]:
		var config := CONFIG.new()
		config.seed = test_seed
		var layout: DungeonLayout = GENERATOR.new().generate(config)
		var report := QUALITY.evaluate(layout)
		assert_bool(bool(report["valid"])) \
			.override_failure_message("生成质量门禁未通过: seed=%d report=%s" % [test_seed, report]).is_true()
		assert_float(float(report["walkable_ratio"])).is_greater_equal(QUALITY.MIN_WALKABLE_RATIO)
		assert_float(float(report["reachable_ratio"])).is_greater_equal(QUALITY.MIN_REACHABLE_RATIO)

func test_quality_report_exposes_topology_metrics() -> void:
	var config := CONFIG.new()
	config.seed = 94021
	var layout: DungeonLayout = GENERATOR.new().generate(config)
	var report := QUALITY.evaluate(layout)
	for key in ["walkable_count", "walkable_ratio", "reachable_ratio", "main_path_cells", "dead_end_count", "junction_count", "occupied_bbox_ratio", "checks"]:
		assert_bool(report.has(key)).override_failure_message("质量报告缺少指标: %s" % key).is_true()
	assert_bool(report["occupied_bbox"] is Rect2i).is_true()

func test_quality_report_rejects_disconnected_layout() -> void:
	var layout := DungeonLayout.new()
	layout.width = 7
	layout.height = 3
	layout.grid = [[2, 1, 1, 2, 1, 1, 2], [2, 1, 1, 2, 1, 1, 2], [2, 2, 2, 2, 2, 2, 2]]
	layout.heights = [[3.0, 3.0, 3.0, 3.0, 3.0, 3.0, 3.0], [3.0, 3.0, 3.0, 3.0, 3.0, 3.0, 3.0], [3.0, 3.0, 3.0, 3.0, 3.0, 3.0, 3.0]]
	layout.player_spawn_cell = Vector2i(1, 0)
	layout.boss_cell = Vector2i(4, 0)
	var report := QUALITY.evaluate(layout)
	assert_bool(bool(report["valid"])).is_false()
	assert_float(float(report["reachable_ratio"])).is_less(QUALITY.MIN_REACHABLE_RATIO)
