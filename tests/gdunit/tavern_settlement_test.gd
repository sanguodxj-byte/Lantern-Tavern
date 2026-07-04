extends GdUnitTestSuite
## 夜晚营业结算引擎 (TavernSettlement) 测试。
## 验证策划案《12-满意度与价格结算系统》全闭环：
## 顾客生成、口味微调、互斥携带、人类付款、怪物结算、好感传递、盲盒赠予、声望赠礼。

const TS := preload("res://globals/tavern_settlement.gd")
var ts: Node  # autoload 实例

func before_test() -> void:
	ts = Engine.get_main_loop().root.get_node("TavernSettlement")
	# 重置状态，避免测试间污染（声望/传闻/常客名册）
	ts.rumor_reputation = 0
	for race in ts.faction_reputation.keys():
		ts.faction_reputation[race] = 0
	for race in ts.regular_customers.keys():
		ts.regular_customers[race].clear()

# ---------- 顾客生成 (策划案 12 §1 + §5.1) ----------

func test_generate_customer_has_race() -> void:
	var cust = ts.generate_customer("goblin")
	assert_str(cust.race_id).is_equal("goblin")


func test_generate_customer_copies_race_template() -> void:
	var cust = ts.generate_customer("goblin")
	# 哥布林模板：喜爱 {腐败:2, 甜美:1}，讨厌 [苦涩]
	# 注意：_apply_individual_flavor_tweak 可能随机给一个喜爱口味 +1
	assert_int(cust.liked.get("腐败", 0)).is_equal(2)
	assert_bool(cust.liked.get("甜美", 0) >= 1).is_true()
	assert_bool(cust.liked.get("甜美", 0) <= 2).is_true()  # 可能被 tweak +1
	assert_bool(cust.hated.has("苦涩")).is_true()


func test_generate_customer_carry_type_is_valid() -> void:
	# 100 次生成验证 carry_type 只能是 iron 或 gear
	for i in range(100):
		var cust = ts.generate_customer("goblin")
		assert_bool(cust.carry_type == "iron" or cust.carry_type == "gear").is_true()


func test_iron_carry_has_positive_amount() -> void:
	# 生成到 iron 类型时 M 必须 > 0
	var found_iron := false
	for i in range(200):
		var cust = ts.generate_customer("goblin")
		if cust.carry_type == "iron":
			found_iron = true
			assert_int(cust.iron_amount).is_greater(0)
			assert_bool(cust.gear_item.is_empty()).is_true()
			break
	assert_bool(found_iron).is_true()


func test_gear_carry_has_zero_iron_and_gear_item() -> void:
	var found_gear := false
	for i in range(200):
		var cust = ts.generate_customer("goblin")
		if cust.carry_type == "gear":
			found_gear = true
			assert_int(cust.iron_amount).is_equal(0)
			assert_bool(not cust.gear_item.is_empty()).is_true()
			break
	assert_bool(found_gear).is_true()


func test_iron_amount_within_race_base_range() -> void:
	# M = Round(base × Random(0.5, 1.5) × prestige_mult)
	# 哥布林 base=12，警惕阶段 mult=1.0，所以 M 应在 6-18 之间
	for i in range(100):
		var cust = ts.generate_customer("goblin")
		if cust.carry_type == "iron":
			assert_bool(cust.iron_amount >= 6 and cust.iron_amount <= 18) \
				.override_failure_message("哥布林铁片数 %d 越界 (应 6-18)" % cust.iron_amount) \
				.is_true()


func test_customer_has_real_name() -> void:
	var cust = ts.generate_customer("goblin")
	assert_bool(cust.real_name != "").is_true()


# ---------- 人类付款结算 (策划案 12 §4) ----------

func _make_human() -> Object:
	return ts.generate_customer("human")

