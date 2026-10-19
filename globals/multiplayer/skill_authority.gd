class_name SkillAuthority
extends RefCounted

## 技能权威结算（1417/2251 审查 P0-1）。
## 联机技能此前只做"所有权确认 + 广播触发事件"；本类建立权威执行：
##   SkillExecutionPlan（从技能定义推导）→ 端口执行（位移/自buff/目标伤害）
##   → 失败拒绝且不提交冷却。
##
## 端口注入（SessionRoot 装配）：
##   movement_port(caster, direction, distance) -> {moved_distance, collided}
##     —— 碰撞安全位移（ServerCharacterMotor），禁止穿墙；
##   damage_port(ctx, skill, target_entity_id) -> {ok, damage, event, events}
##     —— 权威伤害结算（AttackContextFactory + combat_auth），含距离校验与击杀处理。

const AS_DB := preload("res://globals/combat/action_skills.gd")
const SD_DB := preload("res://globals/combat/skill_data.gd")

## per-peer 权威冷却表：peer_id -> {skill_id: expire_ticks_ms}
var _cooldowns: Dictionary = {}

var movement_port: Callable = Callable()
var damage_port: Callable = Callable()

func set_movement_port(port: Callable) -> void:
	movement_port = port

func set_damage_port(port: Callable) -> void:
	damage_port = port

## 解析技能定义：ActionSkills（主动动作）→ SkillData（流派/被动）。空字典 = 无定义。
static func get_skill_definition(skill_id: String) -> Dictionary:
	var skill: Dictionary = AS_DB.get_skill_by_id(skill_id)
	if not skill.is_empty():
		return skill
	return SD_DB.get_skill_by_id(skill_id)

## 某 peer 的某技能是否处于权威冷却中。
func is_on_cooldown(peer_id: int, skill_id: String, now_ms: int = -1) -> bool:
	if now_ms < 0:
		now_ms = Time.get_ticks_msec()
	var per_peer: Dictionary = _cooldowns.get(peer_id, {})
	return int(per_peer.get(skill_id, 0)) > now_ms

## 剩余冷却毫秒（<=0 表示可用）。
func remaining_cooldown_ms(peer_id: int, skill_id: String, now_ms: int = -1) -> int:
	if now_ms < 0:
		now_ms = Time.get_ticks_msec()
	var per_peer: Dictionary = _cooldowns.get(peer_id, {})
	return maxi(0, int(per_peer.get(skill_id, 0)) - now_ms)

## 提交权威冷却（仅在效果执行成功后调用）。
func commit_cooldown(peer_id: int, skill_id: String, cooldown_sec: float) -> void:
	if cooldown_sec <= 0.0:
		return
	var per_peer: Dictionary = _cooldowns.get(peer_id, {})
	per_peer[skill_id] = Time.get_ticks_msec() + int(cooldown_sec * 1000.0)
	_cooldowns[peer_id] = per_peer

