extends GdUnitTestSuite

## 验证酒馆→地牢的装备传递流程：
## 1. 在酒馆 Player A 上配置装备
## 2. save_equipment_from_player 保存到 GameState
## 3. 创建地牢 Player B
## 4. apply_equipment_to_player 应用到 Player B
## 5. 验证 Player B 上的装备正确

const PLAYER_SCENE := preload("res://scenes/characters/player/player.tscn")

var _old_weapon_slot_ids: Array[String]
var _old_armor_slot_ids: Dictionary
var _old_active_weapon_slot: int
var _old_current_player

func before_test() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node("GameState")
	_old_weapon_slot_ids = gs.weapon_slot_ids.duplicate()
	_old_armor_slot_ids = gs.armor_slot_ids.duplicate()
	_old_active_weapon_slot = gs.active_weapon_slot
	_old_current_player = gs.current_player if is_instance_valid(gs.current_player) else null
	var empty_slots: Array[String] = ["", "", "", ""]
	gs.weapon_slot_ids = empty_slots
	gs.armor_slot_ids = {"head": "", "body": "", "hands": "", "feet": ""}
	gs.active_weapon_slot = 0

func after_test() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node("GameState")
	gs.weapon_slot_ids = _old_weapon_slot_ids
	gs.armor_slot_ids = _old_armor_slot_ids
	gs.active_weapon_slot = _old_active_weapon_slot
	gs.current_player = _old_current_player if is_instance_valid(_old_current_player) else null

func _create_real_player() -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	add_child(player)
	return player

func _first_weapon_id() -> String:
	for entry in WeaponRegistry.get_gear_list_entries_by_category("weapons"):
		var wid: String = entry.get("id", "")
		if wid != "":
			return wid
	return ""

func _first_armor_id() -> String:
	for category in ["armor_light", "armor_heavy"]:
		for raw_id in WeaponRegistry.get_by_category().get(category, []):
			var aid := String(raw_id)
			if aid != "":
				return aid
	return ""

func test_save_and_apply_weapon_slot() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node("GameState")
	var weapon_id := _first_weapon_id()
	assert_bool(weapon_id != "").is_true()
	
	# 1. 在 Player A 上配置武器到槽位0
	var player_a := _create_real_player()
	var weapon_data := WeaponRegistry.get_weapon_data(weapon_id)
	assert_object(weapon_data).is_not_null()
	var ok := player_a.equipment.configure_weapon_slot(0, weapon_data, true)
	assert_bool(ok).is_true()
	assert_str(player_a.equipment.get_weapon_slot_data(0).id).is_equal(weapon_id)
	
	# 2. 保存到 GameState
	gs.save_equipment_from_player(player_a)
	assert_str(gs.weapon_slot_ids[0]).is_equal(weapon_id)
	assert_int(gs.active_weapon_slot).is_equal(0)
	
	# 3. 创建 Player B
	var player_b := _create_real_player()
	
	# 4. 应用到 Player B
	gs.apply_equipment_to_player(player_b)
	
	# 5. 验证 Player B 上的装备
	var slot_data := player_b.equipment.get_weapon_slot_data(0)
	assert_object(slot_data).is_not_null()
	assert_str(slot_data.id).is_equal(weapon_id)
	
	player_a.queue_free()
	player_b.queue_free()

func test_save_and_apply_armor_slot() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node("GameState")
	var armor_id := _first_armor_id()
	assert_bool(armor_id != "").is_true()
	
	# 1. 在 Player A 上配置护甲
	var player_a := _create_real_player()
	var armor_data := WeaponRegistry.get_weapon_data(armor_id)
	assert_object(armor_data).is_not_null()
	var armor_slot := armor_data.armor_slot if armor_data.armor_slot != "" else "body"
	var ok := player_a.equipment.configure_armor_slot(armor_slot, armor_data)
	assert_bool(ok).is_true()
	assert_str(player_a.equipment.get_armor_slot_data(armor_slot).id).is_equal(armor_id)
	
	# 2. 保存到 GameState
	gs.save_equipment_from_player(player_a)
	assert_str(gs.armor_slot_ids[armor_slot]).is_equal(armor_id)
	
	# 3. 创建 Player B
	var player_b := _create_real_player()
	
	# 4. 应用到 Player B
	gs.apply_equipment_to_player(player_b)
	
	# 5. 验证 Player B 上的装备
	var slot_data := player_b.equipment.get_armor_slot_data(armor_slot)
	assert_object(slot_data).is_not_null()
	assert_str(slot_data.id).is_equal(armor_id)
	
	player_a.queue_free()
	player_b.queue_free()