func test_human_accepts_clean_brew_cheap_price() -> void:
	# 无魔物风味 + 价格 <= base → 实惠赞赏，金币=P_menu，好感+1
	var cust = _make_human()
	var brew := {"麦香": 5, "甜美": 3}
	var r = ts.settle(brew, 20, cust)
	assert_int(r.gold_gained).is_equal(20)
	assert_int(r.affinity_delta).is_equal(1)
	assert_str(r.tier).is_equal("实惠赞赏")
	assert_bool(r.refused).is_false()

func test_human_accepts_normal_price() -> void:
	var cust = _make_human()
	var brew := {"麦香": 5, "甜美": 3}
	var r = ts.settle(brew, 35, cust)  # base=30, 30<35<=39
	assert_int(r.gold_gained).is_equal(35)
	assert_str(r.tier).is_equal("合理接受")

func test_human_expensive_price_reputation_penalty() -> void:
	var cust = _make_human()
	var brew := {"麦香": 5, "甜美": 3}
	var r = ts.settle(brew, 45, cust)  # 39<45<=48
	assert_int(r.gold_gained).is_equal(45)
	assert_int(r.reputation_delta).is_equal(-2)
	assert_str(r.tier).is_equal("昂贵抱怨")

func test_human_extortionate_price_refused() -> void:
	var cust = _make_human()
	var brew := {"麦香": 5, "甜美": 3}
	var r = ts.settle(brew, 60, cust)  # >48
	assert_int(r.gold_gained).is_equal(0)
	assert_int(r.reputation_delta).is_equal(-15)
	assert_bool(r.refused).is_true()
	assert_str(r.tier).is_equal("暴利拒付")

func test_human_refuses_brew_with_stench() -> void:
	var cust = _make_human()
	var brew := {"麦香": 10, "甜美": 10, "恶臭": 1}
	var r = ts.settle(brew, 10, cust)
	assert_int(r.gold_gained).is_equal(0)
	assert_int(r.reputation_delta).is_equal(-10)
	assert_bool(r.refused).is_true()
	assert_str(r.tier).is_equal("摔杯拒付")

func test_human_refuses_brew_with_poison() -> void:
	var cust = _make_human()
	var brew := {"麦香": 10, "甜美": 10, "剧毒": 1}
	var r = ts.settle(brew, 10, cust)
	assert_bool(r.refused).is_true()


# ---------- 怪物结算 (策划案 12 §5.2) ----------

func test_monster_perfect_settlement_iron_full_pay() -> void:
	# 哥布林喜爱 {腐败:2, 甜美:1} 讨厌[苦涩]
	# 满足硬标准 + 溢出>=4 → 极佳，全额铁片
	var cust = ts.generate_customer("goblin")
	cust.carry_type = "iron"
	cust.iron_amount = 12
	var brew := {"腐败": 6, "甜美": 5}  # 溢出 = (6-2)+(5-1) = 8 >= 4
	var r = ts.settle(brew, 0, cust)
	assert_str(r.tier).is_equal("极佳")
	assert_int(r.affinity_delta).is_equal(15)
	assert_int(r.gold_gained).is_equal(12)

func test_monster_satisfied_settlement_iron_full_pay() -> void:
	var cust = ts.generate_customer("goblin")
	cust.carry_type = "iron"
	cust.iron_amount = 12
	var brew := {"腐败": 3, "甜美": 2}  # 溢出 = 1+1 = 2, 0<=2<4 → 满意
	var r = ts.settle(brew, 0, cust)
	assert_str(r.tier).is_equal("满意")
	assert_int(r.affinity_delta).is_equal(10)
	assert_int(r.gold_gained).is_equal(12)

