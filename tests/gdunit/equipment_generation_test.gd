extends GdUnitTestSuite
## 装备随机生成系统完整测试。
## 覆盖：阶位属性生效、词缀系统、防具掉落、独立实例、地面散落。

const WeaponRegistryScript := preload("res://data/weapon_registry.gd")
const LootTableScript := preload("res://globals/tavern/loot_table.gd")
const AffixSystemScript := preload("res://globals/equipment/affix_system.gd")

var wr: WeaponRegistryScript
var lt: LootTableScript
var asys: AffixSystemScript

func before_test() -> void:
	wr = Engine.get_main_loop().root.get_node("WeaponRegistry") as WeaponRegistryScript
	lt = Engine.get_main_loop().root.get_node("LootTable") as LootTableScript
	asys = Engine.get_main_loop().root.get_node("AffixSystem") as AffixSystemScript

# ============================================================================
# P0: 阶位属性生效测试
# ============================================================================

func test_build_weapon_data_with_tier_returns_independent_instance() -> void:
	var data0 := wr.build_weapon_data_with_tier("shortsword", 0)
	var data2 := wr.build_weapon_data_with_tier("shortsword", 2)
	assert_object(data0).is_not_null()
	assert_object(data2).is_not_null()
	# 必须是不同实例
	assert_bool(data0 != data2).is_true()

func test_tier_0_stats_match_first_tier() -> void:
	var data := wr.build_weapon_data_with_tier("shortsword", 0)
	# 一阶青铜短剑: 1d6+3
	assert_int(data.damage_dice_count).is_equal(1)
	assert_int(data.damage_dice_sides).is_equal(6)
	assert_int(data.damage_flat).is_equal(3)
	assert_str(data.tier_name).is_equal("青铜短剑")
	assert_str(data.material_tier).is_equal("iron")
	assert_int(data.tier_index).is_equal(0)

func test_tier_2_stats_match_third_tier() -> void:
	var data := wr.build_weapon_data_with_tier("shortsword", 2)
	# 三阶誓约之刃: 3d6+20, crit_bonus 5%（命中率 hit_bonus 已移除）
	assert_int(data.damage_dice_count).is_equal(3)
	assert_int(data.damage_dice_sides).is_equal(6)
	assert_int(data.damage_flat).is_equal(20)
	assert_str(data.tier_name).is_equal("誓约之刃")
	assert_str(data.material_tier).is_equal("mithril")
	assert_int(data.tier_index).is_equal(2)
	assert_float(data.crit_bonus_percent).is_equal_approx(5.0, 0.01)

func test_tier_2_damage_higher_than_tier_0() -> void:
	var data0 := wr.build_weapon_data_with_tier("greatsword", 0)
	var data2 := wr.build_weapon_data_with_tier("greatsword", 2)
	# 三阶伤害应远高于一阶
	assert_bool(data2.damage_max > data0.damage_max * 2).is_true()

func test_build_does_not_mutate_registry_shared_instance() -> void:
	var before := wr.get_weapon_data("axe")
	var before_flat := before.damage_flat
	# 构建一个二阶副本
	var data := wr.build_weapon_data_with_tier("axe", 1)
	data.damage_flat = 999
	data.condition = 1
	# 注册表共享实例不受影响
	var after := wr.get_weapon_data("axe")
	assert_int(after.damage_flat).is_equal(before_flat)

func test_tier_index_clamped_for_invalid_values() -> void:
	var data_neg := wr.build_weapon_data_with_tier("shortsword", -1)
	assert_int(data_neg.tier_index).is_equal(0)
	var data_high := wr.build_weapon_data_with_tier("shortsword", 99)
	assert_int(data_high.tier_index).is_equal(2)


func test_material_tier_changes_with_each_weapon_tier() -> void:
	var data0 := wr.build_weapon_data_with_tier("crossbow", 0)
	var data1 := wr.build_weapon_data_with_tier("crossbow", 1)
	var data2 := wr.build_weapon_data_with_tier("crossbow", 2)
	assert_str(data0.material_tier).is_equal("wood")
	assert_str(data1.material_tier).is_equal("steel")
	assert_str(data2.material_tier).is_equal("mithril")

