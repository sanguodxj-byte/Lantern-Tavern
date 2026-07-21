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
	assert_bool(gs.has_method("add_carried_equipment")).is_true()
	assert_bool(gs.has_method("remove_carried_equipment")).is_true()
	assert_bool(gs.has_method("get_carried_equipment_dict")).is_true()
	assert_bool(gs.has_method("get_carried_space_used")).is_true()
	assert_bool(gs.has_method("get_carried_space_free")).is_true()
	assert_bool(gs.has_method("can_add_carried_space")).is_true()
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
	gs.carried_equipment.clear()
	gs.add_carried_weapon()
	gs.add_carried_weapon("sword")
	assert_int(gs.get_carried_weapons()).is_equal(2)
	assert_int(int(gs.get_carried_equipment_dict().get("sword", 0))).is_equal(1)

func test_add_carried_shield_increments() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node("GameState")
	gs.carried_shields = 0
	gs.carried_equipment.clear()
	gs.add_carried_shield("shield")
	assert_int(gs.get_carried_shields()).is_equal(1)
	assert_int(int(gs.get_carried_equipment_dict().get("shield", 0))).is_equal(1)

func test_remove_carried_equipment_decrements_and_erases() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node("GameState")
	gs.carried_equipment.clear()
	gs.add_carried_equipment("sword", 2)
	assert_bool(gs.remove_carried_equipment("sword", 1)).is_true()
	assert_int(int(gs.get_carried_equipment_dict().get("sword", 0))).is_equal(1)
	assert_bool(gs.remove_carried_equipment("sword", 1)).is_true()
	assert_bool(gs.get_carried_equipment_dict().has("sword")).is_false()

func test_materials_runes_and_equipment_share_carried_space() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node("GameState")
	var old_limit: int = gs.carried_space_limit
	var old_materials: Dictionary = gs.carried_materials.duplicate()
	var old_runes: Dictionary = gs.carried_runes.duplicate()
	var old_equipment: Dictionary = gs.carried_equipment.duplicate()
	gs.carried_space_limit = 4
	gs.carried_materials.clear()
	gs.carried_runes.clear()
	gs.carried_equipment.clear()
	assert_bool(gs.add_carried_material("test_mat", 2)).is_true()
	assert_bool(gs.add_carried_rune("ember", 1)).is_true()
	assert_bool(gs.add_carried_equipment("sword", 1)).is_true()
	assert_int(gs.get_carried_space_used()).is_equal(4)
	assert_int(gs.get_carried_space_free()).is_equal(0)
	assert_bool(gs.add_carried_material("overflow", 1)).is_false()
	assert_bool(gs.add_carried_equipment("axe", 1)).is_false()
	gs.carried_space_limit = old_limit
	gs.carried_materials = old_materials
	gs.carried_runes = old_runes
	gs.carried_equipment = old_equipment

func test_register_level_preserves_shared_character_backpack() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node("GameState")
	gs.carried_materials.clear()
	gs.carried_equipment.clear()
	gs.carried_weapons = 0
	gs.add_carried_material("test_mat", 5)
	gs.add_carried_weapon("sword")
	var mock_level: Node3D = Node3D.new()
	gs.register_level(mock_level)
	assert_int(gs.get_carried_materials()).is_equal(5)
	assert_int(gs.get_carried_weapons()).is_equal(1)
	assert_int(int(gs.get_carried_equipment_dict().get("sword", 0))).is_equal(1)
	mock_level.free()

func test_player_state_picking_up_records_carried() -> void:
	var script: Resource = load("res://scenes/characters/player/state/player_state_picking_up.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("GameState.add_carried_weapon") != -1).is_true()
	assert_bool(source.find("GameState.add_carried_shield") != -1).is_true()
	assert_bool(source.find("GameState.add_carried_material") != -1).is_true()
	assert_bool(source.find("TavernManager.add_material") == -1).is_true()

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
