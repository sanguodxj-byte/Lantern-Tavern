class_name WeaponData
extends Resource

@export var id: String = ""
@export var name: String = ""
@export var name_zh: String = ""
@export var condition: int = 800
@export var max_condition: int = 800
@export var damage_min: int = 1
@export var damage_max: int = 3
@export var damage_dice_count: int = 1
@export var damage_dice_sides: int = 6
@export var damage_flat: int = 0
@export var impale_local_translation: Vector3 = Vector3(0, 0, 0.7)
@export var impale_local_rotation: float = 0.0
@export var reach: float = 3.0
@export var throw_rotation_speed: float = 40.0
@export var throw_movement_speed: float = 10.0
@export var glb_mesh: PackedScene
@export var item_tag: String = ""
@export var tags: Array[String] = []
@export var weapon_class: String = ""
@export var attack_type: String = "melee"
## 装弹时长（秒）。仅弩类需要（doc21 reload_shot：每次射击后须装弹，装弹完成前不允许连续发射）。
## 0 表示无装弹（弓/近战）。轻弩未显式设置时回落到 player.CROSSBOW_RELOAD_FALLBACK_SEC。
@export var reload_time: float = 0.0
@export var skill_school: String = ""
@export var combat_styles: Array[String] = []
## Explicit first-person visual profile. Empty keeps legacy taxonomy fallback.
@export var view_model_profile: String = ""
@export var proficiency_key: String = ""
@export var hands: String = ""
@export var tier_index: int = 0
@export var tier_name: String = ""
@export var crit_bonus_percent: float = 0.0
@export var crit_damage_bonus: float = 0.0
@export var armor_pierce_percent: float = 0.0
@export var knockback_m: float = 0.0
@export var stun_sec: float = 0.0
@export var shield_phys_def: int = 0
# 盾无格挡概念：概率/格挡值字段已移除，仅保留物理防御
@export var equipment_category: String = ""
@export var armor_slot: String = ""
@export var armor_phys_def: int = 0
@export var armor_move_speed_mult: float = 1.0

# ── 类 ToME4 / Elona 品质与材质字段 ──
@export var material_tier: String = "iron"         # wood, iron, steel, meteoric, mithril, adamantite
@export var rarity: String = "COMMON"             # INFERIOR, COMMON, SUPERIOR, RARE, EPIC, ARTIFACT
@export var quality_tier: String = "EXCELLENT"    # EXCELLENT, SERVICEABLE, WORN, DECREPIT, DESTROYED
@export var is_identified: bool = true            # 是否已鉴定
@export var is_cursed: bool = false                # 是否诅咒（强行锁定装备槽位）
@export var is_blessed: bool = false               # 是否受赐福

# ── 词缀系统字段（策划案 06 §3）──
## 已应用的词缀 ID 列表（如 "sharp", "rusty" 等）
@export var affixes: Array[String] = []
## 伤害倍率（词缀与材质修正后的最终倍率，1.0 = 无修正）
@export var damage_mult: float = 1.0
## 负重倍率（词缀修正，1.0 = 无修正）
@export var carry_weight_mult: float = 1.0
## 负重加成（饰品类装备专用）
@export var carry_weight_bonus: int = 0
## 是否已损坏（耐久归零时标记，所有属性失效）
@export var is_broken: bool = false

## 吸血百分比加成（实装于伤害结算）
@export var lifesteal_percent: float = 0.0
## 挥刀自扣生命值（诅咒实装）
@export var self_hp_drain_per_hit: int = 0
## 低血斩杀伤害倍率（实装）
@export var low_hp_execute_mult: float = 0.0

## 获取品质稀有度对应 UI 显示颜色 (ToME4 / Elona 风格)
func get_rarity_color() -> Color:
	match rarity.to_upper():
		"INFERIOR": return Color("#888888")  # 灰字劣质
		"COMMON": return Color("#FFFFFF")    # 白字普通
		"SUPERIOR": return Color("#33FF55")  # 绿字优秀
		"RARE": return Color("#3399FF")      # 蓝字稀有
		"EPIC": return Color("#AA33FF")      # 紫字史诗
		"ARTIFACT": return Color("#FFCC00")  # 金字神器
		_: return Color("#FFFFFF")

func get_damage_dealt() -> int:
	if is_broken:
		return 0
	if id.is_empty():
		# 确定性伤害（取 min/max 均值）
		return int(round(float(damage_min + damage_max) / 2.0))
	if damage_dice_count <= 0 or damage_dice_sides <= 0:
		return max(damage_flat, 0)
	var avg := float(damage_dice_count) * float(damage_dice_sides + 1) / 2.0
	# 应用材质基础倍率 + 词缀倍率
	var mat_mult := _get_material_damage_multiplier()
	return int(round((avg + float(damage_flat)) * damage_mult * mat_mult))

func _get_material_damage_multiplier() -> float:
	match material_tier:
		"steel": return 1.05
		"meteoric": return 1.10
		"mithril": return 1.15
		"adamantite": return 1.20
		"wood": return 0.90
		_: return 1.00