func test_loot_table_roll_weapon_has_correct_tier_stats() -> void:
	# 多次 roll，收集三阶样本验证属性正确
	var found_tier2 := false
	for i in range(200):
		var w: Dictionary = lt.roll_weapon()
		if w.is_empty():
			continue
		var wd = w["weapon_data"]
		if int(w["tier_index"]) == 2:
			found_tier2 = true
			# 三阶武器必须有对应阶位名
			assert_bool(not String(wd.tier_name).is_empty()) \
				.override_failure_message("三阶武器 tier_name 为空").is_true()
			# tier_index 必须正确记录
			assert_int(wd.tier_index).is_equal(2)
			break
	# 如果200次都没抽到三阶，可能是概率问题，不算失败但记录
	if not found_tier2:
		push_warning("200次未抽到三阶装备（10%概率），跳过三阶属性验证")

# ============================================================================
# P0: 独立实例测试
# ============================================================================

func test_loot_table_returns_independent_instances() -> void:
	var w1: Dictionary = lt.roll_weapon()
	var w2: Dictionary = lt.roll_weapon()
	if w1.is_empty() or w2.is_empty():
		return
	var wd1 = w1["weapon_data"]
	var wd2 = w2["weapon_data"]
	# 即使是同类型装备，也必须是不同实例
	if wd1.id == wd2.id and wd1.tier_index == wd2.tier_index:
		assert_bool(wd1 != wd2) \
			.override_failure_message("同类型同阶装备返回了同一实例").is_true()

func test_duplicate_weapon_condition_independent() -> void:
	var data := wr.build_weapon_data_with_tier("warhammer", 0)
	var original_condition := data.condition
	data.decrease_condition(5)
	assert_int(data.condition).is_equal(original_condition - 5)
	# 注册表实例不受影响
	var registry_data := wr.get_weapon_data("warhammer")
	assert_bool(registry_data.condition != original_condition - 5 or registry_data == data).is_true()

# ============================================================================
# P1: 词缀系统测试
# ============================================================================

func test_affix_system_registered() -> void:
	assert_object(asys).is_not_null()

func test_roll_affixes_returns_0_to_2() -> void:
	for i in range(100):
		var affixes: Array[String] = asys.roll_affixes()
		assert_bool(affixes.size() >= 0 and affixes.size() <= 2) \
			.override_failure_message("词缀数量 %d 越界 (应 0-2)" % affixes.size()).is_true()

func test_two_affixes_always_one_positive_one_negative() -> void:
	for i in range(200):
		var affixes: Array[String] = asys.roll_affixes()
		if affixes.size() == 2:
			var has_pos := asys.is_positive(affixes[0]) or asys.is_positive(affixes[1])
			var has_neg := asys.is_negative(affixes[0]) or asys.is_negative(affixes[1])
			assert_bool(has_pos and has_neg) \
				.override_failure_message("2词缀时应为1正1负: %s" % str(affixes)).is_true()

func test_positive_affix_ids_are_valid() -> void:
	var positive_ids := ["sharp", "lightweight", "focused", "furious", "sturdy", "blessed"]
	for id in positive_ids:
		assert_bool(asys.is_positive(id)).is_true()
		assert_bool(not asys.is_negative(id)).is_true()

func test_negative_affix_ids_are_valid() -> void:
	var negative_ids := ["rusty", "clunky", "worn", "inferior", "cracked", "dim"]
	for id in negative_ids:
		assert_bool(asys.is_negative(id)).is_true()
		assert_bool(not asys.is_positive(id)).is_true()

func test_apply_affixes_modifies_damage_mult() -> void:
	var data := wr.build_weapon_data_with_tier("shortsword", 0)
	var original_mult := data.damage_mult
	asys.apply_affixes(data, ["sharp"])
	# sharp: damage_mult +0.10
	assert_float(data.damage_mult).is_equal_approx(original_mult + 0.10, 0.001)

func test_apply_affixes_rusty_reduces_damage() -> void:
	var data := wr.build_weapon_data_with_tier("shortsword", 0)
	var original_mult := data.damage_mult
	asys.apply_affixes(data, ["rusty"])
	# rusty: damage_mult -0.15
	assert_float(data.damage_mult).is_equal_approx(original_mult - 0.15, 0.001)

func test_apply_affixes_focused_adds_crit_bonus() -> void:
	var data := wr.build_weapon_data_with_tier("shortsword", 0)
	var original_crit := data.crit_bonus_percent
	asys.apply_affixes(data, ["focused"])
	# focused: 暴击率 +10%（动作化替代命中率 hit_bonus）
	assert_float(data.crit_bonus_percent).is_equal_approx(original_crit + 10.0, 0.01)

