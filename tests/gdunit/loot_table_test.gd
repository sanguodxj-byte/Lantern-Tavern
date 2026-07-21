extends GdUnitTestSuite
## 宝箱掉落表 (LootTable) 测试。
## 验证武器掉落（含 tier 阶位）、材料掉落（区域权重 + 跨区稀有池）、
## chest.gd 对接 LootTable、procedural_dungeon 注入 zone。

const LT := preload("res://globals/tavern/loot_table.gd")
var lt: Node
var bd: Node

func before_test() -> void:
	lt = Engine.get_main_loop().root.get_node("LootTable")
	bd = Engine.get_main_loop().root.get_node("BrewingData")

# ---------- 武器掉落 ----------

func test_roll_weapon_returns_valid_structure() -> void:
	var w: Dictionary = lt.roll_weapon()
	assert_bool(not w.is_empty()).is_true()
	assert_bool(w.has("id")).is_true()
	assert_bool(w.has("tier_index")).is_true()
	assert_bool(w.has("tier_name")).is_true()
	assert_bool(w.has("weapon_data")).is_true()

func test_roll_weapon_id_from_weapon_registry() -> void:
	var wr = Engine.get_main_loop().root.get_node("WeaponRegistry")
	var all_ids: Array[String] = wr.get_all_ids()
	for i in range(20):
		var w: Dictionary = lt.roll_weapon()
		if w.is_empty():
			continue
		assert_bool(all_ids.has(w["id"])) \
			.override_failure_message("掉落了非法武器 id: %s" % w["id"]) \
			.is_true()


func test_roll_weapon_can_drop_all_equipment_categories() -> void:
	# 回归测试：roll_weapon 应能从所有装备类别抽取（武器/盾牌/防具/饰品）
	var wr = Engine.get_main_loop().root.get_node("WeaponRegistry")
	var all_ids: Array[String] = wr.get_all_ids()
	for i in range(200):
		var w: Dictionary = lt.roll_weapon()
		if w.is_empty():
			continue
		assert_bool(all_ids.has(w["id"])) \
			.override_failure_message("roll_weapon 抽到了非法装备 id: %s" % w["id"]) \
			.is_true()


func test_roll_weapon_includes_armor_and_accessories() -> void:
	# 验证 roll_weapon 确实会掉落防具和饰品（不再是仅武器/盾牌）
	var wr = Engine.get_main_loop().root.get_node("WeaponRegistry")
	var categories: Dictionary = wr.get_by_category()
	var armor_ids: Array[String] = []
	for cat in ["armor_light", "armor_heavy", "accessories"]:
		if categories.has(cat):
			armor_ids.append_array(categories[cat])
	if armor_ids.is_empty():
		return  # 无防具注册则跳过
	var found_armor := false
	for i in range(500):
		var w: Dictionary = lt.roll_weapon()
		if w.is_empty():
			continue
		if armor_ids.has(w["id"]):
			found_armor = true
			break
	assert_bool(found_armor) \
		.override_failure_message("500次roll未掉落任何防具/饰品").is_true()

func test_roll_weapon_tier_index_in_valid_range() -> void:
	for i in range(50):
		var w: Dictionary = lt.roll_weapon()
		if w.is_empty():
			continue
		var idx: int = w["tier_index"]
		assert_bool(idx >= 0 and idx <= 2) \
			.override_failure_message("tier_index %d 越界 (应 0-2)" % idx) \
			.is_true()

func test_tier_weights_distribution_approximate() -> void:
	# 1000 次抽样验证 tier 分布大致符合 60/30/10
	seed(12345)
	var counts: Array = [0, 0, 0]
	var total: int = 0
	for i in range(1000):
		var idx: int = lt._pick_tier_index(3)
		if idx <= 2:
			counts[idx] += 1
			total += 1
	if total == 0:
		return
	var p0: float = float(counts[0]) / total
	var p1: float = float(counts[1]) / total
	var p2: float = float(counts[2]) / total
	# 容差 ±10%
	assert_bool(p0 > 0.5 and p0 < 0.7) \
		.override_failure_message("一阶占比 %.2f 偏离 0.6" % p0).is_true()
	assert_bool(p1 > 0.2 and p1 < 0.4) \
		.override_failure_message("二阶占比 %.2f 偏离 0.3" % p1).is_true()
	assert_bool(p2 > 0.05 and p2 < 0.15) \
		.override_failure_message("三阶占比 %.2f 偏离 0.1" % p2).is_true()

