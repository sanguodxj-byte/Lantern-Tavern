extends Node
## 护甲熟练度系统（autoload: ArmorProficiency）。
## 策划案《35-护甲体系》§六：穿甲受击累积经验，解锁专属被动。
##
## 等级阶梯：Lv.1 → Lv.100，每 10 级解锁一阶被动（T1/T2/T3）。
## 熟练度经验：每次被物理命中 +1（格挡命中 +2）。
##
## 轻甲被动：T1 轻盈步法 / T2 侧身闪避 / T3 疾风闪跃
## 重甲被动：T1 装甲加固 / T2 冲击缓冲 / T3 不屈壁垒

# ============================================================================
# 1. 常量
# ============================================================================

## 每级所需经验值（每次受击 +1，格挡受击 +2）
const EXP_PER_LEVEL := 10

## 最大等级
const MAX_LEVEL := 100

## 被动解锁等级表
const PERK_UNLOCK_LEVELS := {
	"light_t1": 10,   # 轻盈步法 / Light Footwork
	"light_t2": 30,   # 侧身闪避 / Sidestep
	"light_t3": 60,   # 疾风闪跃 / Gale Evasion
	"heavy_t1": 10,   # 装甲加固 / Reinforced Armor
	"heavy_t2": 30,   # 冲击缓冲 / Impact Cushioning
	"heavy_t3": 60,   # 不屈壁垒 / Unyielding Bastion
}

## 被动显示名称
const PERK_NAMES := {
	"light_t1": "轻盈步法",
	"light_t2": "侧身闪避",
	"light_t3": "疾风闪跃",
	"heavy_t1": "装甲加固",
	"heavy_t2": "冲击缓冲",
	"heavy_t3": "不屈壁垒",
}

# ============================================================================
# 2. 运行时状态
# ============================================================================

## 各类型护甲的熟练度经验
var _exp: Dictionary = {
	"light": 0,
	"heavy": 0,
}

## 当前穿着的护甲类型（由 CombatBridge 在构建 Defender 时更新）
var _wearing: Dictionary = {
	"light": false,
	"heavy": false,
}

func _ready() -> void:
	reset()

# ============================================================================
# 3. 查询接口（策划案 §6.4）
# ============================================================================

## 获取指定护甲类型的熟练度等级（Lv.1 ~ Lv.100）
func get_level(armor_type: String) -> int:
	var exp_val: int = int(_exp.get(armor_type.to_lower(), 0))
	return mini(int(exp_val / EXP_PER_LEVEL) + 1, MAX_LEVEL)

## 获取指定护甲类型的当前经验值
func get_exp(armor_type: String) -> int:
	return int(_exp.get(armor_type.to_lower(), 0))

## 检查指定被动是否已解锁
func has_perk(armor_type: String, perk_id: String) -> bool:
	var level := get_level(armor_type)
	var required: int = int(PERK_UNLOCK_LEVELS.get(perk_id, 999))
	return level >= required

## 检查当前是否穿着至少一件指定类型的护甲
func is_wearing_type(armor_type: String) -> bool:
	return bool(_wearing.get(armor_type.to_lower(), false))

# ============================================================================
# 4. 熟练度累积
# ============================================================================

## 增加熟练度经验（默认 +1，格挡命中 +2）
func add_exp(armor_type: String, amount: int = 1) -> void:
	var key := armor_type.to_lower()
	if not _exp.has(key):
		_exp[key] = 0
	_exp[key] = int(_exp[key]) + amount

## 受击时累积熟练度（由 CombatBridge 或 player.gd 在受击时调用）
## is_blocked: 是否格挡（格挡命中 +2 经验）
func on_hit_received(is_blocked: bool = false) -> void:
	var gain: int = 2 if is_blocked else 1
	if _wearing.get("light", false):
		add_exp("light", gain)
	if _wearing.get("heavy", false):
		add_exp("heavy", gain)