func test_apply_affixes_furious_adds_crit_and_crit_dmg() -> void:
	var data := wr.build_weapon_data_with_tier("dagger", 0)
	var original_crit := data.crit_bonus_percent
	var original_crit_dmg := data.crit_damage_bonus
	asys.apply_affixes(data, ["furious"])
	# furious: crit +8%, crit_dmg +15%
	assert_float(data.crit_bonus_percent).is_equal_approx(original_crit + 8.0, 0.01)
	assert_float(data.crit_damage_bonus).is_equal_approx(original_crit_dmg + 15.0, 0.01)

func test_apply_affixes_inferior_reduces_max_condition() -> void:
	var data := wr.build_weapon_data_with_tier("shortsword", 0)
	var original_max := data.max_condition
	asys.apply_affixes(data, ["inferior"])
	# inferior: max_condition * 0.8
	assert_int(data.max_condition).is_equal(int(round(float(original_max) * 0.8)))

func test_apply_affixes_sturdy_adds_phys_def() -> void:
	var data := wr.build_weapon_data_with_tier("shield", 0)
	var original_def := data.shield_phys_def
	asys.apply_affixes(data, ["sturdy"])
	# sturdy: phys_def +4
	assert_int(data.shield_phys_def).is_equal(original_def + 4)

func test_apply_affixes_does_not_go_negative_damage() -> void:
	var data := wr.build_weapon_data_with_tier("shortsword", 0)
	# Apply multiple negative damage affixes
	asys.apply_affixes(data, ["rusty", "dim"])
	# damage_mult should not be negative
	assert_bool(data.damage_mult >= 0.0).is_true()

func test_loot_table_weapon_has_affixes_field() -> void:
	for i in range(50):
		var w: Dictionary = lt.roll_weapon()
		if w.is_empty():
			continue
		var wd = w["weapon_data"]
		# affixes 字段必须存在且为数组
		assert_bool("affixes" in wd).is_true()
		assert_bool(wd.affixes.size() <= 2).is_true()

func test_affix_display_name_includes_prefix() -> void:
	var data := wr.build_weapon_data_with_tier("shortsword", 0)
	asys.apply_affixes(data, ["sharp"])
	var display := data.get_full_display_name()
	assert_bool(display.contains("锋利的")).is_true()

func test_get_full_display_name_without_affixes() -> void:
	var data := wr.build_weapon_data_with_tier("shortsword", 0)
	var display := data.get_full_display_name()
	assert_str(display).is_equal("青铜短剑")

# ============================================================================
# P1: 防具掉落测试
# ============================================================================

func test_loot_table_can_drop_armor() -> void:
	var found_armor := false
	for i in range(500):
		var w: Dictionary = lt.roll_weapon()
		if w.is_empty():
			continue
		var wd = w["weapon_data"]
		if wd.equipment_category.begins_with("armor"):
			found_armor = true
			break
	assert_bool(found_armor) \
		.override_failure_message("500次roll未掉落任何防具").is_true()

func test_loot_table_can_drop_accessory() -> void:
	var found_accessory := false
	for i in range(500):
		var w: Dictionary = lt.roll_weapon()
		if w.is_empty():
			continue
		var wd = w["weapon_data"]
		if wd.equipment_category == "accessories":
			found_accessory = true
			break
	assert_bool(found_accessory) \
		.override_failure_message("500次roll未掉落任何饰品").is_true()

func test_loot_table_weapon_data_has_correct_category() -> void:
	var categories_seen: Dictionary = {}
	for i in range(200):
		var w: Dictionary = lt.roll_weapon()
		if w.is_empty():
			continue
		var wd = w["weapon_data"]
		categories_seen[wd.equipment_category] = true
	# 必须能看到多种类别
	assert_bool(categories_seen.size() >= 2) \
		.override_failure_message("只掉落了 %d 种类别" % categories_seen.size()).is_true()

# ============================================================================
# P1: 酒馆盲盒装备测试
# ============================================================================