# ---------- 材料掉落 ----------

func test_roll_materials_count_in_range() -> void:
	for i in range(50):
		var mats: Array = lt.roll_materials(BrewingData.Zone.FOREST)
		assert_bool(mats.size() >= LT.MATERIAL_DROP_MIN and mats.size() <= LT.MATERIAL_DROP_MAX) \
			.override_failure_message("材料数 %d 越界 (应 %d-%d)" % [mats.size(), LT.MATERIAL_DROP_MIN, LT.MATERIAL_DROP_MAX]) \
			.is_true()

func test_roll_materials_ids_are_valid() -> void:
	for i in range(50):
		var mats: Array = lt.roll_materials(BrewingData.Zone.VOLCANO)
		for m in mats:
			var mat_id: String = m["material_id"]
			assert_bool(BrewingData.MATERIALS_DB.has(mat_id)) \
				.override_failure_message("掉落了非法材料 id: %s" % mat_id) \
				.is_true()

func test_roll_materials_no_old_fictional_ids() -> void:
	# 反向断言：不掉落旧虚构材料
	var old_ids: Array = ["wild_glowcap", "frost_berry", "fire_bloom", "cave_lichen", "honeycomb", "sweet_grass", "bitter_root", "mountain_barley"]
	for i in range(100):
		var mats: Array = lt.roll_materials(BrewingData.Zone.FOREST)
		for m in mats:
			assert_bool(not old_ids.has(m["material_id"])) \
				.override_failure_message("仍掉落旧虚构材料: %s" % m["material_id"]) \
				.is_true()

func test_zone_material_weights_all_valid() -> void:
	# 验证 ZONE_MATERIAL_WEIGHTS 中所有材料 id 合法
	for zone_key in LT.ZONE_MATERIAL_WEIGHTS:
		var weights: Dictionary = LT.ZONE_MATERIAL_WEIGHTS[zone_key]
		for mat_id in weights:
			assert_bool(BrewingData.MATERIALS_DB.has(mat_id)) \
				.override_failure_message("区域 %d 权重池含非法材料: %s" % [zone_key, mat_id]) \
				.is_true()

func test_rare_cross_zone_materials_all_valid() -> void:
	for mat_id in LT.RARE_CROSS_ZONE_MATERIALS:
		assert_bool(BrewingData.MATERIALS_DB.has(mat_id)) \
			.override_failure_message("稀有池含非法材料: %s" % mat_id) \
			.is_true()

func test_material_entry_has_name() -> void:
	var mats: Array = lt.roll_materials(BrewingData.Zone.CAVES)
	for m in mats:
		assert_bool(m.has("name") and m["name"] is String and m["name"].length() > 0).is_true()

# ---------- 完整掉落包 ----------

func test_generate_loot_returns_weapon_and_materials() -> void:
	var drop = lt.generate_loot(BrewingData.Zone.GRAVEYARD)
	assert_object(drop).is_not_null()
	assert_bool(not drop.weapon.is_empty()).is_true()
	assert_bool(drop.materials.size() >= LT.MATERIAL_DROP_MIN).is_true()
	assert_bool(drop.runes is Array).is_true()

func test_roll_rune_returns_valid_rune_entry() -> void:
	var rune: Dictionary = lt.roll_rune("boss")
	assert_bool(not rune.is_empty()).is_true()
	assert_bool(rune.has("id")).is_true()
	assert_bool(preload("res://globals/combat/rune_data.gd").has_rune(String(rune["id"]))).is_true()

func test_generate_loot_materials_match_zone_mostly() -> void:
	# 85% 概率从当前区域池抽，验证墓园区掉落墓园专属材料居多
	var graveyard_pool: Array = LT.ZONE_MATERIAL_WEIGHTS[BrewingData.Zone.GRAVEYARD].keys()
	var graveyard_hits: int = 0
	var total: int = 0
	for i in range(100):
		var drop = lt.generate_loot(BrewingData.Zone.GRAVEYARD)
		for m in drop.materials:
			total += 1
			if graveyard_pool.has(m["material_id"]):
				graveyard_hits += 1
	# 至少 60% 应来自墓园池（留余量给稀有池）
	assert_bool(float(graveyard_hits) / total > 0.6) \
		.override_failure_message("墓园区掉落墓园专属材料占比过低: %.2f" % (float(graveyard_hits) / total)) \
		.is_true()

