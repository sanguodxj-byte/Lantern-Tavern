class_name PlayerCombatRuntime
extends RefCounted

## 玩家战斗运行时计时/状态组件
## 从 player.gd 提取（与 CombatBuffComponent 同一模式）：RefCounted，由 Player 持有，
## 在 _physics_process / _process 中调用 tick 系列方法推进。
## 职责：
##   1. 近战攻击冷却（主手/副手独立计时，doc21 #3 急速 cd_reduce）
##   2. 轻弩装弹计时（doc21 reload_shot）
##   3. 二段跳计数（doc21 #4 air_dash）
##   4. 完美格挡·增伤 / 残影 buff（doc21 #6/#7）
##   5. 流派专精被动运行时状态（doc21 §一：蓄势/暴风骤雨/元素环/交错挥砍/奥术护盾）
## 不依赖场景树，可在单元测试中直接 new() 使用。

const SPE := preload("res://globals/combat/style_passive_effects.gd")

# ---- 近战攻击冷却 ----
const MELEE_CD_BASE := 0.45            # 单手近战基础冷却（秒）
const MELEE_CD_TWO_HAND_MULT := 1.5    # 双手武器冷却倍率
const MELEE_CD_DUAL_WIELD := 0.38      # 双持副手冷却（秒）
const CD_REDUCE_MULT := 0.85           # 急速被动：冷却 ×0.85
const MELEE_CHARGE_FULL_SEC := 0.8     # 蓄满所需按住时长（秒）
const MELEE_CHARGE_MAX_MULT := 2.0     # 蓄满伤害倍率（×2.0，doc21 #1）

# ---- 完美格挡 / 残影 ----
const PERFECT_BLOCK_BUFF_MULT := 1.5
const SIDESTEP_BUFF_MULT := 1.3
const SIDESTEP_BUFF_SEC := 1.5

# ---- 轻弩装弹 ----
const CROSSBOW_RELOAD_FALLBACK_SEC := 1.2   # 武器未声明 reload_time 时的兜底装弹时长

# ---- 二段跳 ----
const AIR_JUMPS_MAX := 1                     # 离地后可追加的跳跃次数（=1 即二段跳）
const AIR_JUMP_FORCE_MULT := 0.92           # 空中跳力度相对地面跳

# ---- 暴风骤雨 ----
const FLURRY_STORM_MAX_STACKS := 12          # 上限 ~12 层 = 60%
const FLURRY_STORM_WINDOW_SEC := 3.0         # 层数过期窗口

var melee_cd_primary: float = 0.0
var melee_cd_primary_max: float = 0.0
var melee_cd_secondary: float = 0.0
var melee_cd_secondary_max: float = 0.0

var crossbow_reload_remaining: float = 0.0
var crossbow_reload_total: float = 0.0

var air_jumps_used: int = 0

var perfect_block_buff_active: bool = false
var sidestep_buff_remaining: float = 0.0

# ---- 流派专精被动运行时状态（doc21 §一）----
var accumulated_damage: float = 0.0          # 蓄势：蓄力期间累积的伤害
var is_charging_twohand: bool = false        # 蓄势：是否正在双手蓄力
var flurry_storm_stacks: int = 0             # 暴风骤雨：当前连击层数
var flurry_storm_timer: float = 0.0          # 暴风骤雨：层数过期计时器
var elemental_ring_timer: float = 0.0        # 元素环：剩余持续时间
var dual_combo_last_hand: String = ""        # 交错挥砍：上次攻击手
var dual_combo_last_time: float = 0.0        # 交错挥砍：上次命中时间
var dual_combo_trigger_time: float = -99.0   # 交错挥砍：上次触发/断开时间（内置 CD）
var arcane_shield: int = 0                   # 奥术护盾：法术蓝量转化的护盾值（无限叠加）


# ============================================================================
# 每帧推进（由宿主调用）
# ============================================================================