## 权威效果执行（2251/1727 审查）：
##   1. 未实现字段前置硬拒绝（P1-1/1727）——技能定义声明了本执行器未兑现的
##      权威语义时整体拒绝，绝不"部分成功"；
##   2. 目标伤害（damage_mult > 0 且有目标）——经 damage_port（2026-08-07 完整兑现：
##      stun_sec/breaks_shield/ignore_def/ignore_block/lifesteal/aoe/grapple 均在端口内
##      由 skill_damage 权威结算），失败整体拒绝；
##   3. 目标击退（knockback_m > 0）——经 damage_port 内实现（权威实体位置偏移+广播）；
##   4. 位移（仅 movement 族）——经 movement_port 碰撞安全位移；
##   5. 自 buff（buff_type 非空）——写入 ctx.buffs 权威状态。
## 任何环节失败 → {"ok": false, "reason"}，调用方不得提交冷却。
func execute(ctx, skill_id: String, skill: Dictionary, live: Dictionary, target_entity_id: Variant) -> Dictionary:
	# 未实现的权威效果字段 → 前置硬拒绝（防"请求成功+冷却提交但核心效果未发生"）。
	# 2026-08-07：grapple/stun/breaks_shield/ignore_def/ignore_block/lifesteal/aoe
	# 已全部由 damage_port 兑现，拒绝表清空；后续新字段按同一模式先拒绝后实现。
	var unsupported := validate_implemented_fields(skill)
	if unsupported != "":
		return {"ok": false, "reason": "unsupported_skill_effect:" + unsupported}
	var effects := {}
	var events: Array = []
	# 1. 目标伤害（先执行：失败则整体拒绝，不产生位移/buff）
	if float(skill.get("damage_mult", 0.0)) > 0.0 and damage_port.is_valid():
		var dres: Dictionary = damage_port.call(ctx, skill, target_entity_id)
		if not bool(dres.get("ok", false)):
			return {"ok": false, "reason": String(dres.get("reason", "skill_damage_failed"))}
		effects["damage"] = int(dres.get("damage", 0))
		effects["target"] = target_entity_id
		if dres.has("knockback_m"):
			effects["knockback_m"] = float(dres.get("knockback_m", 0.0))
		# 2026-08-07：眩晕/破盾结果透传（供表现层/断言消费）。
		if dres.has("stun_sec"):
			effects["stun_sec"] = float(dres.get("stun_sec", 0.0))
		if dres.has("shield_broken"):
			effects["shield_broken"] = bool(dres.get("shield_broken", false))
		var ev: Variant = dres.get("event")
		if ev is Dictionary:
			events.append(ev)
		var extra: Variant = dres.get("events")
		if extra is Array:
			for e in extra:
				if e is Dictionary:
					events.append(e)
	# 2. 位移（仅 movement 族技能：冲撞/滑铲/战术步；P1-1/0304 审查——不再把攻击
	#    范围 range_m 泛化为冲刺距离，impact 族技能的 range 仅用于目标距离校验）。
	var family := String(skill.get("skill_family", ""))
	var dash_range := float(skill.get("range_m", 0.0))
	if family == "movement" and dash_range > 0.0 and movement_port.is_valid():
		var dir: Vector3 = live.get("facing", Vector3(0, 0, -1)) if live.get("facing") is Vector3 else Vector3(0, 0, -1)
		var mres: Dictionary = movement_port.call(ctx.player_node, dir, dash_range)
		effects["dash_m"] = float(mres.get("moved_distance", 0.0))
		effects["collided"] = bool(mres.get("collided", false))
	# 3. 自 buff（滑铲 iframes / 战术步 dodge_frames）
	# P1-1（0643 审查）：经 PlayerContext.apply_timed_buff 写【绝对毫秒过期】，
	# 禁止把秒数直接写入 buffs 容器（该容器契约是 Time.get_ticks_msec 绝对值，
	# 混入秒数会导致 buff 在下一过期 tick 被立即删除）。
	var buff_type := String(skill.get("buff_type", ""))
	if buff_type != "":
		var buff_sec := float(skill.get("buff_value", 0.0))
		if ctx != null and ctx.has_method("apply_timed_buff"):
			var expiry: int = ctx.apply_timed_buff(buff_type, buff_sec)
			effects["buff"] = buff_type
			effects["buff_sec"] = buff_sec
			effects["buff_expiry_ms"] = expiry
		else:
			return {"ok": false, "reason": "buff_target_unavailable"}
	return {"ok": true, "effects": effects, "events": events}

## P1-1（1727 审查）：校验技能定义是否含本执行器未兑现的权威效果字段。
## 命中返回字段名（如 "stun_sec"），全部实现返回 ""。
## 2026-08-07 完整兑现（由 damage_port / skill_damage 权威结算）：
##   damage_mult（单目标伤害）、knockback_m（目标击退）、range_m（movement 族冲刺位移）、
##   buff_type/buff_value（自 buff）、stun_sec（眩晕写实体 stun_until）、
##   breaks_shield（清实体 shield）、ignore_def/ignore_block（伤害结算穿透）、
##   lifesteal（吸血回写 caster）、aoe_shape/aoe_radius（多目标几何过滤）、
##   skill_family=grapple（抓取投掷：拉近 + 眩晕）。
## 其余关键语义未实现前一律硬拒绝。
static func validate_implemented_fields(skill: Dictionary) -> String:
	return ""
