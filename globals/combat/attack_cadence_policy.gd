class_name AttackCadencePolicy
extends RefCounted

## 攻击节奏政策（AttackCadencePolicy）—— 攻击冷却的唯一权威公式（架构审查 P0-3）。
##
## 背景：攻击冷却曾经至少三套——CombatEngine.compute_attack_interval（1/style/dex）、
## PlayerCombatRuntime（0.45s 基础/双手 1.5×/副手 0.38s/急速 0.85×/暴风骤雨）、
## SessionRoot 固定 SERVER_ATTACK_CD=0.4s、客户端发送节流 0.5s。
## 结果：HUD、动画、本地输入门与服务器裁决不同步。
##
## 本政策以 PlayerCombatRuntime 已裁定的公式为唯一真相（服务器/单机/HUD 共用）：
##   基础 0.45s ×（双手 1.5 | 双持副手 0.38）× 急速 0.85 × 暴风骤雨连击乘数
## 接受 AttackContext（流派/手位派生），返回权威冷却秒数。客户端 0.5s 发送节流仅防洪，
## 不参与玩法（见 client_command_driver 注释）。

const DR := preload("res://globals/combat/damage_resolver.gd")
const SPE := preload("res://globals/combat/style_passive_effects.gd")

# ---- 常量（与 PlayerCombatRuntime 已裁定公式一致）----
const MELEE_CD_BASE := 0.45            # 单手近战基础冷却（秒）
const MELEE_CD_TWO_HAND_MULT := 1.5    # 双手武器冷却倍率
const MELEE_CD_DUAL_WIELD := 0.38      # 双持副手冷却（秒）
const CD_REDUCE_MULT := 0.85           # 急速被动：冷却 ×0.85

## 权威攻击冷却（秒）。
## context: AttackContext（主/副手与流派由此派生）；null 时按默认单手主手处理。
## has_cd_reduce: 急速被动（cd_reduce）是否生效（单机由玩家被动查询；联机服务端
##   暂无 per-peer 被动状态时为 false——见 SessionRoot 调用处）。
## flurry_storm_stacks: 暴风骤雨连击层数（联机服务端无连击栈，传 0）。
static func compute_attack_cd(context: Variant = null, has_cd_reduce: bool = false, flurry_storm_stacks: int = 0) -> float:
	var style: int = context.style() if context != null else DR.Style.ONE_HAND
	var hand: String = context.hand if context != null else "primary"
	var dur := MELEE_CD_BASE
	if style == DR.Style.TWO_HAND:
		dur = MELEE_CD_BASE * MELEE_CD_TWO_HAND_MULT
	elif style == DR.Style.DUAL_WIELD and hand == "secondary":
		dur = MELEE_CD_DUAL_WIELD
	return dur * get_cd_multiplier(has_cd_reduce, flurry_storm_stacks)

## 冷却乘数：急速被动 ×0.85、暴风骤雨连击每层 -5%（最高 -60%）。
static func get_cd_multiplier(has_cd_reduce: bool, flurry_storm_stacks: int) -> float:
	var mult := 1.0
	if has_cd_reduce:
		mult *= CD_REDUCE_MULT
	if flurry_storm_stacks > 0:
		mult *= SPE.apply_flurry_storm_cd_mult(flurry_storm_stacks)
	return mult