func decrease_condition(amount: int) -> void:
	condition = clampi(condition - amount, 0, max_condition)
	if condition <= 0:
		is_broken = true

## 获取材质本地化显示名
func get_material_display_name() -> String:
	match material_tier:
		"wood": return TranslationServer.translate("木质")
		"iron": return TranslationServer.translate("铁质")
		"steel": return TranslationServer.translate("精钢")
		"meteoric": return TranslationServer.translate("玄铁")
		"mithril": return TranslationServer.translate("秘银")
		"adamantite": return TranslationServer.translate("精金")
		_: return ""

## 获取稀有度本地化显示名
func get_rarity_display_name() -> String:
	match rarity.to_upper():
		"INFERIOR": return TranslationServer.translate("劣质")
		"COMMON": return TranslationServer.translate("普通")
		"SUPERIOR": return TranslationServer.translate("优秀")
		"RARE": return TranslationServer.translate("稀有")
		"EPIC": return TranslationServer.translate("史诗")
		"ARTIFACT": return TranslationServer.translate("神器")
		_: return TranslationServer.translate("普通")

## 获取含材质、品质、词缀与未鉴定遮罩的完整本地化显示名
func get_full_display_name() -> String:
	var is_zh := TranslationServer.get_locale().begins_with("zh")
	# 未鉴定遮罩逻辑
	if not is_identified:
		var cat_name := TranslationServer.translate("武器")
		if equipment_category == "shields":
			cat_name = TranslationServer.translate("防盾")
		elif equipment_category.begins_with("armor"):
			cat_name = TranslationServer.translate("防具")
		elif equipment_category == "accessories":
			cat_name = TranslationServer.translate("饰品")
		return TranslationServer.translate("未鉴定的") + " " + cat_name

	var base := ""
	if is_zh:
		if not tier_name.is_empty():
			base = TranslationServer.translate(tier_name)
		elif not name_zh.is_empty():
			base = TranslationServer.translate(name_zh)
		else:
			base = TranslationServer.translate(name) if not name.is_empty() else id
	else:
		if not name.is_empty():
			base = TranslationServer.translate(name)
		elif not name_zh.is_empty():
			base = TranslationServer.translate(name_zh)
		else:
			base = id
		if not tier_name.is_empty():
			base = TranslationServer.translate(tier_name)

	var mat_str := get_material_display_name()
	var prefix := ""
	for affix_id in affixes:
		prefix += _affix_display_prefix(affix_id) + " "

	if is_zh:
		var mat_prefix := (mat_str + " ") if not mat_str.is_empty() and mat_str != "铁质" else ""
		return prefix + mat_prefix + base
	else:
		var mat_prefix := (mat_str + " ") if not mat_str.is_empty() else ""
		return mat_prefix + prefix + base

## 词缀 ID → 中文前缀/后缀文字
static func _affix_display_prefix(affix_id: String) -> String:
	match affix_id:
		"sharp": return TranslationServer.translate("锋利的")
		"flamereached": return TranslationServer.translate("灼热的")
		"frostbound": return TranslationServer.translate("霜冻的")
		"lightning_touched": return TranslationServer.translate("闪雷的")
		"venomous": return TranslationServer.translate("淬毒的")
		"bloodthirsty": return TranslationServer.translate("嗜血的")
		"swift": return TranslationServer.translate("疾风的")
		"lightweight": return TranslationServer.translate("轻盈的")
		"focused": return TranslationServer.translate("专注的")
		"furious": return TranslationServer.translate("狂暴的")
		"sturdy": return TranslationServer.translate("坚固的")
		"titan": return TranslationServer.translate("泰坦的")
		"blessed": return TranslationServer.translate("赐福的")
		"shining": return TranslationServer.translate("辉闪的")
		"rusty": return TranslationServer.translate("生锈的")
		"brittle": return TranslationServer.translate("易碎的")
		"dull": return TranslationServer.translate("钝化的")
		"clunky": return TranslationServer.translate("笨重的")
		"worn": return TranslationServer.translate("磨损的")
		"inferior": return TranslationServer.translate("劣质的")
		"cracked": return TranslationServer.translate("碎裂的")
		"cursed_vampiric": return TranslationServer.translate("诅咒·吸髓")
		"cursed_sloth": return TranslationServer.translate("诅咒·迟钝")
		"cursed_weight": return TranslationServer.translate("诅咒·沉重")
		"of_slaying": return TranslationServer.translate("之 斩杀")
		"of_parrying": return TranslationServer.translate("之 格架")
		"of_the_vanguard": return TranslationServer.translate("之 先锋")
		"of_tenacity": return TranslationServer.translate("之 韧性")
		"of_scavenger": return TranslationServer.translate("之 搜刮")
		"of_warding": return TranslationServer.translate("之 庇护")
		"of_clarity": return TranslationServer.translate("之 清明")
		"of_precision": return TranslationServer.translate("之 精准")
		_: return ""

