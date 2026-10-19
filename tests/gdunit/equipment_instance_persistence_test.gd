extends GdUnitTestSuite

# 装备实例持久化测试（架构审查 0804 P0-2）：
# 背包 equipment_instances 与已装备 weapon/armor_instances 必须进入存档并在读档后完整恢复
# （词缀/耐久/阶位/诅咒等运行时字段，不能回退为注册表模板）。

const ExpeditionInventory = preload("res://globals/core/state/expedition_inventory.gd")
const EquipmentLoadout = preload("res://globals/core/state/equipment_loadout.gd")

# ---------- WeaponData.to_save_dict / load_from_save_dict ----------

func test_weapon_data_save_dict_roundtrip_preserves_instance_fields() -> void:
	var w := WeaponData.new()
	w.id = "shortsword"
	w.condition = 345
	w.max_condition = 800
	w.tier_index = 2
	w.tier_name = "钢剑"
	w.material_tier = "steel"
	w.rarity = "RARE"
	w.quality_tier = "WOR"
	w.is_identified = false
	w.is_cursed = true
	w.is_blessed = false
	w.affixes = ["sharp", "rusty"]
	w.damage_mult = 1.08
	w.carry_weight_mult = 0.9
	w.carry_weight_bonus = 5
	w.is_broken = false
	w.lifesteal_percent = 0.5
	w.self_hp_drain_per_hit = 1
	w.low_hp_execute_mult = 0.05

	var restored := WeaponData.new()
	restored.load_from_save_dict(w.to_save_dict())

	assert_str(restored.id).is_equal("shortsword")
	assert_int(restored.condition).is_equal(345)
	assert_int(restored.max_condition).is_equal(800)
	assert_int(restored.tier_index).is_equal(2)
	assert_str(restored.tier_name).is_equal("钢剑")
	assert_str(restored.material_tier).is_equal("steel")
	assert_str(restored.rarity).is_equal("RARE")
	assert_str(restored.quality_tier).is_equal("WOR")
	assert_bool(restored.is_identified).is_false()
	assert_bool(restored.is_cursed).is_true()
	assert_bool(restored.is_blessed).is_false()
	assert_array(restored.affixes).contains("sharp")
	assert_array(restored.affixes).contains("rusty")
	assert_float(restored.damage_mult).is_equal_approx(1.08, 0.001)
	assert_float(restored.carry_weight_mult).is_equal_approx(0.9, 0.001)
	assert_int(restored.carry_weight_bonus).is_equal(5)
	assert_bool(restored.is_broken).is_false()
	assert_float(restored.lifesteal_percent).is_equal_approx(0.5, 0.001)
	assert_int(restored.self_hp_drain_per_hit).is_equal(1)
	assert_float(restored.low_hp_execute_mult).is_equal_approx(0.05, 0.001)


func test_weapon_data_save_dict_is_json_serializable() -> void:
	var w := WeaponData.new()
	w.id = "axe"
	var json_text := JSON.stringify(w.to_save_dict())
	var json := JSON.new()
	assert_int(json.parse(json_text)).is_equal(OK)


func test_weapon_data_save_dict_does_not_include_glb_mesh() -> void:
	var w := WeaponData.new()
	w.id = "shortsword"
	var d := w.to_save_dict()
	assert_bool(d.has("glb_mesh")).is_false()


func test_weapon_data_load_from_empty_dict_keeps_defaults() -> void:
	var w := WeaponData.new()
	w.load_from_save_dict({})
	assert_int(w.condition).is_equal(w.max_condition)
	assert_bool(w.is_cursed).is_false()
	assert_bool(w.is_broken).is_false()


# ---------- ExpeditionInventory.to_dict / from_dict ----------

