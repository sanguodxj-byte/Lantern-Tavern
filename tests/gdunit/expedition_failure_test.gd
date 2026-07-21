extends GdUnitTestSuite

class MockPlayer:
	extends Node
	var equipment: EquipmentComponent

var _old_inventory: Dictionary
var _old_runes_inventory: Dictionary
var _old_carried_materials: Dictionary
var _old_carried_runes: Dictionary
var _old_carried_equipment: Dictionary
var _old_carried_weapons: int
var _old_carried_shields: int

func before() -> void:
	var tm: Node = Engine.get_main_loop().root.get_node("TavernManager")
	var gs: Node = Engine.get_main_loop().root.get_node("GameState")
	_old_inventory = tm.inventory.duplicate()
	_old_runes_inventory = tm.runes_inventory.duplicate() if "runes_inventory" in tm else {}
	_old_carried_materials = gs.carried_materials.duplicate()
	_old_carried_runes = gs.carried_runes.duplicate() if "carried_runes" in gs else {}
	_old_carried_equipment = gs.carried_equipment.duplicate()
	_old_carried_weapons = gs.carried_weapons
	_old_carried_shields = gs.carried_shields

func after() -> void:
	var tm: Node = Engine.get_main_loop().root.get_node("TavernManager")
	var gs: Node = Engine.get_main_loop().root.get_node("GameState")
	tm.inventory = _old_inventory
	if "runes_inventory" in tm:
		tm.runes_inventory = _old_runes_inventory
	gs.carried_materials = _old_carried_materials
	if "carried_runes" in gs:
		gs.carried_runes = _old_carried_runes
	gs.carried_equipment = _old_carried_equipment
	gs.carried_weapons = _old_carried_weapons
	gs.carried_shields = _old_carried_shields

func test_expedition_failure_loses_backpack_materials_and_clears_carried_stats() -> void:
	var tm: Node = Engine.get_main_loop().root.get_node("TavernManager")
	var gs: Node = Engine.get_main_loop().root.get_node("GameState")
	tm.inventory = {"goblin_nail": 5, "bone_shard": 1, "stored_only": 7}
	tm.runes_inventory = {"ember": 2, "stored_rune": 1}
	gs.carried_materials = {"goblin_nail": 2, "bone_shard": 2}
	gs.carried_runes = {"ember": 1}
	gs.carried_equipment = {"sword": 1}
	gs.carried_weapons = 3
	gs.carried_shields = 1

	var summary: Dictionary = gs.handle_expedition_failure()

	assert_int(int(tm.inventory.get("goblin_nail", 0))).is_equal(5)
	assert_int(int(tm.inventory.get("bone_shard", 0))).is_equal(1)
	assert_int(int(tm.inventory.get("stored_only", 0))).is_equal(7)
	assert_int(int(tm.runes_inventory.get("ember", 0))).is_equal(2)
	assert_int(int(tm.runes_inventory.get("stored_rune", 0))).is_equal(1)
	assert_bool(gs.carried_materials.is_empty()).is_true()
	assert_bool(gs.carried_runes.is_empty()).is_true()
	assert_bool(gs.carried_equipment.is_empty()).is_true()
	assert_int(gs.carried_weapons).is_equal(0)
	assert_int(gs.carried_shields).is_equal(0)
	assert_int(int(summary["lost_weapons"])).is_equal(3)
	assert_int(int(summary["lost_shields"])).is_equal(1)
	assert_int(int(summary["lost_runes"]["ember"])).is_equal(1)

func test_expedition_failure_randomly_damages_one_equipped_item_without_removing_it() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node("GameState")
	var player: MockPlayer = auto_free(MockPlayer.new())
	var eq := EquipmentComponent.new()
	player.add_child(eq)
	player.equipment = eq
	eq.weapon_placeholder = Node3D.new()
	eq.shield_placeholder = Node3D.new()
	eq.add_child(eq.weapon_placeholder)
	eq.add_child(eq.shield_placeholder)
	var sword := _make_weapon("Sword")
	var axe := _make_weapon("Axe")
	var shield := _make_shield("Shield")
	eq.weapon_slots = [sword, axe, null, null]
	eq.active_weapon_slot = 0
	eq.weapon_data = sword
	eq.shield_data = shield
	eq.shield_placeholder.add_child(Node3D.new())

	var damaged: Dictionary = gs.damage_random_equipped_item(player)

	var damaged_count := 0
	for item in [sword, axe, shield]:
		if item.condition == 0:
			damaged_count += 1
	assert_int(damaged_count).is_equal(1)
	assert_bool(damaged.has("kind")).is_true()
	assert_object(eq.weapon_slots[0]).is_not_null()
	assert_object(eq.weapon_slots[1]).is_not_null()
	assert_object(eq.shield_data).is_not_null()