func test_monster_perfect_gear_type_gives_blind_box() -> void:
	# 极佳档 + gear 类型 → 盲盒赠予，装备从 WeaponRegistry 动态抽取
	var cust = ts.generate_customer("goblin")
	cust.carry_type = "gear"
	cust.iron_amount = 0
	cust.gear_item = ts._pick_random_gear()
	if cust.gear_item.is_empty():
		# WeaponRegistry 未就绪时跳过（不应发生在正常流程）
		return
	var brew := {"腐败": 6, "甜美": 5}  # 溢出>=4 → 极佳
	var r = ts.settle(brew, 0, cust)
	assert_str(r.tier).is_equal("极佳")
	assert_int(r.gold_gained).is_equal(0)
	assert_bool(not r.gear_gained.is_empty()).is_true()
	# 盲盒必须包含合法装备 id（存在于 WeaponRegistry）
	var wr = Engine.get_main_loop().root.get_node("WeaponRegistry")
	assert_bool(wr.get_all_ids().has(r.gear_gained["id"])).is_true()
	# 必须含 tier_index 与 display_name
	assert_bool(r.gear_gained.has("tier_index")).is_true()
	assert_bool(r.gear_gained.has("display_name")).is_true()


func test_blind_box_gear_uses_weapon_registry() -> void:
	# 多次抽取盲盒，验证 id 全部来自 WeaponRegistry
	var wr = Engine.get_main_loop().root.get_node("WeaponRegistry")
	var all_ids: Array[String] = wr.get_all_ids()
	for i in range(20):
		var gear: Dictionary = ts._pick_random_gear()
		if gear.is_empty():
			continue
		assert_bool(all_ids.has(gear["id"])) \
			.override_failure_message("盲盒抽取了非法装备 id: %s" % gear["id"]) \
			.is_true()


func test_blind_box_tier_index_in_valid_range() -> void:
	# tier_index 必须在 0-2 之间（一/二/三阶）
	for i in range(50):
		var gear: Dictionary = ts._pick_random_gear()
		if gear.is_empty():
			continue
		var tier_idx: int = gear["tier_index"]
		assert_bool(tier_idx >= 0 and tier_idx <= 2) \
			.override_failure_message("盲盒 tier_index %d 越界 (应 0-2)" % tier_idx) \
			.is_true()


func test_blind_box_prefix_is_from_defined_pool() -> void:
	# 前缀词缀必须来自策划案定义的正/负/中性池
	var all_prefixes: Array = TS.GEAR_PREFIXES_POSITIVE + TS.GEAR_PREFIXES_NEGATIVE + TS.GEAR_PREFIXES_NEUTRAL
	for i in range(50):
		var gear: Dictionary = ts._pick_random_gear()
		if gear.is_empty():
			continue
		assert_bool(all_prefixes.has(gear["prefix"])) \
			.override_failure_message("盲盒前缀 %s 不在定义池中" % gear["prefix"]) \
			.is_true()


func test_blind_box_display_name_includes_prefix_and_tier() -> void:
	# display_name = prefix + tier_name（prefix 非空时）
	for i in range(50):
		var gear: Dictionary = ts._pick_random_gear()
		if gear.is_empty():
			continue
		var prefix: String = gear["prefix"]
		var tier_name: String = gear["tier_name"]
		var display: String = gear["display_name"]
		if prefix != "":
			assert_bool(display.begins_with(prefix)) \
				.override_failure_message("display_name %s 未包含前缀 %s" % [display, prefix]) \
				.is_true()
		assert_bool(display.ends_with(tier_name)) \
			.override_failure_message("display_name %s 未以 tier_name %s 结尾" % [display, tier_name]) \
			.is_true()

func test_monster_satisfied_gear_type_no_gift() -> void:
	# 满意档（非极佳）+ gear 类型：装备退回，不赠予
	var cust = ts.generate_customer("goblin")
	cust.carry_type = "gear"
	cust.gear_item = {"id": "test_axe"}
	var brew := {"腐败": 3, "甜美": 2}  # 溢出=2 → 满意
	var r = ts.settle(brew, 0, cust)
	assert_str(r.tier).is_equal("满意")
	assert_int(r.gold_gained).is_equal(0)
	assert_bool(r.gear_gained.is_empty()).is_true()