func test_expedition_inventory_instances_roundtrip() -> void:
	var inv = ExpeditionInventory.new()
	var rolled := WeaponData.new()
	rolled.id = "shortsword"
	rolled.affixes = ["sharp"]
	rolled.tier_index = 2
	rolled.condition = 345
	rolled.material_tier = "steel"
	rolled.is_cursed = true
	assert_bool(inv.add_equipment_instance(rolled)).is_true()
	assert_bool(inv.add_material("rat_tail", 3)).is_true()
	assert_bool(inv.add_rune("fire_rune", 2)).is_true()
	inv.space_limit = 40

	var restored = ExpeditionInventory.new()
	restored.from_dict(inv.to_dict())

	assert_int(int(restored.equipment.get("shortsword", 0))).is_equal(1)
	assert_int(int(restored.materials.get("rat_tail", 0))).is_equal(3)
	assert_int(int(restored.runes.get("fire_rune", 0))).is_equal(2)
	assert_int(restored.space_limit).is_equal(40)
	var inst: WeaponData = restored.get_equipment_instance("shortsword")
	assert_object(inst).is_not_null()
	assert_array(inst.affixes).contains("sharp")
	assert_int(inst.tier_index).is_equal(2)
	assert_int(inst.condition).is_equal(345)
	assert_str(inst.material_tier).is_equal("steel")
	assert_bool(inst.is_cursed).is_true()


func test_expedition_inventory_two_instances_same_id_both_restored() -> void:
	var inv = ExpeditionInventory.new()
	var a := WeaponData.new()
	a.id = "shortsword"
	a.affixes = ["sharp"]
	a.condition = 500
	var b := WeaponData.new()
	b.id = "shortsword"
	b.affixes = ["rusty"]
	b.condition = 100
	assert_bool(inv.add_equipment_instance(a)).is_true()
	assert_bool(inv.add_equipment_instance(b)).is_true()

	var restored = ExpeditionInventory.new()
	restored.from_dict(inv.to_dict())

	assert_int(int(restored.equipment.get("shortsword", 0))).is_equal(2)
	assert_int((restored.equipment_instances["shortsword"] as Array).size()).is_equal(2)
	var first: WeaponData = restored.remove_equipment_instance("shortsword")
	var second: WeaponData = restored.remove_equipment_instance("shortsword")
	assert_object(first).is_not_null()
	assert_object(second).is_not_null()
	assert_int(first.condition + second.condition).is_equal(600)


func test_expedition_inventory_from_legacy_dict_without_instances() -> void:
	var inv = ExpeditionInventory.new()
	inv.from_dict({
		"materials": {"rat_tail": 1},
		"equipment": {"shortsword": 1},
		"space_limit": 30,
	})
	assert_int(int(inv.materials.get("rat_tail", 0))).is_equal(1)
	assert_int(int(inv.equipment.get("shortsword", 0))).is_equal(1)
	assert_bool(inv.equipment_instances.is_empty()).is_true()
	# 旧存档无实例数据时，取出实例返回 null（调用方回退注册表模板，不丢物品）。
	assert_object(inv.get_equipment_instance("shortsword")).is_null()


# ---------- EquipmentLoadout.to_dict / from_dict ----------

func test_equipment_loadout_instances_roundtrip() -> void:
	var loadout = EquipmentLoadout.new()
	loadout.weapon_slots = ["shortsword", "axe", "", ""] as Array[String]
	loadout.armor_slots = {"head": "", "body": "leather_armor", "hands": "", "feet": ""}
	var sw := WeaponData.new()
	sw.id = "shortsword"
	sw.condition = 123
	sw.affixes = ["sharp"]
	loadout.weapon_instances[0] = sw.to_save_dict()
	var armor := WeaponData.new()
	armor.id = "leather_armor"
	armor.condition = 456
	armor.affixes = ["sturdy"]
	loadout.armor_instances["body"] = armor.to_save_dict()

	var restored = EquipmentLoadout.new()
	restored.from_dict(loadout.to_dict())

	assert_str(String(restored.weapon_slots[0])).is_equal("shortsword")
	assert_str(String(restored.armor_slots["body"])).is_equal("leather_armor")
	var w_inst := restored.get_weapon_instance(0)
	assert_int(int(w_inst.get("condition", 0))).is_equal(123)
	assert_array(w_inst.get("affixes", [])).contains("sharp")
	var a_inst := restored.get_armor_instance("body")
	assert_int(int(a_inst.get("condition", 0))).is_equal(456)
	assert_array(a_inst.get("affixes", [])).contains("sturdy")


func test_equipment_loadout_legacy_dict_keeps_empty_instances() -> void:
	var loadout = EquipmentLoadout.new()
	loadout.from_dict({
		"weapon_slots": ["shortsword", "", "", ""],
		"armor_slots": {"head": "", "body": "", "hands": "", "feet": ""},
		"active_weapon_slot": 0,
	})
	assert_bool(loadout.get_weapon_instance(0).is_empty()).is_true()
	assert_bool(loadout.get_armor_instance("body").is_empty()).is_true()