func test_expedition_failure_can_damage_equipped_armor() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node("GameState")
	var player: MockPlayer = auto_free(MockPlayer.new())
	var eq := EquipmentComponent.new()
	player.add_child(eq)
	player.equipment = eq
	var armor := _make_armor("Leather")
	eq.configure_armor_slot("body", armor)

	var damaged: Dictionary = gs.damage_random_equipped_item(player)

	assert_str(damaged.get("kind", "")).is_equal("armor")
	assert_str(damaged.get("slot", "")).is_equal("body")
	assert_int(eq.get_armor_slot_data("body").condition).is_equal(0)


func test_expedition_failure_treats_hand_shield_as_hand_equipment() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node("GameState")
	var player: MockPlayer = auto_free(MockPlayer.new())
	var eq := EquipmentComponent.new()
	player.add_child(eq)
	player.equipment = eq
	eq.weapon_slots = [_make_shield_weapon("Buckler"), null, null, null]
	eq.active_weapon_slot = 0
	eq.weapon_data = eq.weapon_slots[0]

	var damaged: Dictionary = gs.damage_random_equipped_item(player)

	assert_str(damaged.get("kind", "")).is_equal("hand")
	assert_int(int(damaged.get("slot", -1))).is_equal(0)
	assert_int(eq.weapon_slots[0].condition).is_equal(0)


func test_player_dying_state_uses_failure_settlement_instead_of_dropping_equipment() -> void:
	var script := load("res://scenes/characters/player/state/player_state_dying.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("GameState.handle_expedition_failure(player)")).is_true()
	assert_bool(source.contains("drop_weapon()")).is_false()
	assert_bool(source.contains("drop_shield()")).is_false()

func test_player_dying_state_sends_to_tavern_not_restart_dungeon() -> void:
	var script := load("res://scenes/characters/player/state/player_state_dying.gd") as GDScript
	var source := script.source_code
	# 死亡后应遣送酒馆而非重开地牢（设计文档 §1.2 强制遣送酒馆）
	assert_bool(source.contains("extract_to_tavern")).is_true()
	# extract_to_tavern 应为主路径，level_restarted 仅作为 TavernManager 不可用时的兜底
	var extract_pos := source.find("extract_to_tavern")
	var restart_pos := source.find("GameEvents.level_restarted.emit()")
	assert_bool(extract_pos != -1).is_true()
	# 如果 level_restarted 存在，它必须在 extract_to_tavern 之后（fallback 分支）
	if restart_pos != -1:
		assert_bool(restart_pos > extract_pos) \
			.override_failure_message("level_restarted 应仅在 extract_to_tavern 之后的 fallback 分支中").is_true()

func _make_weapon(label: String) -> WeaponData:
	var data := WeaponData.new()
	data.name = label
	data.item_tag = "weapon"
	data.equipment_category = "weapons"
	data.condition = 10
	data.max_condition = 10
	data.damage_min = 1
	data.damage_max = 3
	data.reach = 2.0
	return data

func _make_shield(label: String) -> ShieldData:
	var data := ShieldData.new()
	data.name = label
	data.condition = 10
	data.max_condition = 10
	return data

func _make_shield_weapon(label: String) -> WeaponData:
	var data := _make_weapon(label)
	data.item_tag = "shield"
	data.weapon_class = "shield"
	data.equipment_category = "shields"
	return data

func _make_armor(label: String) -> WeaponData:
	var data := WeaponData.new()
	data.name = label
	data.item_tag = "armor_light"
	data.equipment_category = "armor_light"
	data.armor_phys_def = 2
	data.condition = 10
	data.max_condition = 10
	return data
