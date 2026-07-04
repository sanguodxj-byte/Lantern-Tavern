extends GdUnitTestSuite
## 撤离携带物品精确统计测试
## 验证：GameState 携带记录 + player_state_picking_up 记录 + _settle_extraction_loot 读取 + TavernManager.record_expedition_loot

func test_game_state_has_carried_fields() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node_or_null("GameState")
	assert_object(gs).is_not_null()
	assert_bool(gs.has_method("add_carried_material")).is_true()
	assert_bool(gs.has_method("add_carried_weapon")).is_true()
	assert_bool(gs.has_method("add_carried_shield")).is_true()
	assert_bool(gs.has_method("get_carried_materials")).is_true()
	assert_bool(gs.has_method("get_carried_materials_dict")).is_true()
	assert_bool(gs.has_method("get_carried_weapons")).is_true()
	assert_bool(gs.has_method("get_carried_shields")).is_true()

func test_add_carried_material_accumulates() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node("GameState")
	gs.carried_materials.clear()
	gs.add_carried_material("goblin_nail", 2)
	gs.add_carried_material("goblin_nail", 1)
	gs.add_carried_material("bone_shard", 3)
	assert_int(gs.get_carried_materials()).is_equal(6)
	var dict: Dictionary = gs.get_carried_materials_dict()
	assert_int(int(dict.goblin_nail)).is_equal(3)
	assert_int(int(dict.bone_shard)).is_equal(3)

func test_add_carried_weapon_increments() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node("GameState")
	gs.carried_weapons = 0
	gs.add_carried_weapon()
	gs.add_carried_weapon()
	assert_int(gs.get_carried_weapons()).is_equal(2)

func test_add_carried_shield_increments() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node("GameState")
	gs.carried_shields = 0
	gs.add_carried_shield()
	assert_int(gs.get_carried_shields()).is_equal(1)

func test_register_level_resets_carried() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node("GameState")
	gs.add_carried_material("test_mat", 5)
	gs.add_carried_weapon()
	var mock_level: Node3D = Node3D.new()
	gs.register_level(mock_level)
	assert_int(gs.get_carried_materials()).is_equal(0)
	assert_int(gs.get_carried_weapons()).is_equal(0)
	mock_level.queue_free()

func test_player_state_picking_up_records_carried() -> void:
	var script: Resource = load("res://scenes/characters/player/state/player_state_picking_up.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("GameState.add_carried_weapon") != -1).is_true()
	assert_bool(source.find("GameState.add_carried_shield") != -1).is_true()
	assert_bool(source.find("GameState.add_carried_material") != -1).is_true()

func test_settle_extraction_loot_reads_game_state() -> void:
	var script: Resource = load("res://scenes/expedition/procedural_dungeon.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("GameState.get_carried_materials") != -1).is_true()
	assert_bool(source.find("GameState.get_carried_weapons") != -1).is_true()
	assert_bool(source.find("GameState.get_carried_shields") != -1).is_true()

func test_tavern_manager_has_record_expedition_loot() -> void:
	var tm: Node = Engine.get_main_loop().root.get_node_or_null("TavernManager")
	assert_object(tm).is_not_null()
	assert_bool(tm.has_method("record_expedition_loot")).is_true()

func test_tavern_manager_add_material_accumulates() -> void:
	var tm: Node = Engine.get_main_loop().root.get_node("TavernManager")
	tm.inventory.clear()
	tm.add_material("goblin_nail", 2)
	tm.add_material("goblin_nail", 1)
	assert_int(int(tm.inventory.get("goblin_nail", 0))).is_equal(3)
	tm.inventory.clear()

func test_settle_extraction_loot_calls_record_expedition_loot() -> void:
	var script: Resource = load("res://scenes/expedition/procedural_dungeon.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("record_expedition_loot") != -1).is_true()