func test_monster_normal_settlement_partial_pay() -> void:
	# 一般/温饱：至少 1 项喜爱>=1 && 讨厌<=2 → 达标风味数×2（不超过M）
	var cust = ts.generate_customer("goblin")
	# 固定阈值，避免个体微调干扰断言
	cust.liked = {"腐败": 2, "甜美": 1}
	cust.hated = ["苦涩"]
	cust.hated_levels = {"苦涩": 0}
	cust.carry_type = "iron"
	cust.iron_amount = 12
	# 只让甜美达标，腐败不达标 → 硬标准不满足，走一般分支
	var brew := {"甜美": 1, "果香": 5}
	var r = ts.settle(brew, 0, cust)
	assert_str(r.tier).is_equal("一般")
	assert_int(r.affinity_delta).is_equal(2)
	# 达标风味数=1（仅甜美），1×2=2，不超过12
	assert_int(r.gold_gained).is_equal(2)

func test_monster_refuse_with_disliked_flavor_high() -> void:
	# 哥布林讨厌苦涩，若苦涩>2 → 完全不合
	var cust = ts.generate_customer("goblin")
	cust.carry_type = "iron"
	cust.iron_amount = 12
	var brew := {"腐败": 10, "甜美": 10, "苦涩": 3}  # 苦涩=3>容忍上限0
	var r = ts.settle(brew, 0, cust)
	assert_str(r.tier).is_equal("完全不合")
	assert_int(r.affinity_delta).is_equal(-5)
	assert_int(r.gold_gained).is_equal(0)
	assert_bool(r.refused).is_true()

func test_monster_no_liked_no_disliked_refuse() -> void:
	# 完全无喜爱风味 → 完全不合
	var cust = ts.generate_customer("goblin")
	cust.carry_type = "iron"
	cust.iron_amount = 12
	var brew := {"苦涩": 0}  # 什么喜爱都没有
	var r = ts.settle(brew, 0, cust)
	assert_str(r.tier).is_equal("完全不合")
	assert_int(r.gold_gained).is_equal(0)

# ---------- 好感度个体向群体传递 (策划案 12 §2) ----------

func test_affinity_transfers_to_faction_reputation() -> void:
	# 个体好感+15 → 势力声望 +1（15×0.1=1.5 向下取整=1）
	var cust = ts.generate_customer("goblin")
	var initial_rep: int = ts.faction_reputation["goblin"]
	var brew := {"腐败": 6, "甜美": 5}  # 极佳
	ts.settle(brew, 0, cust)
	assert_int(ts.faction_reputation["goblin"]).is_equal(initial_rep + 1)

func test_negative_affinity_transfers_to_faction() -> void:
	var cust = ts.generate_customer("goblin")
	var initial_rep: int = ts.faction_reputation["goblin"]
	var brew := {"苦涩": 5}  # 完全不合，好感-5
	ts.settle(brew, 0, cust)
	# -5 × 0.1 = -0.5 → 向下取整 -1（注意负数处理）
	assert_int(ts.faction_reputation["goblin"]).is_equal(initial_rep - 1)

func test_human_does_not_affect_faction_reputation() -> void:
	# 人类无好感系统，不影响任何势力声望
	var cust = ts.generate_customer("human")
	var initial_goblin: int = ts.faction_reputation["goblin"]
	var brew := {"麦香": 5, "甜美": 3}
	ts.settle(brew, 20, cust)
	assert_int(ts.faction_reputation["goblin"]).is_equal(initial_goblin)

# ---------- 全局传闻声望 ----------

func test_rumor_reputation_decreases_on_human_refuse() -> void:
	var cust = _make_human()
	var initial_rumor: int = ts.rumor_reputation
	var brew := {"恶臭": 1}
	ts.settle(brew, 10, cust)
	assert_int(ts.rumor_reputation).is_equal(initial_rumor - 10)

func test_rumor_reputation_decreases_on_extortionate_price() -> void:
	var cust = _make_human()
	var initial_rumor: int = ts.rumor_reputation
	var brew := {"麦香": 5, "甜美": 3}
	ts.settle(brew, 60, cust)  # 暴利拒付
	assert_int(ts.rumor_reputation).is_equal(initial_rumor - 15)