func test_register_player_applies_saved_loadout() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node("GameState")
	var weapon_id := _first_weapon_id()
	assert_bool(weapon_id != "").is_true()
	
	# 1. 在 Player A 上配置武器并保存
	var player_a := _create_real_player()
	player_a.equipment.configure_weapon_slot(1, WeaponRegistry.get_weapon_data(weapon_id), true)
	gs.save_equipment_from_player(player_a)
	assert_str(gs.weapon_slot_ids[1]).is_equal(weapon_id)
	assert_int(gs.active_weapon_slot).is_equal(1)
	
	# 2. 创建 Player B 并注册（应自动应用保存的装备）
	var player_b := _create_real_player()
	gs.register_player(player_b)
	
	# 3. 验证 Player B 上的装备
	var slot_data := player_b.equipment.get_weapon_slot_data(1)
	assert_object(slot_data).is_not_null()
	assert_str(slot_data.id).is_equal(weapon_id)
	
	player_a.queue_free()
	player_b.queue_free()

func test_register_player_does_not_overwrite_saved_loadout() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node("GameState")
	var weapon_id := _first_weapon_id()
	assert_bool(weapon_id != "").is_true()
	
	# 1. 在 Player A 上配置武器并保存
	var player_a := _create_real_player()
	player_a.equipment.configure_weapon_slot(0, WeaponRegistry.get_weapon_data(weapon_id), true)
	gs.save_equipment_from_player(player_a)
	assert_str(gs.weapon_slot_ids[0]).is_equal(weapon_id)
	
	# 2. 创建 Player B（模拟场景重加载后的新 Player，无装备）
	#    并注册到 GameState
	var player_b := _create_real_player()
	gs.register_player(player_b)
	
	# 3. 验证 GameState 中保存的装备未被空 Player B 覆盖
	assert_str(gs.weapon_slot_ids[0]).is_equal(weapon_id)
	
	# 4. 验证 Player B 获得了保存的装备（通过 register_player 自动应用）
	var slot_data := player_b.equipment.get_weapon_slot_data(0)
	assert_object(slot_data).is_not_null()
	assert_str(slot_data.id).is_equal(weapon_id)
	
	player_a.queue_free()
	player_b.queue_free()

func test_next_day_scenario_preserves_equipment() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node("GameState")
	var weapon_id := _first_weapon_id()
	assert_bool(weapon_id != "").is_true()
	
	# 模拟“下一天”流程：
	# 1. Player A 在酒馆配置装备并保存
	var player_a := _create_real_player()
	player_a.equipment.configure_weapon_slot(1, WeaponRegistry.get_weapon_data(weapon_id), true)
	gs.save_equipment_from_player(player_a)
	assert_str(gs.weapon_slot_ids[1]).is_equal(weapon_id)
	assert_int(gs.active_weapon_slot).is_equal(1)
	
	# 2. 场景重加载：旧 Player A 被释放，新 Player B 生成
	player_a.queue_free()
	var player_b := _create_real_player()
	
	# 3. 新 Player B 注册到 GameState（模拟 _spawn_player 中的调用）
	gs.register_player(player_b)
	
	# 4. 验证装备已正确传递到 Player B
	var slot_data := player_b.equipment.get_weapon_slot_data(1)
	assert_object(slot_data).is_not_null() \
		.override_failure_message("下一天后装备丢失：槽位 1 的武器数据为 null")
	assert_str(slot_data.id).is_equal(weapon_id)
	assert_int(player_b.equipment.active_weapon_slot).is_equal(1)
	
	# 5. 验证 GameState 中的数据仍然完好
	assert_str(gs.weapon_slot_ids[1]).is_equal(weapon_id)
	
	player_b.queue_free()

func test_register_player_with_no_saved_data_keeps_empty() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node("GameState")
	
	# 确保 weapon_slot_ids 全空
	for i in range(gs.weapon_slot_ids.size()):
		gs.weapon_slot_ids[i] = ""
	
	# 创建 Player 并注册
	var player := _create_real_player()
	gs.register_player(player)
	
	# 验证 GameState 仍然为空（register_player 不再自动保存）
	for i in range(gs.weapon_slot_ids.size()):
		assert_str(gs.weapon_slot_ids[i]).is_empty()
	
	player.queue_free()

