extends GdUnitTestSuite

## EquipmentPolicy（架构审查 P0-4）—— 装备命令唯一策略真相。
## 覆盖：类别解析、材料/符文拒绝、槽位兼容、双手↔盾互斥、唯一性、自动槽位。

const EP := preload("res://globals/core/equipment_policy.gd")
const LO := preload("res://globals/core/state/equipment_loadout.gd")

func _source() -> Callable:
	return func(item_id: String) -> Dictionary:
		match item_id:
			"shortsword": return {"category": "weapons", "hands": "one_hand", "armor_slot": ""}
			"greatsword": return {"category": "weapons", "hands": "two_hand", "armor_slot": ""}
			"warhammer": return {"category": "weapons", "hands": "two_hand", "armor_slot": ""}
			"shield": return {"category": "shields", "hands": "off_hand", "armor_slot": ""}
			"buckler": return {"category": "shields", "hands": "off_hand", "armor_slot": ""}
			"cloth_armor": return {"category": "armor_light", "hands": "", "armor_slot": "body"}
			"leather_cap": return {"category": "armor_light", "hands": "", "armor_slot": "head"}
			_: return {}

func _loadout() -> LO:
	return LO.new()

func test_material_and_rune_and_unknown_rejected() -> void:
	var lo := _loadout()
	for bad in ["iron_ore", "ember", "goblin_tooth", "unknown_thing"]:
		var res: Dictionary = EP.resolve(bad, "weapon", 0, "", lo, _source())
		assert_bool(res["ok"]) \
			.override_failure_message("%s 不应可装备" % bad).is_false()

func test_weapon_into_weapon_slot_ok() -> void:
	var lo := _loadout()
	var res: Dictionary = EP.resolve("shortsword", "weapon", 0, "", lo, _source())
	assert_bool(res["ok"]).is_true()
	assert_str(res["slot_kind"]).is_equal(EP.SLOT_KIND_WEAPON)
	assert_int(res["slot_index"]).is_equal(0)

func test_weapon_auto_slot_kind_when_empty() -> void:
	var lo := _loadout()
	var res: Dictionary = EP.resolve("shortsword", "", 0, "", lo, _source())
	assert_bool(res["ok"]).is_true()
	assert_str(res["slot_kind"]).is_equal(EP.SLOT_KIND_WEAPON)

func test_weapon_slot_index_out_of_range_rejected() -> void:
	var lo := _loadout()
	assert_bool(EP.resolve("shortsword", "weapon", 4, "", lo, _source())["ok"]).is_false()
	assert_bool(EP.resolve("shortsword", "weapon", -1, "", lo, _source())["ok"]).is_false()

func test_armor_into_armor_slot_ok_uses_item_default_slot() -> void:
	var lo := _loadout()
	var res: Dictionary = EP.resolve("cloth_armor", "armor", -1, "", lo, _source())
	assert_bool(res["ok"]).is_true()
	assert_str(res["slot_kind"]).is_equal(EP.SLOT_KIND_ARMOR)
	assert_str(res["slot_name"]).is_equal("body")

func test_armor_slot_name_override() -> void:
	var lo := _loadout()
	var res: Dictionary = EP.resolve("leather_cap", "armor", -1, "head", lo, _source())
	assert_bool(res["ok"]).is_true()
	assert_str(res["slot_name"]).is_equal("head")
	# 非法护甲槽名拒绝。
	assert_bool(EP.resolve("cloth_armor", "armor", -1, "bogus", lo, _source())["ok"]).is_false()

## P0-2：护甲固有部位校验——头盔不能进 body，胸甲不能进 head。
func test_armor_intrinsic_slot_mismatch_rejected() -> void:
	var lo := _loadout()
	# 头盔（固有 head）→ body：拒绝（污染权威 loadout/属性/存档/外观的入口）。
	assert_bool(EP.resolve("leather_cap", "armor", -1, "body", lo, _source())["ok"]) \
		.override_failure_message("头盔不得装进 body 槽（固有部位 head）").is_false()
	# 胸甲（固有 body）→ head：拒绝。
	assert_bool(EP.resolve("cloth_armor", "armor", -1, "head", lo, _source())["ok"]) \
		.override_failure_message("胸甲不得装进 head 槽（固有部位 body）").is_false()
	# 固有部位自身始终允许。
	assert_bool(EP.resolve("leather_cap", "armor", -1, "head", lo, _source())["ok"]).is_true()
	assert_bool(EP.resolve("cloth_armor", "armor", -1, "body", lo, _source())["ok"]).is_true()

