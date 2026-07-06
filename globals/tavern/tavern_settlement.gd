extends Node
## 夜晚营业结算引擎（autoload: TavernSettlement）。
## 承载策划案《12-满意度与价格结算系统》全闭环：
## 顾客生成 + 口味微调 + 互斥双轨携带 + 满意度判定 + 付款结算 + 好感传递 + 盲盒赠予 + 声望赠礼。
## 依赖 BrewingData（酿酒数据中枢）与 TavernManager（金币/背包）。

# ============================================================================
# 1. 顾客数据结构
# ============================================================================

class Customer:
	var race_id: String           # 种族标识 (human/goblin/minotaur/cyclops/ghost/elf)
	var display_name: String      # 显示名（未熟识显示种族泛称，熟识显示本名）
	var real_name: String         # 真实本名（熟识后解锁）
	var liked: Dictionary         # 喜爱口味 {口味: 期望阈值}（含个体微调）
	var hated: Array              # 讨厌口味 [口味]（含个体微调后的强度记录）
	var hated_levels: Dictionary  # 讨厌口味的强度阈值 {口味: 容忍上限}（默认 0）
	var carry_type: String        # "iron" 携带亮铁片 / "gear" 携带装备
	var iron_amount: int          # 亮铁片数 M（gear 类型为 0）
	var gear_item: Dictionary     # 随身装备（gear 类型才有，{} 表示无）
	var individual_affinity: int  # 个体好感度
	var is_regular: bool          # 是否为已录入常客名册的熟面孔
	func _init(race: String) -> void:
		race_id = race

# 种族基准亮铁片数（策划案 12 §5.1）
const RACE_BASE_IRON: Dictionary = {
	"goblin": 12, "ghost": 24, "minotaur": 40, "cyclops": 55, "elf": 85,
}

# 种族姓名库（策划案 02 §2.1，熟识后解锁本名）
const RACE_NAME_POOL: Dictionary = {
	"goblin": ["格鲁姆", "斯尼克", "莫格", "拉格纳", "皮普"],
	"minotaur": ["铁蹄", "裂角", "巨锤", "磐石", "怒吼"],
	"cyclops": ["巴洛克", "独眼", "裂岩", "熔瞳", "崩山"],
	"ghost": ["幽影", "残念", "寒泣", "无面", "逝语"],
	"elf": ["艾琳娜", "月辉", "晨露", "叶语", "星弦"],
	"human": ["凯恩", "老兵", "旅人", "佣兵", "猎人"],
}

# 势力声望阶梯（策划案 12 §6.1）
enum PrestigeTier { WARY, NEUTRAL, FRIENDLY, TRUSTED, REVERED, EXALTED }

const PRESTIGE_TIERS: Array = [
	{"name": "警惕", "min": 0, "max": 100, "visit_rate": 1.0, "wallet_mult": 1.0, "gift_prob": 0.0},
	{"name": "中立", "min": 101, "max": 300, "visit_rate": 1.1, "wallet_mult": 1.1, "gift_prob": 0.05},
	{"name": "友好", "min": 301, "max": 600, "visit_rate": 1.25, "wallet_mult": 1.25, "gift_prob": 0.10},
	{"name": "信任", "min": 601, "max": 1000, "visit_rate": 1.45, "wallet_mult": 1.4, "gift_prob": 0.18},
	{"name": "崇敬", "min": 1001, "max": 1500, "visit_rate": 1.7, "wallet_mult": 1.6, "gift_prob": 0.28},
	{"name": "生死之交", "min": 1501, "max": 999999, "visit_rate": 2.0, "wallet_mult": 2.0, "gift_prob": 0.40},
]

# 全局传闻声望
var rumor_reputation: int = 0
# 各势力声望 {race_id: 声望值}
var faction_reputation: Dictionary = {
	"goblin": 0, "minotaur": 0, "cyclops": 0, "ghost": 0, "elf": 0,
}
# 常客名册 {race_id: [Customer...]}，上限每族 5 席
var regular_customers: Dictionary = {
	"goblin": [], "minotaur": [], "cyclops": [], "ghost": [], "elf": [],
}
const REGULAR_MAX_PER_RACE: int = 5

# 装备盲盒词缀池（已迁移至 AffixSystem autoload，此处保留兼容性常量）
const GEAR_PREFIXES_POSITIVE: Array = ["锋利", "坚韧", "炽焰", "寒霜", "破甲", "嗜血"]
const GEAR_PREFIXES_NEGATIVE: Array = ["锈蚀", "裂痕", "钝重", "诅咒", "残缺"]
const GEAR_PREFIXES_NEUTRAL: Array = ["", "普通", "老旧"]