func test_apply_equipment_activates_correct_weapon_slot() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node("GameState")
	var weapon_id := _first_weapon_id()
	assert_bool(weapon_id != "").is_true()
	
	# 1. 在 Player A 上配置武器到槽位2并激活
	var player_a := _create_real_player()
	player_a.equipment.configure_weapon_slot(2, WeaponRegistry.get_weapon_data(weapon_id), true)
	gs.save_equipment_from_player(player_a)
	assert_str(gs.weapon_slot_ids[2]).is_equal(weapon_id)
	assert_int(gs.active_weapon_slot).is_equal(2)
	
	# 2. 创建 Player B 并应用
	var player_b := _create_real_player()
	gs.apply_equipment_to_player(player_b)
	
	# 3. 验证 Player B 的激活槽位和武器数据
	assert_int(player_b.equipment.active_weapon_slot).is_equal(2)
	assert_str(player_b.equipment.weapon_data.id).is_equal(weapon_id)
	assert_bool(player_b.equipment.has_weapon()).is_true()
	
	player_a.queue_free()
	player_b.queue_free()

func test_apply_equipment_preserves_all_four_weapon_slots() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node("GameState")
	
	# 获取所有可用武器ID
	var weapon_ids: Array[String] = []
	for entry in WeaponRegistry.get_gear_list_entries_by_category("weapons"):
		var wid: String = entry.get("id", "")
		if wid != "":
			weapon_ids.append(wid)
		if weapon_ids.size() >= 4:
			break
	assert_int(weapon_ids.size()).is_greater_equal(1)
	
	# 1. 在 Player A 上配置所有可用武器到不同槽位
	var player_a := _create_real_player()
	for i in range(weapon_ids.size()):
		player_a.equipment.configure_weapon_slot(i, WeaponRegistry.get_weapon_data(weapon_ids[i]), i == 0)
	gs.save_equipment_from_player(player_a)
	
	# 2. 创建 Player B 并应用
	var player_b := _create_real_player()
	gs.apply_equipment_to_player(player_b)
	
	# 3. 验证所有槽位
	for i in range(weapon_ids.size()):
		var slot_data := player_b.equipment.get_weapon_slot_data(i)
		assert_object(slot_data).is_not_null() \
			.override_failure_message("槽位 %d 的武器数据为 null（期望 %s）" % [i, weapon_ids[i]])
		assert_str(slot_data.id).is_equal(weapon_ids[i])
	
	player_a.queue_free()
	player_b.queue_free()


# ============================================================================
# 回归测试：旧版 .tres WeaponData（无 id）的持久化
# 酒馆内手放的 PickableShortSword 使用 shortsword.tres（无 id 字段），
# 拾取后若直接按 data.id 保存会得到空串，导致下一天 / 出发返回后装备丢失。
# 修复方案：save_equipment_from_player 对无 id 的装备按 glb_mesh 反查注册表。
# ============================================================================

func test_save_legacy_tres_weapon_persists_via_glb_lookup() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node("GameState")
	# 旧版 .tres 没有 id（复现 bug 前提）
	var legacy_data := load("res://data/weapons/shortsword.tres") as WeaponData
	assert_object(legacy_data).is_not_null()
	assert_str(legacy_data.id).is_empty()

	var player_a := _create_real_player()
	assert_bool(player_a.equipment.equip_weapon(legacy_data)).is_true()

	# 保存：应按 glb 反查注册表，得到可持久化的 "shortsword"（而非空串）
	gs.save_equipment_from_player(player_a)
	assert_str(gs.weapon_slot_ids[0]).is_equal("shortsword") \
		.override_failure_message("无 id 的旧 .tres 武器必须通过 glb 反查持久化，否则下一天会丢失")

	# 场景重载：新 Player 应用保存的装备
	var player_b := _create_real_player()
	gs.apply_equipment_to_player(player_b)
	var slot_data := player_b.equipment.get_weapon_slot_data(0)
	assert_object(slot_data).is_not_null()
	assert_str(slot_data.id).is_equal("shortsword")

	player_a.queue_free()
	player_b.queue_free()


func test_next_day_preserves_legacy_tres_weapon() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node("GameState")
	var legacy_data := load("res://data/weapons/shortsword.tres") as WeaponData
	assert_str(legacy_data.id).is_empty()

	# 1. Player A 在酒馆拾取旧 .tres 武器并保存
	var player_a := _create_real_player()
	player_a.equipment.equip_weapon(legacy_data)
	gs.save_equipment_from_player(player_a)
	assert_str(gs.weapon_slot_ids[0]).is_equal("shortsword")

	# 2. 场景重载：旧 Player A 释放，新 Player B 生成
	player_a.queue_free()
	var player_b := _create_real_player()  # _ready → register_player 自动应用保存的装备

	# 3. 验证装备已传递到 Player B（不会因空 id 丢失）
	var slot_data := player_b.equipment.get_weapon_slot_data(0)
	assert_object(slot_data).is_not_null() \
		.override_failure_message("下一天后旧 .tres 武器丢失：槽位 0 为 null")
	assert_str(slot_data.id).is_equal("shortsword")
	assert_int(player_b.equipment.active_weapon_slot).is_equal(0)

	player_b.queue_free()