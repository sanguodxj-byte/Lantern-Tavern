class_name OriginData
extends RefCounted

## 出身系统数据层（非 autoload，纯数据查询）。
## 在新游戏开始时由 TavernManager.start_new_game() 调用 apply_origin() 应用到 AttrPanel。
## 设计文档：docs/36-出身系统与涌现式Build.md
##
## 出身 ≠ 职业：仅提供初始属性偏移 + 一件武器 + 关系微调，不锁定任何成长路径。

# ============================================================================
# 1. 出身定义表
# ============================================================================

const ORIGINS: Array = [
	{
		"id": "retired_mercenary",
		"name": "退役佣兵",
		"name_en": "Retired Mercenary",
		"lore": "厌倦了无休止的杀戮，靠旧人脉盘下地下城边缘的破酒馆。刀口舔血的日子结束了，但手艺没丢。",
		"attr_bonus": {"str": 3, "con": 1},
		"starting_weapon": "sword",
		"starting_shield": "shield",
		"faction_bonus": {"human": 30},
		"brewing_direction": "烈性麦酒",
		"target_zone": "volcano",
		"proficiency_headstart": {"sword": 2},
	},
	{
		"id": "forest_hunter",
		"name": "林间猎人",
		"name_en": "Forest Hunter",
		"lore": "常年在地下城边缘的林区采药狩猎，与哥布林拾荒者和精灵隐居者打过多年交道。",
		"attr_bonus": {"dex": 3, "per": 1},
		"starting_weapon": "longbow",
		"starting_shield": "",
		"faction_bonus": {"goblin": 30, "elf": 30},
		"brewing_direction": "清爽果酒",
		"target_zone": "forest",
		"proficiency_headstart": {"bow": 2},
	},
	{
		"id": "half_baked_warlock",
		"name": "半吊子术士",
		"name_en": "Half-baked Warlock",
		"lore": "跟幽灵学者学过几年魔法，天赋不足没能出师，转行开酒馆。残缺的咒书还能凑合用。",
		"attr_bonus": {"mag": 3, "per": 1},
		"starting_weapon": "staff",
		"starting_shield": "",
		"faction_bonus": {"ghost": 30},
		"brewing_direction": "灵性酒",
		"target_zone": "graveyard",
		"proficiency_headstart": {"staff": 2},
	},
	{
		"id": "dwarven_disciple",
		"name": "矮人学徒",
		"name_en": "Dwarven Disciple",
		"lore": "在矮人铁匠铺当学徒出师的人类，想自己做老板。打铁练就的体魄比一般人类壮实得多。",
		"attr_bonus": {"con": 3, "str": 1},
		"starting_weapon": "warhammer",
		"starting_shield": "shield",
		"faction_bonus": {"minotaur": 30},
		"brewing_direction": "烈性黑啤",
		"target_zone": "caves",
		"proficiency_headstart": {"hammer": 2},
	},
]

# ============================================================================
# 2. 查询 API
# ============================================================================

## 按 id 获取出身定义（返回副本，防止外部修改常量）
static func get_origin(origin_id: String) -> Dictionary:
	for o in ORIGINS:
		if String(o["id"]) == origin_id:
			return o.duplicate(true)
	return {}

## 获取所有出身 id
static func get_all_ids() -> Array:
	var ids: Array = []
	for o in ORIGINS:
		ids.append(String(o["id"]))
	return ids

## 获取所有出身的显示名（用于 UI）
static func get_all_names() -> Array:
	var names: Array = []
	for o in ORIGINS:
		names.append({"id": String(o["id"]), "name": String(o["name"]), "name_en": String(o["name_en"])})
	return names

## 获取出身数量
static func count() -> int:
	return ORIGINS.size()

# ============================================================================
# 3. 出身效果应用
# ============================================================================

## 将出身效果应用到 AttrPanel（属性偏移 + 熟练度起跑）。
## 在新游戏初始化或 reset() 之后调用一次。
## 返回 true 表示成功应用，false 表示出身 id 无效。
static func apply_origin(attr_panel, origin_id: String) -> bool:
	var origin: Dictionary = get_origin(origin_id)
	if origin.is_empty():
		push_error("[OriginData] Unknown origin id: %s" % origin_id)
		return false
	# 属性偏移
	var attr_bonus: Dictionary = origin.get("attr_bonus", {})
	for attr_key in attr_bonus:
		if attr_panel.attrs.has(attr_key):
			attr_panel.attrs[attr_key] = int(attr_panel.attrs[attr_key]) + int(attr_bonus[attr_key])
	# 熟练度起跑
	var prof_headstart: Dictionary = origin.get("proficiency_headstart", {})
	for prof_key in prof_headstart:
		var headstart_val: int = int(prof_headstart[prof_key])
		var cur_val: int = int(attr_panel.weapon_proficiency.get(prof_key, 0))
		attr_panel.weapon_proficiency[prof_key] = maxi(cur_val, headstart_val)
	# 记录出身 id
	attr_panel.origin_id = origin_id
	# 重算里程碑（初始值可能已触发 T1）
	for attr_key in attr_bonus:
		if attr_panel.has_method("_check_milestone_unlock"):
			attr_panel._check_milestone_unlock(attr_key)
	# 重算熟练度阶梯（起跑值可能已触发 20）
	for prof_key in prof_headstart:
		var val: int = int(attr_panel.weapon_proficiency.get(prof_key, 0))
		if attr_panel.has_method("_check_proficiency_milestones"):
			attr_panel._check_proficiency_milestones(prof_key, val)
	return true

## 将出身势力加成应用到 TavernSettlement。
## human 阵营不在 faction_reputation 中（人类冒险者是顾客来源而非独立势力），
## 保留加成用于未来人类好感 hook。
static func apply_faction_bonus(tavern_settlement, origin_id: String) -> void:
	var origin: Dictionary = get_origin(origin_id)
	if origin.is_empty():
		return
	var faction_bonus: Dictionary = origin.get("faction_bonus", {})
	for faction in faction_bonus:
		var bonus_val: int = int(faction_bonus[faction])
		if tavern_settlement.faction_reputation.has(faction):
			tavern_settlement.faction_reputation[faction] = int(tavern_settlement.faction_reputation[faction]) + bonus_val
		# human 阵营无独立条目，跳过（保留用于未来扩展）
