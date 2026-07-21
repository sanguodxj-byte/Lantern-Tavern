extends GdUnitTestSuite

# 阶段 E：DungeonRuntimeConfig 契约测试

func before() -> void:
	load("res://scenes/expedition/dungeon_runtime_config.gd")
	load("res://scenes/expedition/dungeon_scene_builder.gd")
	load("res://scenes/expedition/procedural_dungeon.gd")

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

func test_builder_and_procedural_use_runtime_config_source() -> void:
	# decor/materials 配置已迁到 DungeonRuntimeConfig；builder 使用 default()，procedural 持 _runtime_cfg
	var cfg := DungeonRuntimeConfig.default()
	var builder_src := (load("res://scenes/expedition/dungeon_scene_builder.gd") as GDScript).source_code
	var pd_src := (load("res://scenes/expedition/procedural_dungeon.gd") as GDScript).source_code
	assert_bool(builder_src.contains("DungeonRuntimeConfig")).is_true()
	assert_bool(pd_src.contains("DungeonRuntimeConfig") and pd_src.contains("_runtime_cfg")).is_true()
	assert_bool(cfg.materials_config.has("blackberry")).is_true()
	assert_bool(cfg.batched_decor_scenes.has("res://scenes/props/structures/pillar.tscn")).is_true()
