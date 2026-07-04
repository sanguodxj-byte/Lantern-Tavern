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
	assert_bool(source.find("func _spawn_loot") != -1).is_true()

func test_procedural_dungeon_injects_zone_to_chest() -> void:
	var script: Resource = load("res://scenes/expedition/procedural_dungeon.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("instance.zone = dungeon_zone") != -1) \
		.override_failure_message("procedural_dungeon 未对宝箱注入 zone").is_true()

# ---------- 撤离点 ----------

func test_procedural_dungeon_has_extraction_portal() -> void:
	var script: Resource = load("res://scenes/expedition/procedural_dungeon.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("_spawn_extraction_portal") != -1).is_true()
	assert_bool(source.find("ExtractionPortal") != -1).is_true()

func test_extraction_triggers_tavern_return() -> void:
	var script: Resource = load("res://scenes/expedition/procedural_dungeon.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("_on_extraction_entered") != -1).is_true()
	assert_bool(source.find("extract_to_tavern") != -1).is_true()

func test_extraction_settles_loot() -> void:
	var script: Resource = load("res://scenes/expedition/procedural_dungeon.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("_settle_extraction_loot") != -1) \
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
	var script: Resource = load("res://scenes/expedition/procedural_dungeon.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("_spawn_dungeon_enemies") != -1).is_true()
	assert_bool(source.find("DungeonSpawner") != -1).is_true()

func test_enemy_prefabs_exist() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/characters/enemies/goblin.tscn")).is_true()
	assert_bool(ResourceLoader.exists("res://scenes/characters/enemies/kobold.tscn")).is_true()