## 词缀 ID → 效果简述（用于 UI 详情行，微数值防膨胀）
static func affix_effect_description(affix_id: String) -> String:
	match affix_id:
		"sharp": return TranslationServer.translate("物理伤害 +3%，暴击率 +1%")
		"flamereached": return TranslationServer.translate("伤害 +3%（附加火元素）")
		"frostbound": return TranslationServer.translate("伤害 +2%（附加微量冰元素）")
		"lightning_touched": return TranslationServer.translate("伤害 +2%（附加微量雷元素）")
		"venomous": return TranslationServer.translate("伤害 +2%（附加微量毒元素）")
		"bloodthirsty": return TranslationServer.translate("微量吸血 +0.5%")
		"swift": return TranslationServer.translate("攻击速度 +3%")
		"lightweight": return TranslationServer.translate("负重扣减 -10%")
		"focused": return TranslationServer.translate("暴击率 +3%")
		"furious": return TranslationServer.translate("暴击率 +2%，暴击伤害 +4%")
		"sturdy": return TranslationServer.translate("物理防御 +1")
		"titan": return TranslationServer.translate("近战碰撞打击半径 +5%")
		"blessed": return TranslationServer.translate("全伤害 +4%，暴击率 +2%")
		"shining": return TranslationServer.translate("照亮半径 +1m，法术防损 +2%")
		"rusty": return TranslationServer.translate("物理伤害 -4%")
		"brittle": return TranslationServer.translate("受击磨损退阶率 +15%")
		"dull": return TranslationServer.translate("暴击率 -3%")
		"clunky": return TranslationServer.translate("负重增加 +10%")
		"worn": return TranslationServer.translate("暴击率 -2%")
		"inferior": return TranslationServer.translate("暴击率 -2%，最大耐久 -8%")
		"cracked": return TranslationServer.translate("物理防御 -1")
		"cursed_vampiric": return TranslationServer.translate("伤害 +5%，挥刀扣 1 点自血 (诅咒)")
		"cursed_sloth": return TranslationServer.translate("攻击速度 -5% (诅咒)")
		"cursed_weight": return TranslationServer.translate("负重 +15%，移速 -3% (诅咒)")
		"of_slaying": return TranslationServer.translate("低血伤害 +5%")
		"of_parrying": return TranslationServer.translate("格挡防阻退阶 +4%")
		"of_the_vanguard": return TranslationServer.translate("满血状态暴击率 +3%")
		"of_tenacity": return TranslationServer.translate("残血状态物防 +2")
		"of_scavenger": return TranslationServer.translate("金币掉落概率 +3%")
		"of_warding": return TranslationServer.translate("法术减伤 +3%")
		"of_clarity": return TranslationServer.translate("施法耗蓝 -3%")
		"of_precision": return TranslationServer.translate("物理护甲穿透 +3%")
		_: return ""

## 词缀 ID → 品质类型（"positive" / "negative" / ""）
static func affix_quality(affix_id: String) -> String:
	match affix_id:
		"sharp", "lightweight", "focused", "furious", "sturdy", "blessed":
			return "positive"
		"rusty", "clunky", "worn", "inferior", "cracked", "dim":
			return "negative"
		_:
			return ""

## 根据词缀列表获取整体品质颜色
## 全正向 → 金色; 有正有负 → 银白色; 全负向 → 灰红; 无词缀 → 白色
static func get_affix_color(affixes_list: Array) -> Color:
	if affixes_list.is_empty():
		return Color.WHITE
	var has_positive := false
	var has_negative := false
	for affix_id in affixes_list:
		var q := affix_quality(String(affix_id))
		if q == "positive":
			has_positive = true
		elif q == "negative":
			has_negative = true
	if has_positive and has_negative:
		return Color(0.82, 0.82, 0.85)  # 银白色（正负权衡）
	if has_positive:
		return Color(0.30, 0.90, 0.40)  # 绿色（纯正向）
	if has_negative:
		return Color(0.90, 0.35, 0.35)  # 红色（纯负向）
	return Color.WHITE

## 根据词缀列表获取品质标签文字
static func get_affix_quality_label(affixes_list: Array) -> String:
	if affixes_list.is_empty():
		return ""
	var has_positive := false
	var has_negative := false
	for affix_id in affixes_list:
		var q := affix_quality(String(affix_id))
		if q == "positive":
			has_positive = true
		elif q == "negative":
			has_negative = true
	if has_positive and has_negative:
		return TranslationServer.translate("权衡")
	if has_positive:
		return TranslationServer.translate("精良")
	if has_negative:
		return TranslationServer.translate("瑕疵")
	return ""

## 获取所有词缀的拼接效果描述（每行一条）
static func get_affix_detail_lines(affixes_list: Array) -> Array[String]:
	var lines: Array[String] = []
	for affix_id in affixes_list:
		var id_str := String(affix_id)
		var prefix := _affix_display_prefix(id_str)
		var effect := affix_effect_description(id_str)
		if not effect.is_empty():
			lines.append("%s: %s" % [prefix, effect])
	return lines