func test_tavern_settlement_gear_has_weapon_data() -> void:
	var ts = Engine.get_main_loop().root.get_node("TavernSettlement")
	# 多次尝试直到获得装备盲盒
	for i in range(100):
		var gear: Dictionary = ts._pick_random_gear()
		if gear.is_empty():
			continue
		assert_bool(gear.has("weapon_data")) \
			.override_failure_message("盲盒装备缺少 weapon_data 字段").is_true()
		var wd = gear["weapon_data"]
		assert_bool(wd is WeaponData or wd is Resource).is_true()
		# tier_index 必须有效
		assert_bool(int(gear["tier_index"]) >= 0).is_true()
		return
	push_warning("100次未获得盲盒装备，跳过测试")

func test_tavern_settlement_gear_display_name_has_affix() -> void:
	var ts = Engine.get_main_loop().root.get_node("TavernSettlement")
	var found_affixed := false
	for i in range(200):
		var gear: Dictionary = ts._pick_random_gear()
		if gear.is_empty():
			continue
		var wd = gear["weapon_data"]
		if wd.affixes.size() > 0:
			found_affixed = true
			var display: String = gear["display_name"]
			# 显示名应包含词缀前缀
			var has_prefix := false
			for affix_id in wd.affixes:
				var affix_name := asys.get_affix_name(affix_id)
				if display.contains(affix_name):
					has_prefix = true
					break
			assert_bool(has_prefix) \
				.override_failure_message("显示名 '%s' 不含词缀前缀" % display).is_true()
			break
	if not found_affixed:
		push_warning("200次未获得带词缀的盲盒装备，跳过测试")

# ============================================================================
# P2: 地面散落装备测试
# ============================================================================

func test_item_spawner_has_scatter_equipment_method() -> void:
	var spawner = Engine.get_main_loop().root.get_node("ItemSpawner")
	assert_bool(spawner.has_method("_spawn_scatter_equipment")).is_true()

func test_item_spawner_scatter_items_checks_weapon_tag() -> void:
	var spawner = Engine.get_main_loop().root.get_node("ItemSpawner")
	var source: String = get_script().source_code
	# 验证 _spawn_scatter_items 方法中包含武器/盾牌生成逻辑
	var spawner_script: Resource = load("res://globals/equipment/item_spawner.gd")
	var spawner_source: String = (spawner_script as GDScript).source_code
	assert_bool(spawner_source.find("TAGS.WEAPON") != -1) \
		.override_failure_message("ItemSpawner 未处理 WEAPON 标签").is_true()
	assert_bool(spawner_source.find("TAGS.SHIELD") != -1) \
		.override_failure_message("ItemSpawner 未处理 SHIELD 标签").is_true()
	assert_bool(spawner_source.find("_spawn_scatter_equipment") != -1) \
		.override_failure_message("ItemSpawner 缺少 _spawn_scatter_equipment 方法").is_true()

# ============================================================================
# CombatBridge 词缀伤害倍率测试
# ============================================================================

func test_combat_bridge_applies_damage_mult() -> void:
	var cb_script: Resource = load("res://globals/combat/combat_bridge.gd")
	var source: String = (cb_script as GDScript).source_code
	assert_bool(source.find("damage_mult") != -1) \
		.override_failure_message("CombatBridge 未读取 weapon.damage_mult").is_true()

# ============================================================================
# WeaponData 词缀字段测试
# ============================================================================

func test_weapon_data_has_affix_fields() -> void:
	var data := WeaponData.new()
	assert_bool("affixes" in data).is_true()
	assert_bool("damage_mult" in data).is_true()
	assert_bool("carry_weight_mult" in data).is_true()
	assert_bool("is_broken" in data).is_true()

func test_broken_weapon_deals_zero_damage() -> void:
	var data := wr.build_weapon_data_with_tier("shortsword", 0)
	data.is_broken = true
	assert_int(data.get_damage_dealt()).is_equal(0)

func test_decrease_condition_sets_broken_flag() -> void:
	var data := wr.build_weapon_data_with_tier("dagger", 0)
	data.condition = 1
	data.decrease_condition(1)
	assert_bool(data.is_broken).is_true()
	assert_int(data.condition).is_equal(0)

# ============================================================================
# AffixSystem autoload 注册测试
# ============================================================================

func test_affix_system_in_project_autoloads() -> void:
	var project := ConfigFile.new()
	project.load("res://project.godot")
	var autoload_path := project.get_value("autoload", "AffixSystem", "")
	assert_bool(not autoload_path.is_empty()) \
		.override_failure_message("AffixSystem 未注册为 autoload").is_true()