## 从 WeaponRegistry 动态抽取盲盒装备（策划案 12 §5.2）。
## 品质（一/二/三阶 tier）、装备 id、词缀全部纯随机，不挂钩势力声望。
## 返回 {id, tier_index, tier_name, prefix, display_name, weapon_data}，空字典表示注册表未就绪。
func _pick_random_gear() -> Dictionary:
	var wr: Node = _get_weapon_registry()
	if wr == null or wr.get_all_ids().is_empty():
		return {}
	var all_ids: Array[String] = wr.get_all_ids()
	var pick_id: String = all_ids[randi() % all_ids.size()]
	var tiers: Array = wr.get_tiers(pick_id)
	var tier_idx: int = 0
	if not tiers.is_empty():
		tier_idx = randi() % tiers.size()
	# 使用 build_weapon_data_with_tier 创建独立副本并应用阶位属性
	var weapon_data = wr.build_weapon_data_with_tier(pick_id, tier_idx)
	if weapon_data == null:
		return {}
	# Roll 词缀并应用
	var affix_system: Node = _get_affix_system()
	var affixes: Array[String] = []
	if affix_system != null:
		affixes = affix_system.roll_affixes()
		if not affixes.is_empty():
			affix_system.apply_affixes(weapon_data, affixes)
	var tier_name: String = weapon_data.tier_name
	if tier_name.is_empty():
		tier_name = wr.get_display_name(pick_id)
	# 生成显示名（含词缀前缀）
	var display: String = weapon_data.get_full_display_name()
	var prefix_str: String = ""
	for affix_id in affixes:
		if affix_system != null:
			prefix_str += affix_system.get_affix_name(affix_id)
		else:
			prefix_str += affix_id
	return {
		"id": pick_id,
		"tier_index": tier_idx,
		"tier_name": tier_name,
		"prefix": prefix_str,
		"display_name": display,
		"weapon_data": weapon_data,
	}

func _pick_random_prefix() -> String:
	# 已迁移至 AffixSystem，此方法保留兼容性
	var affix_system: Node = _get_affix_system()
	if affix_system != null:
		var affixes: Array[String] = affix_system.roll_affixes()
		if affixes.is_empty():
			return ""
		return affix_system.get_affix_name(affixes[0])
	# fallback 旧逻辑
	var roll: float = randf()
	if roll < 0.5:
		return GEAR_PREFIXES_POSITIVE[randi() % GEAR_PREFIXES_POSITIVE.size()]
	elif roll < 0.8:
		return GEAR_PREFIXES_NEGATIVE[randi() % GEAR_PREFIXES_NEGATIVE.size()]
	else:
		return GEAR_PREFIXES_NEUTRAL[randi() % GEAR_PREFIXES_NEUTRAL.size()]

func _get_weapon_registry() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null("WeaponRegistry")

func _get_affix_system() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null("AffixSystem")

# ============================================================================
# 2. 顾客生成（策划案 12 §1 + §5.1）
# ============================================================================

## 生成一个普通顾客。race_id 为空则按基础概率随机选种族。
func generate_customer(race_id: String = "") -> Customer:
	if race_id == "":
		race_id = _pick_random_race()
	var cust := Customer.new(race_id)
	# 1. 拷贝种族模板
	var template: Dictionary = BrewingData.RACE_PREFERENCES.get(race_id, {})
	cust.liked = template.get("liked", {}).duplicate()
	cust.hated = (template.get("hated", []) as Array).duplicate()
	for h in cust.hated:
		cust.hated_levels[h] = 0
	# 2. 个体口味微调（50% 喜爱+1，50% 讨爱容忍上限+1）
	_apply_individual_flavor_tweak(cust)
	# 3. 姓名遮罩
	cust.real_name = _pick_random_name(race_id)
	cust.display_name = race_id  # 未熟识显示种族泛称（翻译键）
	# 4. 互斥双轨携带（人类无此机制，固定金币消费；怪物 50% 铁片 / 50% 装备）
	if race_id == "human":
		cust.carry_type = "iron"
		cust.iron_amount = 0  # 人类付款由菜单标价决定，不预置铁片
		cust.gear_item = {}
	else:
		if randf() < 0.5:
			cust.carry_type = "iron"
			var base: int = RACE_BASE_IRON.get(race_id, 10)
			var mult: float = get_prestige_tier(race_id).wallet_mult
			cust.iron_amount = int(round(base * randf_range(0.5, 1.5) * mult))
			cust.gear_item = {}
		else:
			cust.carry_type = "gear"
			cust.iron_amount = 0
			cust.gear_item = _pick_random_gear()
	# 5. 30% 概率从常客名册挑选熟面孔（人类无名册，跳过）
	if race_id != "human" and randf() < 0.3 and regular_customers.get(race_id, []).size() > 0:
		var pool: Array = regular_customers[race_id]
		return pool[randi() % pool.size()]
	cust.is_regular = false
	cust.individual_affinity = 0
	return cust