# ---------- chest.gd 对接 ----------

func test_chest_script_uses_loot_table() -> void:
	# 确认 chest.gd 已改为调用 LootTable 而非硬编码池
	var script: GDScript = load("res://scenes/props/chest/chest.gd") as GDScript
	assert_object(script).is_not_null()
	var source: String = script.source_code
	assert_bool(source.find("LootTable") != -1) \
		.override_failure_message("chest.gd 未接入 LootTable").is_true()
	assert_bool(source.find("generate_loot") != -1) \
		.override_failure_message("chest.gd 未调用 generate_loot").is_true()
	assert_bool(source.find("\"runes\"") != -1) \
		.override_failure_message("chest.gd 未把符文写入 loot_data").is_true()
	# 旧虚构材料池应已移除
	assert_bool(source.find("wild_glowcap") == -1) \
		.override_failure_message("chest.gd 仍含旧虚构材料 wild_glowcap").is_true()
	assert_bool(source.find("frost_berry") == -1) \
		.override_failure_message("chest.gd 仍含旧虚构材料 frost_berry").is_true()

func test_chest_has_zone_export() -> void:
	# 确认 chest.gd 暴露 zone 属性供 procedural_dungeon 注入
	var script: GDScript = load("res://scenes/props/chest/chest.gd") as GDScript
	var source: String = script.source_code
	assert_bool(source.find("@export var zone") != -1) \
		.override_failure_message("chest.gd 未暴露 zone 导出属性").is_true()

# ---------- procedural_dungeon 注入 zone ----------

func test_procedural_dungeon_injects_zone_to_chest() -> void:
	# 确认 _spawn_prefab 对 CHEST_PREFAB 注入 zone
	var script: Resource = load("res://scenes/expedition/procedural_dungeon.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("instance.zone = dungeon_zone") != -1) \
		.override_failure_message("procedural_dungeon 未对宝箱注入 zone").is_true()
	assert_bool(source.find("@export var dungeon_zone") != -1) \
		.override_failure_message("procedural_dungeon 未暴露 dungeon_zone 属性").is_true()

# ---------- 散落材料池（单一数据源验证） ----------

func test_scatter_weights_all_zones_have_data() -> void:
	for zone_id in [0, 1, 2, 3, 4, 5]:
		var pool: Dictionary = lt.get_scatter_materials(zone_id)
		assert_bool(not pool.is_empty()) \
			.override_failure_message("区域 %d 散落池为空" % zone_id).is_true()

func test_scatter_weights_all_materials_valid() -> void:
	for zone_id in [0, 1, 2, 3, 4, 5]:
		var pool: Dictionary = lt.get_scatter_materials(zone_id)
		for mat_id in pool:
			assert_bool(BrewingData.MATERIALS_DB.has(mat_id)) \
				.override_failure_message("区域 %d 散落池含非法材料: %s" % [zone_id, mat_id]) \
				.is_true()

func test_scatter_weights_match_zone_theme() -> void:
	# 火山区散落池应含 firegrape，不含 blackberry
	var volcano_pool: Dictionary = lt.get_scatter_materials(4)
	assert_bool(volcano_pool.has("firegrape")).is_true()
	assert_bool(not volcano_pool.has("blackberry")).is_true()
	# 森林区应含 blackberry，不含 firegrape
	var forest_pool: Dictionary = lt.get_scatter_materials(1)
	assert_bool(forest_pool.has("blackberry")).is_true()
	assert_bool(not forest_pool.has("firegrape")).is_true()

func test_scatter_weights_returns_duplicate() -> void:
	# 确保返回的是副本，修改不影响原数据
	var pool1: Dictionary = lt.get_scatter_materials(0)
	pool1["fake_material"] = 999
	var pool2: Dictionary = lt.get_scatter_materials(0)
	assert_bool(not pool2.has("fake_material")).is_true()

func test_zone_manager_delegates_scatter_to_loot_table() -> void:
	# 验证 ZoneManager.get_scatter_materials 委托 LootTable
	var zm = Engine.get_main_loop().root.get_node("ZoneManager")
	assert_object(zm).is_not_null()
	for zone_id in [0, 1, 2, 3, 4, 5]:
		var zm_pool: Dictionary = zm.get_scatter_materials(zone_id)
		var lt_pool: Dictionary = lt.get_scatter_materials(zone_id)
		assert_dict(zm_pool).is_equal(lt_pool)
