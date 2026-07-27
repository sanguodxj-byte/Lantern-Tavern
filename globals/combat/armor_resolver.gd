class_name ArmorResolver
## 护甲结算器（ArmorResolver）—— 百分比减伤 + 元素抗性 + 魔法减伤管线。
##
## 职责：把「基础伤害 + 护甲面板 + 攻方穿透」结算为「最终伤害」，
## 覆盖策划案《35-护甲体系》§三~§八 全流程：
##   物理减伤(%) → 魔法减伤(%) → 元素抗性(绝对) → 里程碑绝对减免 → max(1)
##
## 废弃旧版平减法 `final = max(1, base − (armor_def+con))`，
## 改为伤害相关百分比减伤 `mit% = def / (def + k × base)`（PoE2 / Brotato 家族）。

# ============================================================================
# 1. 常量
# ============================================================================

## 减伤曲线陡峭常数。k 越大，防御对低伤的吸收越强、对高伤的穿透越快。
const K := 8.0

## 物理减伤硬封顶 90%。
const MAX_PHYSICAL_MITIGATION := 0.90

## 魔法减伤硬封顶 75%。
const MAX_MAGIC_MITIGATION := 75.0

# ============================================================================
# 2. 品质系数 / 材质倍率 / 稀有度系数
# ============================================================================

const QUALITY_COEFFICIENTS := {
	"EXCELLENT": 1.0,
	"SERVICEABLE": 0.9,
	"WORN": 0.75,
	"DECREPIT": 0.5,
	"DESTROYED": 0.0,
}

const MATERIAL_MULTIPLIERS := {
	"wood": 0.90,
	"iron": 1.0,
	"steel": 1.05,
	"meteoric": 1.10,
	"mithril": 1.15,
	"adamantite": 1.20,
}

const RARITY_COEFFICIENTS := {
	"INFERIOR": 0.85,
	"COMMON": 1.0,
	"SUPERIOR": 1.03,
	"RARE": 1.06,
	"EPIC": 1.10,
	"ARTIFACT": 1.15,
}

## 获取品质系数（安全降级，未知品质返回 1.0）
static func get_quality_coefficient(quality_tier: String) -> float:
	return float(QUALITY_COEFFICIENTS.get(quality_tier.to_upper(), 1.0))

## 获取材质倍率（安全降级，未知材质返回 1.0）
static func get_material_multiplier(material_tier: String) -> float:
	return float(MATERIAL_MULTIPLIERS.get(material_tier.to_lower(), 1.0))

## 获取稀有度系数（安全降级，未知稀有度返回 1.0）
static func get_rarity_coefficient(rarity: String) -> float:
	return float(RARITY_COEFFICIENTS.get(rarity.to_upper(), 1.0))

# ============================================================================
# 3. 单件护甲有效物理防御
# ============================================================================

## 计算单件护甲的有效物理防御值（品质 × 材质 × 稀有度 三重修正）。
static func get_effective_phys_def(armor) -> float:
	if armor == null:
		return 0.0
	var base_def: int = int(armor.armor_phys_def)
	var q := get_quality_coefficient(armor.quality_tier)
	var m := get_material_multiplier(armor.material_tier)
	var r := get_rarity_coefficient(armor.rarity)
	return float(base_def) * q * m * r

## 计算单件护甲的有效元素抗性（仅受品质系数影响，不受材质/稀有度修正）。
static func get_effective_element_res(armor, element: String) -> int:
	if armor == null:
		return 0
	var field := "armor_%s_res" % element
	if not field in armor:
		return 0
	var base_res: int = int(armor.get(field))
	var q := get_quality_coefficient(armor.quality_tier)
	return int(round(float(base_res) * q))

# ============================================================================
# 4. 护甲面板聚合（从 EquipmentComponent 读取全身护甲）
# ============================================================================

## 护甲面板快照：从装备组件提取的全身护甲聚合数据。
class ArmorSnapshot:
	var total_phys_def: float = 0.0
	var total_fire_res: int = 0
	var total_ice_res: int = 0
	var total_lightning_res: int = 0
	var total_poison_res: int = 0
	var total_magic_res_percent: float = 0.0
	var total_knockback_res: float = 0.0
	var total_move_speed_mult: float = 1.0
	var has_light: bool = false
	var has_heavy: bool = false

