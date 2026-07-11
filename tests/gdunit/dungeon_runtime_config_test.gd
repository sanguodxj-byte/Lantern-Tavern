extends GdUnitTestSuite

# 阶段 E 步3：DungeonRuntimeConfig 呑约测试

func before() -> void:
	load("res://scenes/expedition/dungeon_runtime_config.gd")

func test_default_config_has_materials_and_decor() -> void:
	var cfg := DungeonRuntimeConfig.default()
	assert_bool(cfg.materials_config.has("blackberry")).is_true()
	assert_bool(cfg.materials_config.has("poison_berry")).is_true()
	assert_int(int(cfg.materials_config["blackberry"])).is_equal(15)
	assert_bool(cfg.decor_config.has("res://scenes/props/decor/bones.tscn")).is_true()
	assert_bool(cfg.decor_config.has("res://scenes/props/barrel/barrel.tscn")).is_true()

func test_batched_decor_scenes_contains_pillar_and_iron_bar() -> void:
	var cfg := DungeonRuntimeConfig.default()
	assert_bool(cfg.batched_decor_scenes.has("res://scenes/props/structures/pillar.tscn")).is_true()
	assert_bool(cfg.batched_decor_scenes.has("res://scenes/props/decor/iron_bar_grate.tscn")).is_true()
	assert_bool(bool(cfg.batched_decor_scenes["res://scenes/props/structures/pillar.tscn"])).is_true()

func test_fields_are_mutable() -> void:
	var cfg := DungeonRuntimeConfig.default()
	cfg.materials_config["custom_herb"] = 99
	assert_int(int(cfg.materials_config["custom_herb"])).is_equal(99)

func test_procedural_top_consts_match_default_config() -> void:
	# procedural 顶仍持旧 const（迁移期暂保，下回合删改读 cfg.*）
	var src := (load("res://scenes/expedition/procedural_dungeon.gd") as GDScript).source_code
	assert_bool(src.contains('"blackberry": 15')).is_true()
	assert_bool(src.contains('"res://scenes/props/decor/bones.tscn": 20')).is_true()
	assert_bool(src.contains('"res://scenes/props/structures/pillar.tscn": true')).is_true()
