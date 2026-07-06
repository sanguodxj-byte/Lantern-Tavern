class_name WeaponData
extends Resource

@export var id: String = ""
@export var name: String = ""
@export var name_zh: String = ""
@export var condition: int = 20
@export var max_condition: int = 20
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
@export var skill_school: String = ""
@export var combat_styles: Array[String] = []
@export var proficiency_key: String = ""
@export var hands: String = ""
@export var tier_index: int = 0
@export var tier_name: String = ""
@export var hit_bonus_percent: float = 0.0
@export var crit_bonus_percent: float = 0.0
@export var crit_damage_bonus: float = 0.0
@export var armor_pierce_percent: float = 0.0
@export var knockback_m: float = 0.0
@export var stun_sec: float = 0.0
@export var shield_phys_def: int = 0
@export var shield_block_value: int = 0
@export var shield_block_chance_percent: float = 0.0
@export var equipment_category: String = ""
@export var armor_slot: String = ""
@export var armor_phys_def: int = 0
@export var armor_evade_percent: float = 0.0
@export var armor_move_speed_mult: float = 1.0

# ── 词缀系统字段（策划案 06 §3）──
## 已应用的词缀 ID 列表（如 "sharp", "rusty" 等）
@export var affixes: Array[String] = []
## 伤害倍率（词缀修正后的最终倍率，1.0 = 无修正）
@export var damage_mult: float = 1.0
## 负重倍率（词缀修正，1.0 = 无修正）
@export var carry_weight_mult: float = 1.0
## 负重加成（饰品类装备专用）
@export var carry_weight_bonus: int = 0
## 是否已损坏（耐久归零时标记，所有属性失效）
@export var is_broken: bool = false

func get_damage_dealt() -> int:
	if is_broken:
		return 0
	if id.is_empty():
		return randi_range(damage_min, damage_max)
	if damage_dice_count <= 0 or damage_dice_sides <= 0:
		return max(damage_flat, 0)
	var total := damage_flat
	for i in range(damage_dice_count):
		total += randi_range(1, damage_dice_sides)
	return int(round(float(total) * damage_mult))

func decrease_condition(amount: int) -> void:
	condition = clampi(condition - amount, 0, max_condition)
	if condition <= 0:
		is_broken = true

## 获取含词缀前缀的完整显示名
func get_full_display_name() -> String:
	var base := name_zh if not name_zh.is_empty() else name
	if not tier_name.is_empty():
		base = tier_name
	var prefix := ""
	for affix_id in affixes:
		prefix += _affix_display_prefix(affix_id)
	return prefix + base if not prefix.is_empty() else base

## 词缀 ID → 中文前缀文字
static func _affix_display_prefix(affix_id: String) -> String:
	match affix_id:
		"sharp": return "锋利的"
		"lightweight": return "轻盈的"
		"focused": return "专注的"
		"furious": return "狂暴的"
		"sturdy": return "坚固的"
		"blessed": return "受洗的"
		"rusty": return "生锈的"
		"clunky": return "笨重的"
		"worn": return "磨损的"
		"inferior": return "劣质的"
		"cracked": return "碎裂的"
		"dim": return "黯淡的"
		_: return ""