# ----------------------------------------------------------------------------
# 性能优化：护甲快照缓存
# ----------------------------------------------------------------------------
## 缓存上限（超过时清空重建，避免长时间运行后陈旧条目堆积）。
const _SNAPSHOT_CACHE_MAX_SIZE: int = 128
## 缓存结构：eq_instance_id -> {"fingerprint": Array[int], "snapshot": ArmorSnapshot}
## 指纹 = 装备项 instance_id 排序列表；相同指纹 → 装备未变 → 复用快照（O(n)→O(1)）。
## 战斗中每秒数十次受击，护甲变更频率极低（换装时才变），命中率接近 100%。
static var _snapshot_cache: Dictionary = {}

## 判断两组指纹是否相同（逐元素比较排序列表）。
static func _fingerprint_matches(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if a[i] != b[i]:
			return false
	return true

## 从 EquipmentComponent 构建护甲面板快照（带缓存）。
## 缓存策略：以装备组件 instance_id 为 key、装备项 instance_id 排序列列为指纹。
## 装备项替换/增删 → 指纹变化 → 重建快照；装备项不变 → 直接复用。
## 注意：返回的 ArmorSnapshot 是引用类型，调用方不应修改返回的缓存对象。
static func build_snapshot(eq) -> ArmorSnapshot:
	if eq == null or not eq.has_method("get_equipped_armor_items"):
		return ArmorSnapshot.new()
	var items: Array = eq.get_equipped_armor_items()
	# 计算指纹：装备项 instance_id 排序列表
	var fingerprint: Array = []
	for armor in items:
		if armor != null and is_instance_valid(armor):
			fingerprint.append(armor.get_instance_id())
	fingerprint.sort()
	# 缓存命中检查
	var eq_id: int = eq.get_instance_id()
	if _snapshot_cache.has(eq_id):
		var cached: Dictionary = _snapshot_cache[eq_id]
		if _fingerprint_matches(cached.get("fingerprint", []), fingerprint):
			return cached["snapshot"]
	# 缓存大小控制：超过上限时清空（保守但安全，避免陈旧条目无限增长）
	if _snapshot_cache.size() >= _SNAPSHOT_CACHE_MAX_SIZE:
		_snapshot_cache.clear()
	# 重建快照
	var snap := ArmorSnapshot.new()
	for armor in items:
		if armor == null:
			continue
		snap.total_phys_def += get_effective_phys_def(armor)
		snap.total_fire_res += get_effective_element_res(armor, "fire")
		snap.total_ice_res += get_effective_element_res(armor, "ice")
		snap.total_lightning_res += get_effective_element_res(armor, "lightning")
		snap.total_poison_res += get_effective_element_res(armor, "poison")
		snap.total_magic_res_percent += float(armor.armor_magic_res_percent)
		snap.total_knockback_res += float(armor.armor_knockback_res)
		snap.total_move_speed_mult *= float(armor.armor_move_speed_mult)
		var atype: String = String(armor.armor_type)
		if atype == "light":
			snap.has_light = true
		elif atype == "heavy":
			snap.has_heavy = true
	# 封顶
	snap.total_magic_res_percent = minf(snap.total_magic_res_percent, MAX_MAGIC_MITIGATION)
	snap.total_knockback_res = clampf(snap.total_knockback_res, 0.0, 1.0)
	# 写入缓存
	_snapshot_cache[eq_id] = {"fingerprint": fingerprint, "snapshot": snap}
	return snap

## 使某装备组件的快照缓存失效（装备变更时调用）。
static func invalidate_snapshot_cache(eq) -> void:
	if eq == null:
		return
	_snapshot_cache.erase(eq.get_instance_id())

## 清理全部护甲快照缓存（场景切换 / 测试重置时调用）。
static func clear_snapshot_cache() -> void:
	_snapshot_cache.clear()

# ============================================================================
# 5. 核心结算管线
# ============================================================================

## 结算输入：由 CombatBridge 从 AttackInput + Defender + ArmorSnapshot 组装。
class ResolveInput:
	var base_damage: float = 0.0           # 进入防御前的伤害（已含暴击/朝向/材质修正）
	var attack_type: String = "melee"       # melee / ranged / spell
	var total_phys_def: float = 0.0         # 聚合后的有效物理防御（不含 con）
	var con: int = 10                       # 体质属性
	var ignore_def_percent: float = 0.0     # 攻方穿透
	var total_magic_res_percent: float = 0.0
	var fire_res: int = 0
	var ice_res: int = 0
	var lightning_res: int = 0
	var poison_res: int = 0
	var flat_reduce: int = 0                # 里程碑绝对减免（厚实皮肤 −2、元素护壳 −4）
	var element_type: String = ""           # 攻击的元素类型："fire"/"ice"/"lightning"/"poison"/""
	var ignore_def: bool = false             # 骷髅+锤被动：完全无视防御
	var knockback_res: float = 0.0          # 击退抗性（0~1，1=完全免疫）

## 结算结果。
class ResolveResult:
	var final_damage: int = 0
	var physical_mitigation: float = 0.0    # 物理减伤百分比（0~90）
	var magic_mitigation: float = 0.0       # 魔法减伤百分比（0~75）
	var element_absorbed: int = 0           # 元素抗性吸收的绝对值
	var flat_absorbed: int = 0              # 里程碑绝对减免
	var effective_def: float = 0.0           # 最终防御基值
	var knockback_res: float = 0.0          # 击退抗性（0~1）

## 执行护甲结算管线。
## 调用方：DamageResolver.resolve_attack 或 CombatBridge.resolve_player_attack。
static func resolve(input: ResolveInput) -> ResolveResult:
	var result := ResolveResult.new()
	var base: float = input.base_damage

	# ---- 阶段一：物理减伤（百分比）----
	var def: float = 0.0
	if input.ignore_def:
		def = 0.0
		result.effective_def = 0.0
	else:
		def = (input.total_phys_def + float(input.con)) * (1.0 - input.ignore_def_percent / 100.0)
		result.effective_def = def

	var mitigation: float = 0.0
	if def > 0.0 and base > 0.0:
		mitigation = def / (def + K * base)
		mitigation = minf(mitigation, MAX_PHYSICAL_MITIGATION)
	result.physical_mitigation = mitigation
	var post_mit: float = base * (1.0 - mitigation)

	# ---- 阶段二：魔法减伤（仅 spell）----
	var magic_mit: float = 0.0
	if input.attack_type == "spell":
		magic_mit = minf(input.total_magic_res_percent, MAX_MAGIC_MITIGATION)
		result.magic_mitigation = magic_mit
		post_mit = post_mit * (1.0 - magic_mit / 100.0)

	# ---- 阶段三：元素抗性（绝对减伤）----
	var elem_absorb: int = 0
	match input.element_type:
		"fire":
			elem_absorb = input.fire_res
		"ice":
			elem_absorb = input.ice_res
		"lightning":
			elem_absorb = input.lightning_res
		"poison":
			elem_absorb = input.poison_res
	result.element_absorbed = elem_absorb
	var post_elem: float = post_mit - float(elem_absorb)

	# ---- 阶段四：里程碑绝对减免 ----
	result.flat_absorbed = input.flat_reduce
	var post_milestone: float = post_elem - float(input.flat_reduce)

	# ---- 收口 ----
	result.final_damage = maxi(int(round(post_milestone)), 1)
	result.knockback_res = input.knockback_res
	return result

# ============================================================================
# 6. 便捷封装：从 Defender + ArmorSnapshot 直接结算
# ============================================================================

## 给定 base_damage、defender（旧平减模型兼容）和可选的 ArmorSnapshot，
## 返回最终伤害。如果 snap 为 null 则退化为仅 con 平减（向后兼容旧调用）。
static func resolve_damage(base_damage: float, defender, snap: ArmorSnapshot = null, attack_type: String = "melee", ignore_def_percent: float = 0.0, ignore_def: bool = false, flat_reduce: int = 0, element_type: String = "") -> ResolveResult:
	var input := ResolveInput.new()
	input.base_damage = base_damage
	input.attack_type = attack_type
	input.ignore_def_percent = ignore_def_percent
	input.ignore_def = ignore_def
	input.flat_reduce = flat_reduce
	input.element_type = element_type
	if defender != null:
		input.con = int(defender.con)
	if snap != null:
		input.total_phys_def = snap.total_phys_def
		input.total_magic_res_percent = snap.total_magic_res_percent
		input.fire_res = snap.total_fire_res
		input.ice_res = snap.total_ice_res
		input.lightning_res = snap.total_lightning_res
		input.poison_res = snap.total_poison_res
		input.knockback_res = snap.total_knockback_res
	return resolve(input)

# ============================================================================
# 7. 击退抗性结算
# ============================================================================

## 计算有效击退力（乘以 1 - knockback_res）。
static func resolve_knockback(base_knockback: float, snap: ArmorSnapshot) -> float:
	if snap == null:
		return base_knockback
	return base_knockback * (1.0 - snap.total_knockback_res)
