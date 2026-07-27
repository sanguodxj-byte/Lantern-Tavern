class_name StylePassiveEffects
## 17 项流派专精被动效果实装（策划案《21-被动技能》§一 + 《31-流派与武器扩展技能设计方案》§一）。
## 纯静态函数，读取 SkillRuntime 机制被动状态，返回效果修正值或触发副作用。
## 由 CombatBridge / DamageResolver / Player 状态机各路径调用。
##
## 被动 ID 一览（17 项）：
##   单手 (ONE_HAND):     onehand_duelist, onehand_spellblade
##   持盾 (ONE_HAND_SHIELD): shield_bash, shield_refraction
##   双手 (TWO_HAND):     twohand_accumulation, twohand_heavy_swing
##   双持 (DUAL_WIELD):   dual_cross_strike, dual_cross_counter
##   徒手 (UNARMED):      unarmed_flurry_storm, unarmed_over_shoulder_slam,
##                         unarmed_grapple, unarmed_swift_kick, unarmed_arrow_break
##   远程 (RANGED):       ranged_weakpoint_sight, ranged_piercing
##   法系 (SPELL):        spell_arcane_barrier, spell_elemental_ring

# ============================================================================
# 0. SkillRuntime 查询辅助
# ============================================================================

## 获取 SkillRuntime autoload 实例（可能为 null，如联机 per-peer 场景）
static func _sr() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("SkillRuntime")

## 查询是否拥有某流派被动
static func has(id: String) -> bool:
	var sr: Node = _sr()
	if sr == null or not sr.has_method("has_mechanism_passive"):
		return false
	return sr.has_mechanism_passive(id)

# ============================================================================
# 1. 攻击路径修正（CombatBridge.build_player_attack 调用）
# ============================================================================

## 决斗者（ONE_HAND）：锁定目标后 +50% 攻击力、+50% 暴击率。
## is_target_locked: 是否已锁定当前目标（由玩家输入/准星逻辑判定）
## 返回 {"atk_bonus": float, "crit_bonus": float}
static func apply_duelist_buff(is_target_locked: bool) -> Dictionary:
	if has("passive_style_onehand_duelist") and is_target_locked:
		return {"atk_bonus": 50.0, "crit_bonus": 50.0}
	return {"atk_bonus": 0.0, "crit_bonus": 0.0}

## 交错挥砍（DUAL_WIELD）：连携激活时副手必暴 / 主手无视 50% 防御。
## combo_active: 连携是否激活（0.5s 内连续命中）
## is_offhand: 当前攻击是否为副手攻击
## 返回 {"force_crit": bool, "ignore_def_percent": float}
static func apply_dual_cross_strike(combo_active: bool, is_offhand: bool) -> Dictionary:
	if not has("passive_style_dual_cross_strike"):
		return {"force_crit": false, "ignore_def_percent": 0.0}
	if not combo_active:
		return {"force_crit": false, "ignore_def_percent": 0.0}
	if is_offhand:
		return {"force_crit": true, "ignore_def_percent": 0.0}
	else:
		return {"force_crit": false, "ignore_def_percent": 50.0}

## 看破弱点（RANGED）：弱点命中时必定暴击 ×2.0。
## is_weakpoint_hit: 是否命中弱点标记
## 返回 {"force_crit": bool, "crit_mult_override": float}
static func apply_weakpoint_sight(is_weakpoint_hit: bool) -> Dictionary:
	if has("passive_style_ranged_weakpoint_sight") and is_weakpoint_hit:
		return {"force_crit": true, "crit_mult_override": 2.0}
	return {"force_crit": false, "crit_mult_override": 0.0}

## 贯穿（RANGED）：弹道贯穿至多 5 个敌人，每贯穿一个递减 20%。
## pierce_index: 当前贯穿序号（0 = 第一个目标，1 = 第二个，...）
## 返回伤害倍率（0.0 = 无修正，返回 > 0 时为乘数）
static func apply_piercing_falloff(pierce_index: int) -> float:
	if not has("passive_style_ranged_piercing"):
		return 1.0
	if pierce_index < 0:
		return 1.0
	var max_pierce: int = 5
	if pierce_index >= max_pierce:
		return 0.0  # 超过最大贯穿数，无伤害
	# 每贯穿一个递减 20%：第 0 个 = 1.0，第 1 个 = 0.8，第 2 个 = 0.6 ...
	return 1.0 - 0.20 * float(pierce_index)

## 暴风骤雨（UNARMED）：每次交替攻击减少 5% 攻击冷却，最高 60%。
## stack_count: 当前连击层数
## 返回冷却乘数（1.0 = 无修正，0.4 = 最高减 60%）
static func apply_flurry_storm_cd_mult(stack_count: int) -> float:
	if not has("passive_style_unarmed_flurry_storm"):
		return 1.0
	var max_reduce: float = 0.60
	var per_hit: float = 0.05
	var total_reduce: float = minf(per_hit * float(stack_count), max_reduce)
	return 1.0 - total_reduce

## 过肩摔（UNARMED）：真实伤害计算。
## target_max_hp: 目标最大生命值
## is_boss: 是否为精英/Boss
## 返回真实伤害值
static func compute_over_shoulder_slam_damage(target_max_hp: int, is_boss: bool) -> int:
	if not has("passive_style_unarmed_over_shoulder_slam"):
		return 0
	var pct: float = 0.25 if is_boss else 1.0
	return maxi(1, int(round(float(target_max_hp) * pct)))

# ============================================================================
# 2. 防御路径修正（Player.receive_hit 调用）
# ============================================================================