# ============================================================================
# 5. 当前护甲类型更新
# ============================================================================

## 从 ArmorSnapshot 更新当前穿着的护甲类型
func update_current_armor(snap) -> void:
	_wearing["light"] = false
	_wearing["heavy"] = false
	if snap == null:
		return
	_wearing["light"] = snap.has_light
	_wearing["heavy"] = snap.has_heavy

## 直接设置穿着状态（测试用）
func set_wearing(armor_type: String, value: bool) -> void:
	_wearing[armor_type.to_lower()] = value

# ============================================================================
# 6. 重甲熟练度被动效果（策划案 §6.3）
# ============================================================================

## 重甲物理防御加成（T1: +2 flat, T2: +5%, T3: +10%）
## 返回叠加在 base_phys_def 上的总加成值
func get_heavy_phys_def_bonus(base_phys_def: float) -> float:
	if not is_wearing_type("heavy"):
		return 0.0
	var bonus: float = 0.0
	if has_perk("heavy", "heavy_t1"):
		bonus += 2.0
	if has_perk("heavy", "heavy_t2"):
		bonus += base_phys_def * 0.05
	if has_perk("heavy", "heavy_t3"):
		bonus += base_phys_def * 0.10
	return bonus

## 获取有效击退抗性（T3: 完全免疫击退 = 1.0）
func get_effective_knockback_res(base_knockback_res: float) -> float:
	if is_wearing_type("heavy") and has_perk("heavy", "heavy_t3"):
		return 1.0
	return base_knockback_res

## 检查是否应跳过品质阶梯磨损（T2: 20% 概率不扣减）
func should_skip_degradation() -> bool:
	if is_wearing_type("heavy") and has_perk("heavy", "heavy_t2"):
		return randf() < 0.20
	return false

## 获取反震信息（T3: 15% 概率反震，伤害 = 自身物防 × 50%）
func get_reflect_info() -> Dictionary:
	if is_wearing_type("heavy") and has_perk("heavy", "heavy_t3"):
		return {"chance": 0.15, "damage_ratio": 0.50}
	return {"chance": 0.0, "damage_ratio": 0.0}

# ============================================================================
# 7. 轻甲熟练度被动效果（策划案 §6.2）
# ============================================================================

## 闪避性能档位加成（T1: +1, T2: +2, T3: +3）
func get_dodge_tier_bonus() -> int:
	if not is_wearing_type("light"):
		return 0
	if has_perk("light", "light_t3"):
		return 3
	if has_perk("light", "light_t2"):
		return 2
	if has_perk("light", "light_t1"):
		return 1
	return 0

## 侧击/背击伤害加成降低比例（T2: 50%）
## 返回 0.0~1.0，表示攻方侧击/背击伤害加成的缩减比例
func get_flanking_damage_reduction() -> float:
	if is_wearing_type("light") and has_perk("light", "light_t2"):
		return 0.50
	return 0.0

## 被暴击率降低（T3: −5%）
func get_crit_rate_reduction() -> float:
	if is_wearing_type("light") and has_perk("light", "light_t3"):
		return 5.0
	return 0.0

## 成功闪避后下次攻击前摇缩减（T3: −15%）
func get_dodge_windup_reduction() -> float:
	if is_wearing_type("light") and has_perk("light", "light_t3"):
		return 0.15
	return 0.0

# ============================================================================
# 8. 存档 / 读档
# ============================================================================

func reset() -> void:
	_exp = {"light": 0, "heavy": 0}
	_wearing = {"light": false, "heavy": false}

func to_dict() -> Dictionary:
	return {
		"exp": _exp.duplicate(true),
	}

func from_dict(data: Dictionary) -> void:
	var saved_exp: Dictionary = data.get("exp", {})
	_exp = {
		"light": int(saved_exp.get("light", 0)),
		"heavy": int(saved_exp.get("heavy", 0)),
	}
	_wearing = {"light": false, "heavy": false}
