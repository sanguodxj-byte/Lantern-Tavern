extends RefCounted

## A2（架构审查 P0）：服务器权威敌人攻击模拟（EnemyCombatAuthority）。
## 纯逻辑、无场景依赖（与 CombatAuthority 同构），由 SessionRoot.tick_enemy_combat 委托调用。
##
## 修复目标：旧实现把攻击参数硬编码在会话层（ENEMY_ATTACK_INTERVAL/RANGE/DAMAGE 常量），
## 所有敌人共用同一射程/间隔/伤害，且无视线检查。本权威类把参数来源收敛到：
##   实体 data.attack_range/attack_interval/attack_damage（最优先）
##   > data.attack_profile.{...}（实体可携带整组攻击配置）
##   > 构造注入的可配置 profile（SessionRoot 默认 profile = 旧常量语义）
##   > 本类默认值（仅兜底，绝不再在 session_root 出现裸常量）。
##
## 视线遮挡：注入 ray_query 端口（func(from: Vector3, to: Vector3) -> Dictionary）。
## 生产由 SessionRoot 接线 PhysicsDirectSpaceState3D.intersect_ray（mask 用视野遮挡层）；
## 测试注入 stub，无物理世界依赖。射线命中字典【非空】即判定无视线 → 不攻击。
## 未接线 ray_query 时视为无遮挡（保持旧行为，仅纯逻辑最小调用路径）。
##
## 攻击节奏：每敌人独立 next_attack_at（实体 data 字段，服务器时间秒）。
## decide_attack 为【纯函数】：不修改传入 data，返回决策含 next_attack_at，
## 由调用方（SessionRoot）把节奏写回实体 data——测试可直接断言节奏值。

# 默认 profile（与旧会话常量一致的兜底语义；实体 data / 注入 profile 可覆盖）。
const DEFAULT_ATTACK_RANGE := 1.8
const DEFAULT_ATTACK_INTERVAL := 1.5
const DEFAULT_ATTACK_DAMAGE := 8

## 可配置 profile 回退：{"attack_range": float, "attack_interval": float, "attack_damage": int}。
## 构造注入；优先级低于实体 data 的 attack_* / attack_profile。
var _profile: Dictionary

## 视线查询端口：func(from: Vector3, to: Vector3) -> Dictionary（空字典 = 无遮挡）。
## SessionRoot 生产接线真实 intersect_ray；测试注入 stub。未接线视为无遮挡。
var ray_query: Callable = Callable()

func _init(profile: Dictionary = {}) -> void:
	_profile = profile.duplicate()

# ---------------------------------------------------------------------------
# 攻击参数派生（实体 data > 实体 attack_profile > 注入 profile > 默认）
# ---------------------------------------------------------------------------

func _read_param_float(data: Dictionary, key: String, fallback: float) -> float:
	if data.has(key):
		return float(data[key])
	var profile: Variant = data.get("attack_profile", null)
	if profile is Dictionary and (profile as Dictionary).has(key):
		return float((profile as Dictionary)[key])
	if _profile.has(key):
		return float(_profile[key])
	return fallback

func _read_param_int(data: Dictionary, key: String, fallback: int) -> int:
	if data.has(key):
		return int(data[key])
	var profile: Variant = data.get("attack_profile", null)
	if profile is Dictionary and (profile as Dictionary).has(key):
		return int((profile as Dictionary)[key])
	if _profile.has(key):
		return int(_profile[key])
	return fallback

## 敌人攻击射程（米）。
func attack_range_for(data: Dictionary) -> float:
	return _read_param_float(data, "attack_range", DEFAULT_ATTACK_RANGE)

## 敌人攻击间隔（秒）——决定 next_attack_at = now + interval。
func attack_interval_for(data: Dictionary) -> float:
	return _read_param_float(data, "attack_interval", DEFAULT_ATTACK_INTERVAL)

## 敌人单次攻击伤害。
func attack_damage_for(data: Dictionary) -> int:
	return _read_param_int(data, "attack_damage", DEFAULT_ATTACK_DAMAGE)

# ---------------------------------------------------------------------------
# 目标选择 / 攻击决策
# ---------------------------------------------------------------------------

## 在攻击射程内选择最近存活玩家。players 每项 {peer_id:int, position:Vector3, is_alive:bool}。
## 返回 peer_id；无目标返回 0。与旧实现一致：dist <= range 即视为可命中。
func select_target(data: Dictionary, players: Array) -> int:
	var epos: Vector3 = data.get("position", Vector3.ZERO)
	var atk_range: float = attack_range_for(data)
	var best_peer: int = 0
	var best_dist: float = atk_range
	for entry in players:
		if not (entry is Dictionary):
			continue
		var entry_dict: Dictionary = entry
		if not bool(entry_dict.get("is_alive", false)):
			continue
		var ppos: Vector3 = entry_dict.get("position", Vector3.ZERO)
		var dist: float = epos.distance_to(ppos)
		if dist <= best_dist:
			best_dist = dist
			best_peer = int(entry_dict.get("peer_id", 0))
	return best_peer

## 对单个敌人做一次攻击决策（纯函数，不修改 data）。
##   * 未到 next_attack_at → 不攻击；
##   * 射程内无存活玩家 → 不攻击；
##   * 视线被遮挡 → 不攻击；
##   * 否则攻击，返回 {"attack":true, "target_peer":int, "damage":int, "next_attack_at":float}。
## 调用方负责把 next_attack_at 写回实体 data（SessionRoot.tick_enemy_combat 每 tick 写回）。
func decide_attack(data: Dictionary, players: Array, now: float) -> Dictionary:
	var next_at: float = float(data.get("next_attack_at", 0.0))
	if next_at > now:
		return {"attack": false, "target_peer": 0, "damage": 0, "next_attack_at": next_at}
	var target_peer: int = select_target(data, players)
	if target_peer == 0:
		return {"attack": false, "target_peer": 0, "damage": 0, "next_attack_at": next_at}
	var epos: Vector3 = data.get("position", Vector3.ZERO)
	var ppos: Vector3 = _player_position(players, target_peer)
	if not _has_line_of_sight(epos, ppos):
		return {"attack": false, "target_peer": 0, "damage": 0, "next_attack_at": next_at}
	var interval: float = attack_interval_for(data)
	return {
		"attack": true,
		"target_peer": target_peer,
		"damage": attack_damage_for(data),
		"next_attack_at": now + interval,
	}

## 从玩家快照数组取指定 peer 的位置（供视线检查）。
func _player_position(players: Array, peer_id: int) -> Vector3:
	for entry in players:
		if not (entry is Dictionary):
			continue
		var entry_dict: Dictionary = entry
		if int(entry_dict.get("peer_id", 0)) == peer_id:
			return entry_dict.get("position", Vector3.ZERO)
	return Vector3.ZERO

## 视线检查：ray_query 命中字典为空（或无遮挡）→ true。未接线 ray_query → true（保守保持旧行为）。
func _has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	if not ray_query.is_valid():
		return true
	var hit: Variant = ray_query.call(from, to)
	if hit == null:
		return true
	if hit is Dictionary:
		return (hit as Dictionary).is_empty()
	return true
