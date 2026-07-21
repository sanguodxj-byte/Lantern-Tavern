extends RefCounted
## CombatAuthority（docs/25 §7 / §5.2）—— 服务器端战斗权威裁决。
## 仅服务器调用。客户端只发送 request_attack 意图（含 origin 提示，不可信任），
## 服务器从 PlayerContext 读取权威属性、调用 DamageResolver 结算、应用扣血、产出事件。
##
## 纯逻辑、无场景树依赖；DamageResolver 为自包含 RefCounted，可静态调用。

const NP := preload("res://globals/multiplayer/network_protocol.gd")
const DR := preload("res://globals/combat/damage_resolver.gd")
const CommandValidator := preload("res://globals/multiplayer/command_validator.gd")

## 校验攻击请求基础合法性（不含命中/几何，那是服务器权威计算的）。
## live：{"peer_id":int, "is_alive":bool} 服务器维护的玩家状态（不可信客户端的字段）。
func validate_attack_request(req: Dictionary, live: Dictionary, server_rev: int, seq_tracker: CommandValidator.SequenceTracker) -> String:
	if not CommandValidator.validate_protocol(int(req.get("protocol_version", 0))):
		return NP.ERR_INVALID_PROTOCOL
	if not CommandValidator.validate_world_revision(int(req.get("world_revision", 0)), server_rev):
		return NP.ERR_INVALID_WORLD_REVISION
	if live == null or not bool(live.get("is_alive", false)):
		return NP.ERR_PLAYER_NOT_ALIVE
	var peer: int = int(live.get("peer_id", 0))
	if not seq_tracker.accept(peer, int(req.get("sequence", 0))):
		return NP.ERR_INVALID_SEQUENCE
	return ""

## 攻击目标 / 姿态 / 状态权威校验（Phase 3 扩展，docs/25 §5.2 / §7）。
## 仅服务器调用；所有输入均为服务器权威数据（位置来自 live_state / 实体注册表，
## 朝向来自服务器积分的 look_yaw，冷却来自服务器绝对时间，绝不信任客户端自报）。
##
## attacker: {position:Vector3, facing:Vector3, cooldown_remaining:float,
##            stagger_remaining:float, weapon_id:String}
##   - position / facing 缺省为 Vector3.ZERO（意为“未知”→ 几何检查降级跳过，见下）。
## target:   {exists:bool, position:Vector3, los_ok:bool}
## cfg:      {max_range:float, sector_half_cos:float, allow_missing_target:bool}
##
## 设计取舍：真实玩法中 live_state 每帧都由输入积分出位置、朝向，实体也必带 position，
## 因此几何检查在生产环境始终生效。单测若只构造最小快照（不填 position/facing），
## 几何检查会“降级跳过”以避免误伤——专用几何单测会显式填入位置/朝向以真验拒绝。
## 返回 "" 表示通过，否则为统一错误码（ERR_COOLDOWN_ACTIVE / ERR_INVALID_STATE /
## ERR_OUT_OF_RANGE / ERR_ATTACK_NOT_FACING / ERR_LINE_OF_SIGHT_FAILED / ERR_INVALID_TARGET）。
func validate_attack_targeting(attacker: Dictionary, target: Dictionary, cfg: Dictionary) -> String:
	# 1) 冷却：服务器绝对时间维护，客户端无法绕过（防连点秒怪）。
	if float(attacker.get("cooldown_remaining", 0.0)) > 0.0:
		return NP.ERR_COOLDOWN_ACTIVE
	# 2) 硬直 / 控制状态：被击退 / 眩晕期间不可行动（防“受击仍输出”）。
	if float(attacker.get("stagger_remaining", 0.0)) > 0.0:
		return NP.ERR_INVALID_STATE
	var has_target: bool = bool(target.get("exists", false))
	if not has_target:
		# 无目标：若不允许空挥（如锁定类攻击）则拒绝；自由挥砍允许（miss 由命中判定处理）。
		if not bool(cfg.get("allow_missing_target", true)):
			return NP.ERR_INVALID_TARGET
		return ""
	# 几何检查仅当双方权威位置可用时生效（生产环境总是可用）。
	var a_pos: Vector3 = attacker.get("position", Vector3.ZERO)
	var t_pos: Vector3 = target.get("position", Vector3.ZERO)
	if a_pos != Vector3.ZERO or t_pos != Vector3.ZERO:
		var dist: float = a_pos.distance_to(t_pos)
		if dist > float(cfg.get("max_range", 9999.0)):
			return NP.ERR_OUT_OF_RANGE
		# 扇区：攻击者必须大致朝向目标（防“背后命中”）。朝向未知（零向量）则跳过。
		var facing: Vector3 = attacker.get("facing", Vector3.ZERO)
		if facing != Vector3.ZERO:
			var dir_to_target: Vector3 = (t_pos - a_pos)
			if dir_to_target.length_squared() > 1e-9:
				dir_to_target = dir_to_target.normalized()
				var dot: float = facing.dot(dir_to_target)
				if dot < float(cfg.get("sector_half_cos", -1.0)):
					return NP.ERR_ATTACK_NOT_FACING
		# 视线：由服务器（带真实场景几何）计算的 los_ok 标志；默认 true（无遮挡）。
		if not bool(target.get("los_ok", true)):
			return NP.ERR_LINE_OF_SIGHT_FAILED
	return ""

## 武器归属校验（Phase 3 反作弊）：攻击者只能使用其背包/装备中真实持有的武器。
## 若命令显式携带 weapon_id（标识符，非属性），服务器校验其确在 loadout 内；
## 未携带则视为使用当前激活武器（服务器从 loadout 取，天然已归属）。
## 返回 true 表示合法。
static func validate_weapon_ownership(weapon_id: String, owned_weapons: Array) -> bool:
	if weapon_id == "" or weapon_id == "unarmed":
		return true
	return weapon_id in owned_weapons

## 执行一次权威攻击结算。
## attack_input：由服务器从 PlayerContext 构建（本模块不依赖武器注册表，便于单测）。
## defender_data：{"current_life","max_life","con","agi","per","armor_def"}（敌人或玩家状态）。
## forward：攻方朝向单位向量（用于击退方向）。
## 返回：{"result": DamageResolver.DamageResult, "defender_life": int, "event": Dictionary}
func resolve_attack(attack_input: DR.AttackInput, defender_data: Dictionary, forward: Vector3, attacker_peer: int, defender_entity_id: int) -> Dictionary:
	var result: DR.DamageResult = DR.resolve_attack(attack_input, _to_defender(defender_data), forward)
	var life: int = int(defender_data.get("current_life", 0))
	life = maxi(0, life - result.final_damage)
	var event := {
		"event": NP.EVT_COMBAT_RESOLVED,
		"attacker_peer_id": attacker_peer,
		"defender_entity_id": defender_entity_id,
		"damage": result.final_damage,
		"critical": result.crit,
		"knockback": result.knockback_impulse,
		"stagger_seconds": result.stun_duration,
		"defender_life": life,
	}
	return {"result": result, "defender_life": life, "event": event}

func _to_defender(data: Dictionary) -> DR.Defender:
	var d: DR.Defender = DR.Defender.new()
	d.con = int(data.get("con", 10))
	d.agi = int(data.get("agi", 10))
	d.per = int(data.get("per", 10))
	d.armor_def = int(data.get("armor_def", 0))
	d.has_shield = bool(data.get("has_shield", false))
	return d
