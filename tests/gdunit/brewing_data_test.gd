extends GdUnitTestSuite
## 酿酒数据中枢 (BrewingData) 完整性测试。
## 验证 16 种口味、40 种材料、10 种经典酒谱、6 种族偏好阈值
## 与策划案《09》《10》《13》的数值完全一致。

# 运行时函数已是 static，直接用 const BD 调用
const BD := preload("res://globals/brewing_data.gd")
var bd: Node  # 备用 autoload 引用

func before_test() -> void:
	bd = Engine.get_main_loop().root.get_node("BrewingData") if Engine.get_main_loop() else null

# ---------- 16 种口味完整性 (策划案 09 §1) ----------

func test_flavor_count_is_16() -> void:
	assert_int(BD.Flavor.size()).is_equal(16)


func test_flavor_name_enum_bidirectional_consistency() -> void:
	# 中文键 → 枚举 → 中文键 必须往返一致
	for name in BD.FLAVOR_NAME_TO_ENUM:
		var enum_val = BD.FLAVOR_NAME_TO_ENUM[name]
		assert_str(BD.FLAVOR_ENUM_TO_NAME[enum_val]).is_equal(name)
	# 反向：枚举 → 中文 → 枚举
	for enum_val in BD.FLAVOR_ENUM_TO_NAME:
		var name = BD.FLAVOR_ENUM_TO_NAME[enum_val]
		assert_int(BD.FLAVOR_NAME_TO_ENUM[name]).is_equal(enum_val)


func test_flavor_tr_keys_cover_all_16() -> void:
	assert_int(BD.FLAVOR_TR_KEYS.size()).is_equal(16)


# ---------- 40 种材料完整性 (策划案 10) ----------

func test_material_count_is_40() -> void:
	assert_int(BD.MATERIALS_DB.size()).is_equal(40)


func test_each_zone_has_10_materials() -> void:
	# 策划案分 4 区，每区 10 种
	var zone_counts: Dictionary = {}
	for mat_id in BD.MATERIALS_DB:
		var zone: int = BD.MATERIALS_DB[mat_id].zone
		zone_counts[zone] = zone_counts.get(zone, 0) + 1
	assert_int(zone_counts[BD.Zone.FOREST]).is_equal(10)
	assert_int(zone_counts[BD.Zone.CAVES]).is_equal(10)
	assert_int(zone_counts[BD.Zone.GRAVEYARD]).is_equal(10)
	assert_int(zone_counts[BD.Zone.VOLCANO]).is_equal(10)


func test_all_material_flavors_use_valid_names() -> void:
	# 每种材料的口味键必须全部属于 16 种正式口味
	for mat_id in BD.MATERIALS_DB:
		var flavors: Dictionary = BD.MATERIALS_DB[mat_id].flavors
		for flavor_name in flavors:
			assert_bool(BD.FLAVOR_NAME_TO_ENUM.has(flavor_name)) \
				.override_failure_message("材料 %s 含非法口味键: %s" % [mat_id, flavor_name]) \
				.is_true()


func test_material_flavor_intensity_in_valid_range() -> void:
	# 策划案规定强度 1-4 点
	for mat_id in BD.MATERIALS_DB:
		var flavors: Dictionary = BD.MATERIALS_DB[mat_id].flavors
		for flavor_name in flavors:
			var intensity: int = flavors[flavor_name]
			assert_bool(intensity >= 1 and intensity <= 4) \
				.override_failure_message("材料 %s 的 %s 强度 %d 越界 (应 1-4)" % [mat_id, flavor_name, intensity]) \
				.is_true()


func test_material_flavor_count_in_valid_range() -> void:
	# 策划案规定每材料 1-4 种风味倾向
	for mat_id in BD.MATERIALS_DB:
		var flavor_count: int = BD.MATERIALS_DB[mat_id].flavors.size()
		assert_bool(flavor_count >= 1 and flavor_count <= 4) \
			.override_failure_message("材料 %s 风味数 %d 越界 (应 1-4)" % [mat_id, flavor_count]) \
			.is_true()


func test_all_materials_have_name_and_zone() -> void:
	for mat_id in BD.MATERIALS_DB:
		var mat: Dictionary = BD.MATERIALS_DB[mat_id]
		assert_bool(mat.has("name") and mat.name is String and mat.name != "") \
			.override_failure_message("材料 %s 缺中文名" % mat_id).is_true()
		assert_bool(mat.has("zone") and mat.zone is int) \
			.override_failure_message("材料 %s 缺区域" % mat_id).is_true()


# ---------- 10 种经典酒谱完整性 (策划案 13) ----------