## 物理帧推进：冷却/装弹/残影窗口倒计时；落地重置空中跳跃次数
func tick_physics(delta: float, on_floor: bool) -> void:
	melee_cd_primary = maxf(0.0, melee_cd_primary - delta)
	melee_cd_secondary = maxf(0.0, melee_cd_secondary - delta)
	crossbow_reload_remaining = maxf(0.0, crossbow_reload_remaining - delta)
	sidestep_buff_remaining = maxf(0.0, sidestep_buff_remaining - delta)
	if on_floor:
		air_jumps_used = 0

## 渲染帧推进：流派被动状态衰减（暴风骤雨层数过期、元素环倒计时）
func tick_style_passives(delta: float) -> void:
	if flurry_storm_stacks > 0:
		flurry_storm_timer -= delta
		if flurry_storm_timer <= 0.0:
			flurry_storm_stacks = 0
	if elemental_ring_timer > 0.0:
		elemental_ring_timer -= delta


# ============================================================================
# 近战攻击冷却
# ============================================================================

## 触发一次近战攻击冷却（hand: "primary" 主手 / "secondary" 双持副手）
func start_melee_cooldown(hand: String, two_handed: bool, has_cd_reduce: bool) -> void:
	var dur := compute_melee_cd_duration(hand, two_handed, has_cd_reduce)
	if hand == "secondary":
		melee_cd_secondary = dur
		melee_cd_secondary_max = dur
	else:
		melee_cd_primary = dur
		melee_cd_primary_max = dur

func compute_melee_cd_duration(hand: String, two_handed: bool, has_cd_reduce: bool) -> float:
	var dur := MELEE_CD_BASE
	if two_handed:
		dur = MELEE_CD_BASE * MELEE_CD_TWO_HAND_MULT
	elif hand == "secondary":
		dur = MELEE_CD_DUAL_WIELD
	return dur * get_melee_cd_multiplier(has_cd_reduce)

## 急速被动（cd_reduce）：冷却 ×0.85
## 暴风骤雨（unarmed_flurry_storm）：徒手连击每层 -5% CD（最高 -60%）
func get_melee_cd_multiplier(has_cd_reduce: bool) -> float:
	var mult: float = 1.0
	if has_cd_reduce:
		mult *= CD_REDUCE_MULT
	if flurry_storm_stacks > 0:
		mult *= SPE.apply_flurry_storm_cd_mult(flurry_storm_stacks)
	return mult

## 某手是否处于近战冷却中
func is_melee_on_cooldown(hand: String) -> bool:
	if hand == "secondary":
		return melee_cd_secondary > 0.0001
	return melee_cd_primary > 0.0001

## 某手冷却恢复比例 0..1（1=就绪）。无近战武器/远程时恒为 1
func get_melee_cd_fill(hand: String) -> float:
	if hand == "secondary":
		if melee_cd_secondary_max <= 0.0:
			return 1.0
		return clampf(1.0 - melee_cd_secondary / melee_cd_secondary_max, 0.0, 1.0)
	if melee_cd_primary_max <= 0.0:
		return 1.0
	return clampf(1.0 - melee_cd_primary / melee_cd_primary_max, 0.0, 1.0)


# ============================================================================
# 轻弩装弹
# ============================================================================

## 启动装弹计时（时长由宿主根据武器数据/被动计算后传入）
func start_crossbow_reload(sec: float) -> void:
	crossbow_reload_remaining = sec
	crossbow_reload_total = sec

func is_crossbow_reloading() -> bool:
	return crossbow_reload_remaining > 0.0001

func get_crossbow_reload_fill() -> float:
	if crossbow_reload_total <= 0.0:
		return 1.0
	return clampf(1.0 - crossbow_reload_remaining / crossbow_reload_total, 0.0, 1.0)


# ============================================================================
# 二段跳
# ============================================================================

func reset_air_jumps() -> void:
	air_jumps_used = 0

## 尝试消费一次空中跳跃次数；成功返回 true
func try_use_air_jump() -> bool:
	if air_jumps_used >= AIR_JUMPS_MAX:
		return false
	air_jumps_used += 1
	return true