func _apply_individual_flavor_tweak(cust: Customer) -> void:
	if randf() < 0.5 and cust.liked.size() > 0:
		# 喜爱口味 +1
		var keys: Array = cust.liked.keys()
		var pick: String = keys[randi() % keys.size()]
		cust.liked[pick] = cust.liked[pick] + 1
	elif cust.hated.size() > 0:
		# 讨爱口味容忍上限 -1（即反感程度减轻，允许少量出现）
		var pick: String = cust.hated[randi() % cust.hated.size()]
		cust.hated_levels[pick] = 1  # 容忍上限提升到 1

func _pick_random_race() -> String:
	var races: Array = ["goblin", "minotaur", "cyclops", "ghost", "elf", "human"]
	return races[randi() % races.size()]

func _pick_random_name(race_id: String) -> String:
	var pool: Array = RACE_NAME_POOL.get(race_id, ["无名"])
	return pool[randi() % pool.size()]

# ============================================================================
# 3. 结算决策树（策划案 12 §3 + §4 + §5.2）
# ============================================================================

class SettlementResult:
	var gold_gained: int = 0
	var gear_gained: Dictionary = {}   # 装备盲盒赠予
	var gift_material: Dictionary = {} # 声望赠礼 {material_id: count}
	var affinity_delta: int = 0        # 个体好感度变动
	var reputation_delta: int = 0      # 全局传闻声望变动
	var tier: String = ""              # 评价档次标签
	var refused: bool = false          # 是否拒付离席

## 主结算入口。brew_flavors=酒水口味, menu_price=菜单标价, customer=顾客。
## 返回 SettlementResult，并自动更新 customer.individual_affinity 与 faction_reputation。
func settle(brew_flavors: Dictionary, menu_price: int, customer: Customer) -> SettlementResult:
	var result := SettlementResult.new()
	if customer.race_id == "human":
		_settle_human(brew_flavors, menu_price, result)
	else:
		_settle_monster(brew_flavors, customer, result)
	# 后置：个体好感变动 → 势力声望传递（向下取整 10%，负数用 floor）
	if customer.race_id != "human" and result.affinity_delta != 0:
		var faction_gain: int = int(floor(result.affinity_delta * 0.1))
		faction_reputation[customer.race_id] = faction_reputation.get(customer.race_id, 0) + faction_gain
		customer.individual_affinity += result.affinity_delta
		# 熟识解锁本名（个体好感达到阈值即录入常客名册）
		_try_register_regular(customer)
	# 全局传闻声望变动
	if result.reputation_delta != 0:
		rumor_reputation += result.reputation_delta
	return result

# ---- 人类分支（策划案 12 §4）----
func _settle_human(brew_flavors: Dictionary, menu_price: int, result: SettlementResult) -> void:
	# 一票否决：含魔物专属风味（恶臭/腐败/死寂/剧毒 > 0）
	for taboo in ["恶臭", "腐败", "死寂", "剧毒"]:
		if brew_flavors.get(taboo, 0) > 0:
			result.gold_gained = 0
			result.reputation_delta = -10
			result.tier = "摔杯拒付"
			result.refused = true
			return
	# 价格偏离度评估。P_base 取酒谱标价或默认 30
	var p_base: int = 30  # 占位：应从匹配的酒谱读取 price
	var p_menu: int = menu_price
	if p_menu <= p_base:
		result.gold_gained = p_menu
		result.affinity_delta = 1
		result.tier = "实惠赞赏"
	elif p_menu <= int(p_base * 1.3):
		result.gold_gained = p_menu
		result.tier = "合理接受"
	elif p_menu <= int(p_base * 1.6):
		result.gold_gained = p_menu
		result.reputation_delta = -2
		result.tier = "昂贵抱怨"
	else:
		result.gold_gained = 0
		result.reputation_delta = -15
		result.tier = "暴利拒付"
		result.refused = true

