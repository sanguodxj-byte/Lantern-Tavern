extends GdUnitTestSuite
## 地牢物体互动与撤离点测试
## 验证：宝箱 zone 注入 + 撤离点逻辑 + 可拾取物 + 可投掷物

# ---------- 宝箱互动 ----------

func test_chest_script_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/props/chest/chest.gd")).is_true()
	assert_bool(ResourceLoader.exists("res://scenes/props/chest/chest.tscn")).is_true()

func test_chest_has_zone_export() -> void:
	var script: Resource = load("res://scenes/props/chest/chest.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("@export var zone") != -1).is_true()

func test_chest_open_chest_method() -> void:
	var script: Resource = load("res://scenes/props/chest/chest.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("func open_chest") != -1).is_true()
	assert_bool(source.find("func _spawn_loot_physical") != -1).is_true()
	assert_bool(source.find("func _generate_loot_data") != -1).is_true()
	assert_bool(source.find("func close_loot_panel") != -1).is_true()

func test_procedural_dungeon_injects_zone_to_chest() -> void:
	# chest zone 注入已迁入 DungeonSceneBuilder（layout.zone）
	var source: String = (load("res://scenes/expedition/dungeon_scene_builder.gd") as GDScript).source_code
	assert_bool(source.find("layout.zone") != -1) \
		.override_failure_message("DungeonSceneBuilder 未对宝箱注入 zone").is_true()

func test_procedural_dungeon_has_extraction_portal() -> void:
	var builder_src: String = (load("res://scenes/expedition/dungeon_scene_builder.gd") as GDScript).source_code
	assert_bool(builder_src.find("_build_extraction_portal") != -1 or builder_src.find("ExtractionPortal") != -1).is_true()

func test_extraction_triggers_tavern_return() -> void:
	var runtime_src: String = (load("res://scenes/expedition/dungeon_runtime.gd") as GDScript).source_code
	assert_bool(runtime_src.find("on_extraction_requested") != -1).is_true()
	assert_bool(runtime_src.find("extract_to_tavern") != -1).is_true()

func test_extraction_settles_loot() -> void:
	var runtime_src: String = (load("res://scenes/expedition/dungeon_runtime.gd") as GDScript).source_code
	assert_bool(runtime_src.find("_settle_extraction_loot") != -1) \
		.override_failure_message("撤离点未结算携带物品").is_true()

# ---------- 可拾取物体 ----------

func test_pickable_item_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/equipment/pickable_item.gd")).is_true()
	assert_bool(ResourceLoader.exists("res://scenes/equipment/pickable_item.tscn")).is_true()

func test_pickable_item_has_weapon_data_field() -> void:
	var script: Resource = load("res://scenes/equipment/pickable_item.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("weapon_data") != -1).is_true()
	assert_bool(source.find("material_id") != -1).is_true()

func test_pickable_item_highlight_methods() -> void:
	var script: Resource = load("res://scenes/equipment/pickable_item.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("func highlight") != -1).is_true()
	assert_bool(source.find("func unhighlight") != -1).is_true()

# ---------- 可投掷物体 ----------

func test_thrown_item_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/equipment/thrown_item.gd")).is_true()
	assert_bool(ResourceLoader.exists("res://scenes/equipment/thrown_item.tscn")).is_true()

func test_barrel_is_throwable() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/props/barrel/barrel.tscn")).is_true()

func test_enemy_impale_interface() -> void:
	var script: Resource = load("res://scenes/characters/enemies/enemy.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("func impale") != -1).is_true()
	assert_bool(source.find("func try_receive_furniture_impact") != -1).is_true()

# ---------- 怪物生成 ----------

func test_dungeon_spawner_registered() -> void:
	assert_object(Engine.get_main_loop().root.get_node_or_null("DungeonSpawner")).is_not_null()

func test_procedural_dungeon_calls_spawner() -> void:
	# 敌人生成已迁入 DungeonRuntime；仍应走 DungeonSpawner layout 接口
	var runtime_src: String = (load("res://scenes/expedition/dungeon_runtime.gd") as GDScript).source_code
	assert_bool(runtime_src.find("spawn_enemies_from_layout") != -1).is_true()
	assert_bool(runtime_src.find("Service.dungeon_spawner()") != -1 or runtime_src.find("DungeonSpawner") != -1).is_true()
	var pd_src: String = (load("res://scenes/expedition/procedural_dungeon.gd") as GDScript).source_code
	assert_bool(pd_src.find("_runtime.start()") != -1 or pd_src.find("DungeonRuntime") != -1).is_true()

func test_retained_enemy_prefabs_exist() -> void:
	for enemy_id in ["goblin", "dragon", "rock_golem", "orc_raider", "skeleton"]:
		var path := "res://scenes/characters/enemies/%s.tscn" % enemy_id
		assert_bool(ResourceLoader.exists(path)) \
			.override_failure_message("保留的敌人场景不存在: %s" % path).is_true()