## P0-2：多部位护甲经 armor_slots 数组显式声明允许槽（未来装备），未声明则只允许固有部位。
func test_armor_multi_slot_declared_allowed() -> void:
	var lo := _loadout()
	var multi := func(item_id: String) -> Dictionary:
		match item_id:
			"layered_robe": return {"category": "armor_light", "hands": "", "armor_slot": "body",
				"armor_slots": ["body", "head"]}
			_: return {}
	var ok_body: Dictionary = EP.resolve("layered_robe", "armor", -1, "body", lo, multi)
	assert_bool(ok_body["ok"]).is_true()
	assert_str(ok_body["slot_name"]).is_equal("body")
	var ok_head: Dictionary = EP.resolve("layered_robe", "armor", -1, "head", lo, multi)
	assert_bool(ok_head["ok"]).is_true()
	# 声明数组之外的槽仍拒绝。
	assert_bool(EP.resolve("layered_robe", "armor", -1, "feet", lo, multi)["ok"]).is_false()

func test_armor_into_weapon_slot_rejected_and_vice_versa() -> void:
	var lo := _loadout()
	assert_bool(EP.resolve("cloth_armor", "weapon", 0, "", lo, _source())["ok"]).is_false()
	assert_bool(EP.resolve("shortsword", "armor", -1, "body", lo, _source())["ok"]).is_false()

func test_two_hand_conflicts_with_shield() -> void:
	var lo := _loadout()
	lo.set_weapon_slot(0, "shield")
	assert_bool(EP.resolve("greatsword", "weapon", 1, "", lo, _source())["ok"]) \
		.override_failure_message("双手与盾必须互斥").is_false()
	# 反向：先双手，再盾 → 拒绝。
	var lo2 := _loadout()
	lo2.set_weapon_slot(0, "greatsword")
	assert_bool(EP.resolve("shield", "weapon", 1, "", lo2, _source())["ok"]).is_false()
	# 单手持盾允许（盾 + 单手剑）。
	var lo3 := _loadout()
	lo3.set_weapon_slot(0, "shortsword")
	assert_bool(EP.resolve("buckler", "weapon", 1, "", lo3, _source())["ok"]).is_true()

func test_only_one_two_hand_weapon_allowed() -> void:
	var lo := _loadout()
	lo.set_weapon_slot(0, "greatsword")
	assert_bool(EP.resolve("warhammer", "weapon", 1, "", lo, _source())["ok"]) \
		.override_failure_message("不得同时装备两把双手武器").is_false()
	# 双手 + 单手（备份位）允许。
	var lo2 := _loadout()
	lo2.set_weapon_slot(0, "greatsword")
	assert_bool(EP.resolve("shortsword", "weapon", 1, "", lo2, _source())["ok"]).is_true()

func test_only_one_shield_allowed() -> void:
	var lo := _loadout()
	lo.set_weapon_slot(0, "shield")
	assert_bool(EP.resolve("buckler", "weapon", 1, "", lo, _source())["ok"]) \
		.override_failure_message("不得同时装备两面盾").is_false()

func test_equipping_same_slot_replaces_previous_item() -> void:
	# 目标槽自身不算冲突（替换旧装备是合法操作）。
	var lo := _loadout()
	lo.set_weapon_slot(0, "greatsword")
	var res: Dictionary = EP.resolve("warhammer", "weapon", 0, "", lo, _source())
	assert_bool(res["ok"]).is_true()

func test_unknown_slot_kind_rejected() -> void:
	var lo := _loadout()
	assert_bool(EP.resolve("shortsword", "backpack", 0, "", lo, _source())["ok"]).is_false()

func test_empty_data_source_yields_unknown_rejected() -> void:
	# headless 无注册表：data_source 无效 → 全部按未知物品拒绝（绝不猜测放行）。
	var lo := _loadout()
	var res: Dictionary = EP.resolve("shortsword", "weapon", 0, "", lo, Callable())
	assert_bool(res["ok"]).is_false()