## 蓄势（TWO_HAND）：蓄力期间受到的伤害降低 30%。
## is_charging: 是否正在蓄力
## 返回减免后的伤害
static func apply_accumulation_damage_reduce(damage: int, is_charging: bool) -> int:
	if has("passive_style_twohand_accumulation") and is_charging:
		return maxi(1, int(round(float(damage) * 0.70)))
	return damage

## 蓄势（TWO_HAND）：蓄力期间承受的伤害累积为释放时的追加伤害。
## 返回当前累积的额外伤害（由调用方在释放时叠加到攻击力上）
## accumulated_damage: 传入已累积的伤害池
static func get_accumulation_bonus(accumulated_damage: float) -> float:
	if not has("passive_style_twohand_accumulation"):
		return 0.0
	return accumulated_damage

## 折射（ONE_HAND_SHIELD）：成功格挡远程/法系攻击时 100% 反射。
## is_ranged_or_spell: 攻击是否为远程或法系
## is_blocking: 是否成功格挡
## 返回反射比例（0.0 = 不反射，1.0 = 100% 反射）
static func try_reflect_attack(is_ranged_or_spell: bool, is_blocking: bool) -> float:
	if has("passive_style_shield_refraction") and is_ranged_or_spell and is_blocking:
		return 1.0
	return 0.0

## 折射（ONE_HAND_SHIELD）：格挡远程/法系时盾牌耐久消耗加倍。
## 返回耐久消耗倍率
static func get_refraction_durability_mult() -> float:
	if has("passive_style_shield_refraction"):
		return 2.0
	return 1.0

## 奥术护盾（SPELL）：施法消耗蓝量转化为等额护盾。
## mana_spent: 本次施法消耗的蓝量
## 返回应获得的护盾值
static func compute_arcane_barrier_shield(mana_spent: int) -> int:
	if not has("passive_style_spell_arcane_barrier"):
		return 0
	return maxi(0, mana_spent)

# ============================================================================
# 3. 状态机 / 输入驱动查询
# ============================================================================

## 奥法之剑（ONE_HAND）：满蓄力攻击释放时自动释放选中魔法。
## 返回是否应触发魔法释放
static func should_spellblade_cast(is_full_charge: bool) -> bool:
	return has("passive_style_onehand_spellblade") and is_full_charge

## 盾击（ONE_HAND_SHIELD）：格挡中按左键触发盾击。
## 返回是否应触发盾击
static func should_shield_bash(is_blocking: bool, left_click_pressed: bool) -> bool:
	return has("passive_style_shield_bash") and is_blocking and left_click_pressed

## 盾击（ONE_HAND_SHIELD）：盾击命中后压制窗口判定。
## 返回是否触发压制（敌方无法行动且防御为 0）
static func should_shield_bash_suppress(time_since_enemy_attack: float) -> bool:
	if not has("passive_style_shield_bash"):
		return false
	return time_since_enemy_attack <= 0.3

## 重型挥舞（TWO_HAND）：替换基础攻击动作为大范围横扫。
## 返回横扫参数
static func get_heavy_swing_params() -> Dictionary:
	if has("passive_style_twohand_heavy_swing"):
		return {"arc_angle_deg": 120.0, "radius_mult": 1.3}
	return {"arc_angle_deg": 0.0, "radius_mult": 1.0}

## 十字返（DUAL_WIELD）：受到敌人近战攻击前摇时同时按左右键触发。
## 返回是否应触发十字返
static func should_dual_cross_counter(is_enemy_windup: bool, both_keys_pressed: bool) -> bool:
	return has("passive_style_dual_cross_counter") and is_enemy_windup and both_keys_pressed

## 擒拿（UNARMED）：左右键同时按下 + 目标 HP ≤ 30% → 执行投掷。
## 返回是否应触发擒拿
static func should_grapple(target_hp_pct: float, both_keys_pressed: bool) -> bool:
	return has("passive_style_unarmed_grapple") and both_keys_pressed and target_hp_pct <= 30.0

## 迅猛踢击（UNARMED）：踢击视为普通攻击。
## 返回是否启用
static func has_swift_kick() -> bool:
	return has("passive_style_unarmed_swift_kick")

## 折箭术（UNARMED）：徒手攻击命中投射物时偏转。
## 返回偏转角度（度），0 = 未启用
static func try_arrow_break_deflect() -> float:
	if not has("passive_style_unarmed_arrow_break"):
		return 0.0
	# ±60°~90° 随机
	var sign_val: float = 1.0 if randf() < 0.5 else -1.0
	return sign_val * randf_range(60.0, 90.0)

## 元素环（SPELL）：施法后生成跟随元素环。
## 返回持续秒数，0 = 未启用
static func get_elemental_ring_duration() -> float:
	if has("passive_style_spell_elemental_ring"):
		return 5.0
	return 0.0

# ============================================================================
# 4. 连携状态管理（双持交错挥砍专用）
# ============================================================================

## 交错挥砍连携状态：记录上次攻击的手和时间。
## 由 Player 攻击状态机调用：
##   - 攻击命中时调用 record_combo_hit(hand, time)
##   - 查询连携是否激活时调用 is_combo_active(current_time, is_offhand)
##   - 攻击落空时调用 break_combo()

static func is_combo_active(last_hit_time: float, current_time: float, last_hand: String, current_hand: String) -> bool:
	if not has("passive_style_dual_cross_strike"):
		return false
	# 必须是不同手交替
	if last_hand == current_hand or last_hand == "":
		return false
	# 0.5 秒窗口内
	if current_time - last_hit_time > 0.5:
		return false
	return true

## 交错挥砍内置 CD：触发或断开后 3 秒内无法再次触发。
## 返回是否在 CD 内
static func is_combo_on_cooldown(last_trigger_time: float, current_time: float) -> bool:
	if not has("passive_style_dual_cross_strike"):
		return false
	return current_time - last_trigger_time < 3.0