func test_recipe_count_is_10() -> void:
	assert_int(BD.RECIPES_DB.size()).is_equal(10)


func test_all_recipe_ingredients_are_valid_materials() -> void:
	for recipe_id in BD.RECIPES_DB:
		var ings: Dictionary = BD.RECIPES_DB[recipe_id].ingredients
		for mat_id in ings:
			assert_bool(BD.MATERIALS_DB.has(mat_id)) \
				.override_failure_message("酒谱 %s 引用不存在的材料: %s" % [recipe_id, mat_id]) \
				.is_true()


func test_all_recipe_ingredient_counts_positive() -> void:
	for recipe_id in BD.RECIPES_DB:
		var ings: Dictionary = BD.RECIPES_DB[recipe_id].ingredients
		for mat_id in ings:
			assert_int(ings[mat_id]).is_greater(0)


func test_recipe_expected_flavors_match_computation() -> void:
	# 核心校验：策划案标定的合成口味必须与按材料加算的结果完全一致
	for recipe_id in BD.RECIPES_DB:
		var recipe: Dictionary = BD.RECIPES_DB[recipe_id]
		var computed: Dictionary = BD.compute_brew_flavors(recipe.ingredients)
		var expected: Dictionary = recipe.expected_flavors
		assert_int(computed.size()).is_equal(expected.size())
		for flavor_name in expected:
			assert_int(computed.get(flavor_name, 0)) \
				.override_failure_message("酒谱 %s 的 %s 应为 %d，实算 %d" % [recipe_id, flavor_name, expected[flavor_name], computed.get(flavor_name, 0)]) \
				.is_equal(expected[flavor_name])


# ---------- 6 种族偏好阈值矩阵 (策划案 09 §2.1) ----------

func test_race_preference_count_is_6() -> void:
	assert_int(BD.RACE_PREFERENCES.size()).is_equal(6)


func test_all_race_liked_flavors_valid() -> void:
	for race_id in BD.RACE_PREFERENCES:
		var liked: Dictionary = BD.RACE_PREFERENCES[race_id].liked
		for flavor_name in liked:
			assert_bool(BD.FLAVOR_NAME_TO_ENUM.has(flavor_name)) \
				.override_failure_message("种族 %s 喜爱含非法口味: %s" % [race_id, flavor_name]) \
				.is_true()
			assert_int(liked[flavor_name]).is_greater(0)


func test_all_race_hated_flavors_valid() -> void:
	for race_id in BD.RACE_PREFERENCES:
		var hated: Array = BD.RACE_PREFERENCES[race_id].hated
		for flavor_name in hated:
			assert_bool(BD.FLAVOR_NAME_TO_ENUM.has(flavor_name)) \
				.override_failure_message("种族 %s 讨厌含非法口味: %s" % [race_id, flavor_name]) \
				.is_true()


# 策划案逐条数值断言
func test_human_preferences_exact() -> void:
	var p: Dictionary = BD.RACE_PREFERENCES.human
	assert_int(p.liked["麦香"]).is_equal(2)
	assert_int(p.liked["甜美"]).is_equal(1)
	assert_array(p.hated).contains_exactly(["恶臭", "腐败", "死寂", "剧毒"])


func test_goblin_preferences_exact() -> void:
	var p: Dictionary = BD.RACE_PREFERENCES.goblin
	assert_int(p.liked["腐败"]).is_equal(2)
	assert_int(p.liked["甜美"]).is_equal(1)
	assert_array(p.hated).contains_exactly(["苦涩"])


func test_minotaur_preferences_exact() -> void:
	var p: Dictionary = BD.RACE_PREFERENCES.minotaur
	assert_int(p.liked["麦香"]).is_equal(3)
	assert_int(p.liked["浓郁"]).is_equal(2)
	assert_array(p.hated).contains_exactly(["酸爽"])


func test_cyclops_preferences_exact() -> void:
	var p: Dictionary = BD.RACE_PREFERENCES.cyclops
	assert_int(p.liked["辣口"]).is_equal(3)
	assert_int(p.liked["温暖"]).is_equal(2)
	assert_array(p.hated).contains_exactly(["甜美"])


func test_ghost_preferences_exact() -> void:
	var p: Dictionary = BD.RACE_PREFERENCES.ghost
	assert_int(p.liked["死寂"]).is_equal(3)
	assert_int(p.liked["寒凉"]).is_equal(2)
	assert_array(p.hated).contains_exactly(["温暖"])