# ---------- 声望阶梯 (策划案 12 §6.1) ----------

func test_prestige_tier_wary_at_zero() -> void:
	ts.faction_reputation["goblin"] = 0
	assert_str(ts.get_prestige_tier_name("goblin")).is_equal("警惕")

func test_prestige_tier_exalted_at_high_value() -> void:
	ts.faction_reputation["goblin"] = 2000
	assert_str(ts.get_prestige_tier_name("goblin")).is_equal("生死之交")

func test_prestige_tier_boundaries() -> void:
	# 测试边界：100→警惕，101→中立，300→中立，301→友好
	ts.faction_reputation["goblin"] = 100
	assert_str(ts.get_prestige_tier_name("goblin")).is_equal("警惕")
	ts.faction_reputation["goblin"] = 101
	assert_str(ts.get_prestige_tier_name("goblin")).is_equal("中立")
	ts.faction_reputation["goblin"] = 600
	assert_str(ts.get_prestige_tier_name("goblin")).is_equal("友好")
	ts.faction_reputation["goblin"] = 601
	assert_str(ts.get_prestige_tier_name("goblin")).is_equal("信任")

# ---------- 声望赠礼 (策划案 12 §6.2) ----------

func test_prestige_gift_pool_contains_valid_materials() -> void:
	# 验证赠礼池中的材料 id 都存在于 BrewingData.MATERIALS_DB
	for race_id in TS.FACTION_GIFT_POOL:
		var pool = TS.FACTION_GIFT_POOL[race_id]
		for mat_id in pool.normal + pool.rare:
			assert_bool(BrewingData.MATERIALS_DB.has(mat_id)) \
				.override_failure_message("种族 %s 赠礼池含非法材料: %s" % [race_id, mat_id]) \
				.is_true()

func test_wary_tier_no_gift() -> void:
	# 警惕阶段赠礼概率=0，喝爽也不赠礼
	ts.faction_reputation["goblin"] = 0
	var cust = ts.generate_customer("goblin")
	cust.carry_type = "iron"
	cust.iron_amount = 12
	var brew := {"腐败": 6, "甜美": 5}
	# 多次测试，警惕阶段应无赠礼
	for i in range(50):
		var r = ts.settle(brew, 0, cust)
		assert_bool(r.gift_material.is_empty()).is_true()

# ---------- 常客名册 (策划案 02 §2.1) ----------

func test_regular_registration_at_affinity_threshold() -> void:
	# 个体好感>=30 录入常客名册并解锁本名
	var cust = ts.generate_customer("goblin")
	cust.display_name = "goblin"  # 初始显示种族泛称
	cust.individual_affinity = 0
	# 通过极佳结算累积好感
	for i in range(3):
		var brew := {"腐败": 6, "甜美": 5}
		ts.settle(brew, 0, cust)
	# 3次极佳 = 45 好感，应已录入名册
	assert_bool(cust.is_regular).is_true()
	assert_str(cust.display_name).is_equal(cust.real_name)
	assert_bool(ts.regular_customers["goblin"].has(cust)).is_true()

func test_regular_pool_max_five_per_race() -> void:
	# 每族常客上限 5 席
	for i in range(10):
		var cust = ts.generate_customer("goblin")
		cust.individual_affinity = 30 + i  # 不同好感
		ts._try_register_regular(cust)
	assert_int(ts.regular_customers["goblin"].size()).is_equal(5)

# ---------- 结算结果完整性 ----------

func test_settlement_result_initial_state() -> void:
	var r = TS.SettlementResult.new()
	assert_int(r.gold_gained).is_equal(0)
	assert_bool(r.gear_gained.is_empty()).is_true()
	assert_bool(r.gift_material.is_empty()).is_true()
	assert_int(r.affinity_delta).is_equal(0)
	assert_int(r.reputation_delta).is_equal(0)
	assert_bool(r.refused).is_false()