# ============================================================================
# 完美格挡·增伤 / 残影 buff
# ============================================================================

func set_perfect_block_buff() -> void:
	perfect_block_buff_active = true

## 消费完美格挡·增伤 buff（仅一次）
func consume_perfect_block_buff() -> bool:
	if perfect_block_buff_active:
		perfect_block_buff_active = false
		return true
	return false

func set_sidestep_buff() -> void:
	sidestep_buff_remaining = SIDESTEP_BUFF_SEC

## 消费残影 buff：窗口内首次攻击命中时返回 true 并清零（仅一次）
func consume_sidestep_buff() -> bool:
	if sidestep_buff_remaining > 0.0001:
		sidestep_buff_remaining = 0.0
		return true
	return false


# ============================================================================
# 流派专精被动运行时（doc21 §一）
# ============================================================================

## 记录近战攻击命中：追踪交错挥砍连携与暴风骤雨层数
func record_melee_hit(hand: String, has_flurry_storm: bool) -> void:
	var current_time: float = Time.get_ticks_msec() / 1000.0
	if has_flurry_storm:
		flurry_storm_stacks = mini(flurry_storm_stacks + 1, FLURRY_STORM_MAX_STACKS)
		flurry_storm_timer = FLURRY_STORM_WINDOW_SEC
	dual_combo_last_hand = hand
	dual_combo_last_time = current_time

## 消耗蓄势累积的额外伤害：返回累积伤害值并清空池
func consume_accumulation_bonus() -> float:
	var bonus: float = accumulated_damage
	accumulated_damage = 0.0
	return SPE.get_accumulation_bonus(bonus)

func set_charging_twohand(charging: bool) -> void:
	is_charging_twohand = charging
	# 释放时不清空累积池（由 consume_accumulation_bonus 在结算时消费）

## 蓄势（TWO_HAND）：蓄力期间减伤 30%，减免部分累积到释放时叠加。
## 返回减免后的伤害；非蓄力状态原样返回。
func apply_charging_accumulation(final_damage: int) -> int:
	if not is_charging_twohand:
		return final_damage
	var reduced := SPE.apply_accumulation_damage_reduce(final_damage, true)
	accumulated_damage += float(final_damage - reduced)
	return reduced

## 奥术护盾（SPELL）：吸收伤害，返回吸收后的剩余伤害
func absorb_with_arcane_shield(final_damage: int) -> int:
	if arcane_shield <= 0:
		return final_damage
	var absorbed: int = mini(arcane_shield, final_damage)
	arcane_shield -= absorbed
	return maxi(final_damage - absorbed, 0)

## 触发元素环（由施法路径调用）
func trigger_elemental_ring() -> void:
	var duration: float = SPE.get_elemental_ring_duration()
	if duration > 0.0:
		elemental_ring_timer = duration

## 触发奥术护盾（消耗蓝量转化为护盾，无限叠加）
func trigger_arcane_barrier(mana_spent: int) -> void:
	var shield_val: int = SPE.compute_arcane_barrier_shield(mana_spent)
	if shield_val > 0:
		arcane_shield += shield_val

## 流派被动运行时状态字典（供 CombatBridge.build_player_attack 使用）
func get_style_context() -> Dictionary:
	var current_time: float = Time.get_ticks_msec() / 1000.0
	var is_offhand: bool = dual_combo_last_hand == "primary"
	var combo_active: bool = SPE.is_combo_active(
		dual_combo_last_time, current_time,
		dual_combo_last_hand, "secondary" if is_offhand else "primary"
	) and not SPE.is_combo_on_cooldown(dual_combo_trigger_time, current_time)
	return {
		"is_target_locked": false,  # 由准星/锁定逻辑设置（待 UI 层接入）
		"is_combo_active": combo_active,
		"is_offhand_attack": is_offhand,
		"is_weakpoint_hit": false,  # 由远程瞄准逻辑设置（待 UI 层接入）
		"accumulation_bonus": consume_accumulation_bonus() if accumulated_damage > 0.0 else 0.0,
	}
