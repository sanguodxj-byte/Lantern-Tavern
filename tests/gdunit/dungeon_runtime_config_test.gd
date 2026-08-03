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
	assert_bool(cfg.decor_config.has("res://scenes/props/dungeon/decor/bones.tscn")).is_true()
	assert_bool(cfg.decor_config.has("res://scenes/props/dungeon/dungeon_barrel.tscn")).is_true()
	assert_bool(cfg.decor_config.has("res://scenes/props/dungeon/dungeon_crate.tscn")).is_true()
	for kind in ["stalagmite_cluster", "sarcophagus", "wall_chain", "fungus_patch"]:
		var path := cfg.dungeon_decor_scene_path_for(kind)
		assert_bool(cfg.decor_config.has(path)).override_failure_message("新增地牢装饰未进入运行时池: %s" % kind).is_true()
		assert_bool(cfg.is_dungeon_scene_path_allowed(path)).is_true()


func test_new_dungeon_decor_have_explicit_placement_profiles() -> void:
	var cfg := DungeonRuntimeConfig.default()
	assert_str(cfg.dungeon_decor_placement_for("stalagmite_cluster")).is_equal("edge")
	assert_str(cfg.dungeon_decor_placement_for("sarcophagus")).is_equal("anchor")
	assert_str(cfg.dungeon_decor_placement_for("wall_chain")).is_equal("wall")
	assert_str(cfg.dungeon_decor_placement_for("fungus_patch")).is_equal("edge")
	assert_str(cfg.dungeon_decor_placement_for_path("res://scenes/props/dungeon/decor/wall_chain.tscn")).is_equal("wall")

func test_batched_decor_scenes_contains_pillar_and_iron_bar() -> void:
	var cfg := DungeonRuntimeConfig.default()
	assert_bool(cfg.batched_decor_scenes.has("res://scenes/props/dungeon/pillar.tscn")).is_true()
	assert_bool(cfg.batched_decor_scenes.has("res://scenes/props/dungeon/decor/iron_bar_grate.tscn")).is_true()
	assert_bool(bool(cfg.batched_decor_scenes["res://scenes/props/dungeon/pillar.tscn"])).is_true()

func test_dungeon_catalog_rejects_tavern_only_scene_objects() -> void:
	var cfg := DungeonRuntimeConfig.default()
	var tavern_only_paths := [
		"res://scenes/props/decor/lit_candles.tscn",
		"res://scenes/props/decor/table.tscn",
		"res://scenes/props/decor/chair.tscn",
		"res://scenes/props/decor/bench.tscn",
		"res://scenes/props/decor/weapon_rack.tscn",
		"res://scenes/props/decor/bucket.tscn",
	]
	for path in tavern_only_paths:
		assert_bool(cfg.decor_config.has(path)).is_false()
		assert_bool(cfg.batched_decor_scenes.has(path)).is_false()
		assert_bool(cfg.is_dungeon_scene_path_allowed(path)).is_false()
	for tavern_container in [
		"res://scenes/props/barrel/barrel.tscn",
		"res://scenes/props/crates/small_crate.tscn",
	]:
		assert_bool(cfg.is_dungeon_scene_path_allowed(tavern_container)).is_false()

func test_json_decor_pool_is_subset_of_dungeon_catalog() -> void:
	var file := FileAccess.open("res://data/item_placement_config.json", FileAccess.READ)
	assert_object(file).is_not_null()
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	assert_bool(parsed is Array).is_true()
	for entry in parsed:
		if String(entry.get("tag", "")) != "decor":
			continue
		for scene_entry in entry.get("item_scene_paths", []):
			var path := String(scene_entry.get("path", ""))
			assert_bool(DungeonRuntimeConfig.is_allowed_dungeon_scene_path(path)) \
				.override_failure_message("JSON 地牢装饰池包含非地牢物体: %s" % path).is_true()

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
	assert_bool(cfg.batched_decor_scenes.has("res://scenes/props/dungeon/pillar.tscn")).is_true()

func test_wfc_visual_debug_uses_the_same_dungeon_catalog() -> void:
	var wfc_src := (load("res://scenes/expedition/wfc_visual_test.gd") as GDScript).source_code
	assert_bool(wfc_src.contains("DungeonRuntimeConfig")).is_true()
	for forbidden in ["table.tscn", "chair.tscn", "bench.tscn", "lit_candles.tscn", "weapon_rack.tscn", "bucket.tscn"]:
		assert_bool(not wfc_src.contains(forbidden)) \
			.override_failure_message("WFC 调试地牢仍硬编码酒馆物体: %s" % forbidden).is_true()