func test_elf_preferences_exact() -> void:
	var p: Dictionary = BD.RACE_PREFERENCES.elf
	assert_int(p.liked["香醇"]).is_equal(3)
	assert_int(p.liked["果香"]).is_equal(2)
	assert_array(p.hated).contains_exactly(["恶臭", "腐败"])


# ---------- 满意度判定逻辑 (策划案 09 §2) ----------

func test_satisfaction_liked_meets_threshold_passes() -> void:
	# 人类：麦香>=2 甜美>=1 无讨厌 → 满意
	var brew := {"麦香": 2, "甜美": 1}
	assert_bool(BD.evaluate_satisfaction(brew, "human")).is_true()


func test_satisfaction_liked_below_threshold_fails() -> void:
	# 人类：麦香=1 不达标 → 不满意
	var brew := {"麦香": 1, "甜美": 1}
	assert_bool(BD.evaluate_satisfaction(brew, "human")).is_false()


func test_satisfaction_hated_present_fails() -> void:
	# 人类：含恶臭 → 一票否决
	var brew := {"麦香": 5, "甜美": 5, "恶臭": 1}
	assert_bool(BD.evaluate_satisfaction(brew, "human")).is_false()


func test_satisfaction_goblin_with_rot_sweet_passes() -> void:
	# 哥布林：腐败>=2 甜美>=1 无苦涩 → 满意
	var brew := {"腐败": 2, "甜美": 1}
	assert_bool(BD.evaluate_satisfaction(brew, "goblin")).is_true()


func test_satisfaction_goblin_with_bitter_fails() -> void:
	# 哥布林：含苦涩 → 一票否决
	var brew := {"腐败": 5, "甜美": 5, "苦涩": 1}
	assert_bool(BD.evaluate_satisfaction(brew, "goblin")).is_false()


func test_satisfaction_unknown_race_returns_false() -> void:
	var brew := {"麦香": 10}
	assert_bool(BD.evaluate_satisfaction(brew, "dragon")).is_false()


# ---------- 经典配方匹配 ----------

func test_match_recipe_exact_match() -> void:
	# 亮莓果汁：2 黑莓 + 1 蓝光菇 + 1 妖精粉尘
	var ings := {"blackberry": 2, "glowshroom": 1, "pixie_dust": 1}
	assert_str(BD.match_recipe(ings)).is_equal("glowberry_juice")


func test_match_recipe_no_match_returns_empty() -> void:
	var ings := {"blackberry": 1, "glowshroom": 1}
	assert_str(BD.match_recipe(ings)).is_equal("")


func test_match_recipe_wrong_count_no_match() -> void:
	# 数量不对
	var ings := {"blackberry": 1, "glowshroom": 1, "pixie_dust": 1}
	assert_str(BD.match_recipe(ings)).is_equal("")


# ---------- 酒谱受众与定价校验 (策划案 13) ----------

func test_glowberry_juice_price_is_30() -> void:
	assert_int(BD.RECIPES_DB.glowberry_juice.price).is_equal(30)


func test_moonlight_ale_price_is_45() -> void:
	assert_int(BD.RECIPES_DB.moonlight_ale.price).is_equal(45)


func test_lava_royal_whiskey_price_is_80() -> void:
	assert_int(BD.RECIPES_DB.lava_royal_whiskey.price).is_equal(80)


func test_monster_recipes_have_null_price() -> void:
	# 哥布林/牛头人/独眼巨人/幽灵专属酒谱无人类标价
	for recipe_id in ["goblin_sweet_rot_mash", "blindfish_rot_wine", "heavyrock_charred_stout", "magma_spicy_spirits", "sulfur_flame_mash", "ice_coffin_undead_call", "moonlily_honey_mead"]:
		assert_object(BD.RECIPES_DB[recipe_id].price).is_null()


# ---------- compute_brew_flavors 加算逻辑 ----------

func test_compute_brew_flavors_sums_correctly() -> void:
	# 2 黑莓(果香3 甜美2) → 果香6 甜美4
	var ings := {"blackberry": 2}
	var result: Dictionary = bd.compute_brew_flavors(ings)
	assert_int(result["果香"]).is_equal(6)
	assert_int(result["甜美"]).is_equal(4)


func test_compute_brew_flavors_unknown_material_ignored() -> void:
	var ings := {"blackberry": 1, "nonexistent": 5}
	var result: Dictionary = bd.compute_brew_flavors(ings)
	# 只算 blackberry
	assert_int(result["果香"]).is_equal(3)
	assert_bool(not result.has("nonexistent"))


func test_compute_brew_flavors_empty_returns_empty() -> void:
	var result: Dictionary = bd.compute_brew_flavors({})
	assert_bool(result.is_empty()).is_true()