# ---- 怪物分支（策划案 12 §5.2）----
func _settle_monster(brew_flavors: Dictionary, cust: Customer, result: SettlementResult) -> void:
	# 计算满意度硬标准：喜爱全达标 && 讨厌全不超容忍上限
	var hard_pass: bool = true
	var delta: int = 0  # 溢出值和
	for flavor_name in cust.liked:
		var threshold: int = cust.liked[flavor_name]
		var actual: int = brew_flavors.get(flavor_name, 0)
		if actual < threshold:
			hard_pass = false
		else:
			delta += actual - threshold
	var hated_ok: bool = true
	for h_flavor in cust.hated:
		if brew_flavors.get(h_flavor, 0) > cust.hated_levels.get(h_flavor, 0):
			hated_ok = false
	# 判定档次
	if hard_pass and hated_ok and delta >= 4:
		# 极佳/爆表赠予
		result.tier = "极佳"
		result.affinity_delta = 15
		if cust.carry_type == "iron":
			result.gold_gained = cust.iron_amount
		else:
			result.gold_gained = 0
			result.gear_gained = cust.gear_item  # 盲盒赠予
		_roll_prestige_gift(cust, result)
	elif hard_pass and hated_ok and delta >= 0:
		# 满意/喝爽
		result.tier = "满意"
		result.affinity_delta = 10
		if cust.carry_type == "iron":
			result.gold_gained = cust.iron_amount
		else:
			result.gold_gained = 0  # M=0，装备退回
		_roll_prestige_gift(cust, result)
	else:
		# 检查一般/温饱：至少 1 项喜爱 >=1 且讨厌 <=2
		var any_liked: bool = false
		for fn in cust.liked:
			if brew_flavors.get(fn, 0) >= 1:
				any_liked = true
				break
		var hated_within_two: bool = true
		for hf in cust.hated:
			if brew_flavors.get(hf, 0) > 2:
				hated_within_two = false
				break
		if any_liked and hated_within_two:
			result.tier = "一般"
			result.affinity_delta = 2
			if cust.carry_type == "iron":
				# 达标风味数 × 2，不超过 M
				var hit_count: int = 0
				for fn in cust.liked:
					if brew_flavors.get(fn, 0) >= cust.liked[fn]:
						hit_count += 1
				result.gold_gained = min(hit_count * 2, cust.iron_amount)
			else:
				result.gold_gained = 0  # 装备退回
		else:
			result.tier = "完全不合"
			result.affinity_delta = -5
			result.gold_gained = 0
			result.refused = true

# ============================================================================
# 4. 声望赠礼（策划案 12 §6.2）
# ============================================================================

## 喝爽后掷骰，落入声望阶段赠礼概率则赠送本族专属材料
func _roll_prestige_gift(cust: Customer, result: SettlementResult) -> void:
	var tier: Dictionary = get_prestige_tier(cust.race_id)
	var prob: float = tier.gift_prob
	if randf() < prob:
		var gift: Dictionary = _pick_faction_gift(cust.race_id)
		if not gift.is_empty():
			result.gift_material = gift

# 种族赠礼池（策划案 12 §6.2）
const FACTION_GIFT_POOL: Dictionary = {
	"goblin": {"normal": ["goblin_nail", "poison_berry"], "rare": ["glowshroom"]},
	"minotaur": {"normal": ["deeprock_moss", "black_rye_root"], "rare": ["lava_jet"]},
	"cyclops": {"normal": ["cyclops_beard", "black_rye_root"], "rare": ["lava_malt"]},
	"elf": {"normal": ["moongrass", "blackberry"], "rare": ["moon_lily"]},
	"ghost": {"normal": ["soulmint", "ghost_tear"], "rare": ["wraith_ash"]},
}

func _pick_faction_gift(race_id: String) -> Dictionary:
	var pool: Dictionary = FACTION_GIFT_POOL.get(race_id, {})
	if pool.is_empty():
		return {}
	var mat_id: String
	var count: int = 1
	if randf() < 0.2:
		mat_id = pool.rare[randi() % pool.rare.size()]
		count = 1
	else:
		mat_id = pool.normal[randi() % pool.normal.size()]
		count = randi_range(1, 2)
	return {mat_id: count}

# ============================================================================
# 5. 声望阶梯与常客名册
# ============================================================================

## 获取种族当前声望阶梯
func get_prestige_tier(race_id: String) -> Dictionary:
	var rep: int = faction_reputation.get(race_id, 0)
	for tier in PRESTIGE_TIERS:
		if rep >= tier.min and rep <= tier.max:
			return tier
	return PRESTIGE_TIERS[0]

## 获取种族声望阶梯名
func get_prestige_tier_name(race_id: String) -> String:
	return get_prestige_tier(race_id).name

## 个体好感达到"熟悉"阈值（>=30）即录入常客名册，解锁本名
func _try_register_regular(cust: Customer) -> void:
	if cust.is_regular:
		return
	if cust.individual_affinity < 30:
		return
	cust.is_regular = true
	cust.display_name = cust.real_name  # 解锁本名
	var pool: Array = regular_customers[cust.race_id]
	# 上限替换：好感最低且最久未来店的常客被替换
	if pool.size() >= REGULAR_MAX_PER_RACE:
		var lowest_idx: int = 0
		for i in range(1, pool.size()):
			if pool[i].individual_affinity < pool[lowest_idx].individual_affinity:
				lowest_idx = i
		pool[lowest_idx] = cust
	else:
		pool.append(cust)

# ============================================================================
# 6. 工具
# ============================================================================

func randf_range(a: float, b: float) -> float:
	return a + randf() * (b - a)

func randi_range(a: int, b: int) -> int:
	return a + randi() % (b - a + 1)
