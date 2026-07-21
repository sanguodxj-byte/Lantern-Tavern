extends Node
## SessionRoot —— 多人会话根节点 / 权威编排器（Phase 3 实现版）。
##
## 职责（docs/25 §3.2）：聚合 PlayerRegistry + WorldState + CommandRouter + 各权威系统，
## 处理版本握手、peer→上下文注册、客户端命令分发、快照/事件下发、断线清理。
## 本身不计算具体伤害/库存，而是调度子权威系统（CombatAuthority / InteractionAuthority /
## LootAuthority）。
##
## 不声明 class_name，规避 headless 类注册 / .uid 问题；经 preload 访问：
##   const SR := preload("res://globals/multiplayer/session_root.gd")

const NP := preload("res://globals/multiplayer/network_protocol.gd")
const PlayerRegistryClass := preload("res://globals/multiplayer/player_registry.gd")
const WorldStateClass := preload("res://globals/multiplayer/world_state.gd")
const CommandRouterClass := preload("res://globals/multiplayer/command_router.gd")
const CommandValidatorClass := preload("res://globals/multiplayer/command_validator.gd")
const PlayerContextClass := preload("res://globals/core/player_context.gd")
const AttrPanelClass := preload("res://globals/combat/attr_panel.gd")
const SkillRuntimeClass := preload("res://globals/combat/skill_runtime.gd")
const ExpeditionInventoryClass := preload("res://globals/core/state/expedition_inventory.gd")
const EquipmentLoadoutClass := preload("res://globals/core/state/equipment_loadout.gd")
const InteractionAuthorityClass := preload("res://globals/multiplayer/interaction_authority.gd")
const CombatAuthorityClass := preload("res://globals/multiplayer/combat_authority.gd")
const LootAuthorityClass := preload("res://globals/multiplayer/loot_authority.gd")
const MovementAuthorityClass := preload("res://globals/multiplayer/movement_authority.gd")
const EntitySyncAuthorityClass := preload("res://globals/multiplayer/entity_sync_authority.gd")
const DungeonAuthorityClass := preload("res://globals/multiplayer/dungeon_authority.gd")
const ConnectionAuthorityClass := preload("res://globals/multiplayer/connection_authority.gd")
const SaveAuthorityClass := preload("res://globals/multiplayer/save_authority.gd")
const DamageResolverClass := preload("res://globals/combat/damage_resolver.gd")

signal session_event(event: Dictionary)
signal player_registered(peer_id: int)
signal player_spawned(peer_id: int)
signal player_unregistered(peer_id: int)

var registry: PlayerRegistryClass
var world: WorldStateClass
var router: CommandRouterClass
var validator: CommandValidatorClass
var is_server: bool = false
# 服务器时钟（秒）。由 NetworkManager 每帧/每 tick 更新；单测中直接赋值以确定性验证重连时效。
var current_time: float = 0.0

# 服务器维护的玩家权威状态（不可信客户端的字段）：peer_id -> {peer_id,is_alive,position}
var _live_state: Dictionary
# 服务器权威实体注册表（敌人/掉落/宝箱/门...）：entity_id -> data
var _entities: Dictionary
# ctx 实例 id -> peer_id 反向索引（handler 只能拿到 ctx，需反查 peer_id）
var _ctx_peer: Dictionary
var _seq_tracker: CommandValidatorClass.SequenceTracker
# 掉落实体 id 自增计数器（服务器权威分配，避免与敌人 id 1001/1002 冲突）。
var _loot_seq: int = 5000
# 出征结算基线：peer_id -> 进地牢时该玩家单人存档摘要（ExpeditionInventory.to_dict）。
# 用于出征结算时只回写【本次净获得】（当前背包 - 基线），避免把已带入的地牢物资重复累加，
# 也不丢失玩家单人存档中既有的、未带入地牢的符文/装备（基线/结算都不含它们）。
var _inventory_baseline: Dictionary

# 玩家权威出生点：地牢生成后由 DungeonSessionController 经唯一算法
# DungeonLayout.calc_player_spawn_pos() 写入（与敌人放置 base 同源）。
# handle_spawn_request 据此签发玩家权威起始位置，确保与敌人处于同一地牢坐标系
# （否则玩家出生在原点、敌人在地牢出生点附近，射程/朝向校验将永远拒掉合法攻击）。
# 默认 Vector3.ZERO 保留以便 headless 单测无场景依赖时仍可用。
var player_spawn_pos: Vector3 = Vector3.ZERO

# 子权威系统实例
var interaction_auth: InteractionAuthorityClass
var combat_auth: CombatAuthorityClass
var loot_auth: LootAuthorityClass
var movement_auth: MovementAuthorityClass
var entity_sync_auth: EntitySyncAuthorityClass
var dungeon_auth: DungeonAuthorityClass
var connection_auth: ConnectionAuthorityClass
var save_auth: SaveAuthorityClass

# 服务器权威世界状态变更广播钩子：由 NetworkManager 接线为 _dispatch_world_event（含 RPC 下发到远端客户端）。
# 单进程无真实 peer 时 is_valid() 为 false→仅本地计数（单测可注入 spy 观察）。SessionRoot 经此广播
# EVT_WORLD_REVISION_CHANGED，使远端客户端更新其「服务器当前 revision」——
# 否则它们一直用旧 revision 上送→被 validate_world_revision 永久拒绝（world_revision 闭环的关键）。
var broadcast_event: Callable = Callable()

# 服务器固定采样步长（秒）：客户端以该频率发送 input_frame，服务器以此积分移动。
const SERVER_TICK_DT := 1.0 / 30.0

# 攻击冷却（秒，服务器绝对时间维护，客户端无法绕过）。
const SERVER_ATTACK_CD := 0.4
# 攻击扇区半角余弦（前 ~150° 弧内可命中；cos(75°)≈0.259）。
const ATTACK_SECTOR_HALF_COS := 0.259

# 攻击冷却到期时刻（peer_id -> 绝对时间），与 current_time 比较。
var _attack_cd_until: Dictionary = {}
# 玩家硬直剩余秒（peer_id -> float），受击时由伤害结算写入（Phase 3 预留）。
var _stagger: Dictionary = {}

func _init() -> void:
	registry = PlayerRegistryClass.new()
	world = WorldStateClass.new()
	router = CommandRouterClass.new()
	validator = CommandValidatorClass.new()
	interaction_auth = InteractionAuthorityClass.new()
	combat_auth = CombatAuthorityClass.new()
	loot_auth = LootAuthorityClass.new()
	movement_auth = MovementAuthorityClass.new()
	entity_sync_auth = EntitySyncAuthorityClass.new()
	dungeon_auth = DungeonAuthorityClass.new()
	connection_auth = ConnectionAuthorityClass.new()
	save_auth = SaveAuthorityClass.new()
	# 引用类型必须在 _init 内按实例独立初始化（GDScript 类级字面量跨实例共享）。
	_live_state = {}
	_entities = {}
	_ctx_peer = {}
	_seq_tracker = CommandValidatorClass.SequenceTracker.new()
	_loot_seq = 5000
	_inventory_baseline = {}
	_attack_cd_until = {}
	_stagger = {}

## 服务器侧会话初始化：标记权威、挂载默认权威处理器。
func init_server() -> void:
	is_server = true
	wire_default_authorities()

## 客户端侧会话初始化（不持有权威，但仍可缓存本地快照）。
func init_client() -> void:
	is_server = false

## 注册一个玩家（服务器生成后调用）。
func register_player(peer_id: int, ctx: PlayerContextClass, player = null, position: Vector3 = Vector3.ZERO) -> void:
	registry.register_peer(peer_id, ctx, player)
	_live_state[peer_id] = {"peer_id": peer_id, "is_alive": true, "position": position,
		"facing": Vector3(0, 0, -1), "look_yaw": 0.0}
	_ctx_peer[ctx.get_instance_id()] = peer_id
	registry.set_spawned(peer_id, true)
	player_registered.emit(peer_id)

## 服务器处理一次玩家生成请求（替代 network_manager 的 no-op）。
## 为 peer 创建独立的 PlayerContext（聚合独立属性/技能/背包/装备状态）。
## 联机范围仅限地牢（出征）：玩家进入地牢时只继承各自单人存档状态（save_state），
## 酒馆经营（酿造/升级/共享经济）为单人本地，不在联机范围内、不由本会话权威管理。
## save_state: 玩家单人存档摘要（materials/loadout 等），由存档系统加载后传入；空则使用默认。
## player_guid: 稳定身份（§14.2，不随 peer_id 变化），用于重连锚定；空则按 peer_id 派生。
func handle_spawn_request(peer_id: int, save_state: Dictionary = {}, player_guid: String = "") -> PlayerContextClass:
	if not is_server:
		return null
	if registry.has_peer(peer_id):
		return registry.get_context(peer_id)
	var attrs := AttrPanelClass.new()
	attrs.init_defaults()
	var sk := SkillRuntimeClass.new()
	sk.init_defaults()
	var inv := ExpeditionInventoryClass.new()
	var lo := EquipmentLoadoutClass.new()
	# 只继承存档状态：把玩家单人存档摘要应用到新生成的联机上下文（服务器可信数据）。
	if not save_state.is_empty():
		_apply_save_state(inv, lo, save_state)
	# 记录进地牢时的背包基线（用于结算时只回写净获得）。
	_inventory_baseline[peer_id] = inv.to_dict()
	var guid: String = player_guid if player_guid != "" else ("peer_%d" % peer_id)
	var ctx: PlayerContextClass = PlayerContextClass.for_peer(attrs, sk, inv, lo, null, guid)
	register_player(peer_id, ctx, null, player_spawn_pos)
	connection_auth.register_online(peer_id, guid, 0.0)
	player_spawned.emit(peer_id)
	# 玩家加入是结构性世界变更→推进 world_revision 并广播（闭环）。
	_bump_world()
	return ctx

## 把玩家单人存档摘要应用到新生成的联机上下文（地牢继承存档状态）。
## 仅复制服务器可信的存档数据；不信任任何客户端自报值。
func _apply_save_state(inv: ExpeditionInventoryClass, lo: EquipmentLoadoutClass, save_state: Dictionary) -> void:
	if save_state.has("materials") and save_state["materials"] is Dictionary:
		inv.materials = save_state["materials"].duplicate()
	if save_state.has("loadout") and save_state["loadout"] is Dictionary:
		lo.from_dict(save_state["loadout"])

## 注销玩家（断线清理）。
func unregister_player(peer_id: int) -> void:
	var ctx = registry.get_context(peer_id)
	if ctx != null:
		_ctx_peer.erase(ctx.get_instance_id())
	registry.unregister_peer(peer_id)
	_live_state.erase(peer_id)
	_seq_tracker.reset_peer(peer_id)
	_inventory_baseline.erase(peer_id)
	player_unregistered.emit(peer_id)

# ---------------------------------------------------------------------------
# 连接生命周期（§13）：断线保留 / 重连 / 心跳超时 / 主动离开
# ---------------------------------------------------------------------------

## 心跳（客户端定期 ping）：刷新该 peer 的最后活跃时间。
func heartbeat(peer_id: int, now: float = -1.0) -> void:
	if now < 0.0:
		now = current_time
	connection_auth.touch(peer_id, now)

## 服务器检测到 peer 掉线（显式断开 或 心跳超时）：进入 GRACE 保留期。
## 保留 PlayerContext，广播 player_despawned，释放其交互锁，并发放重连 token。
## 返回 {token, was_tracked}。调用方据此把 token 回传客户端供其重连使用。
func handle_peer_disconnected(peer_id: int, now: float = -1.0) -> Dictionary:
	if now < 0.0:
		now = current_time
	var res: Dictionary = connection_auth.on_disconnect(peer_id, now)
	if res["was_tracked"]:
		# 释放该 peer 持有的全部交互锁（§13.1「释放交互锁」）
		interaction_auth.clear_locks_for(peer_id)
		# 广播断线（其他客户端隐藏其实体；保留期后由 tick_connections 真正清理）
		var evt := {"event": NP.EVT_PLAYER_DESPAWNED, "peer_id": peer_id}
		session_event.emit(evt)
		# 玩家离开是结构性世界变更→推进 world_revision 并广播（闭环）。
		_bump_world()
	return res

## 客户端主动离开（不再重连）：立即清理 PlayerContext。
func handle_peer_left(peer_id: int) -> void:
	connection_auth.on_leave(peer_id)
	interaction_auth.clear_locks_for(peer_id)
	unregister_player(peer_id)
	var evt := {"event": NP.EVT_PLAYER_DESPAWNED, "peer_id": peer_id}
	session_event.emit(evt)
	# 玩家主动离开是结构性世界变更→推进 world_revision 并广播（闭环）。
	_bump_world()

## 推进连接时间：清理所有 GRACE 超时的 peer（保留期已过，注销 PlayerContext）。
## 返回被清理的 peer_id 列表。
func tick_connections(now: float = -1.0) -> Array:
	if now < 0.0:
		now = current_time
	var cleaned: Array = []
	for pid in connection_auth.collect_expired_grace(now):
		unregister_player(pid)
		cleaned.append(pid)
	return cleaned

## 客户端重连请求（CMD_RESUME）：按 guid/token 锚定旧条目，把全部服务器权威状态
## 从旧 peer_id 接管（迁移）到新 peer_id，恢复在线、重置序列、下发 session_snapshot
## （§13.2 重连快照）。重连沿用断线保留期内的同一 PlayerContext（inventory/位置/状态连续）。
## 关键：ENet 重连会分配【新】peer_id，全程不依赖 peer_id 作主键（§14.2）。
func _handle_resume(command: Dictionary, _ctx: PlayerContextClass) -> Dictionary:
	var new_peer_id: int = int(command.get("peer_id", 0))
	var token: String = String(command.get("token", ""))
	var guid: String = String(command.get("player_guid", ""))
	# 重连身份按 guid/token 锚定（不依赖会变的 peer_id）。
	var vr: Dictionary = connection_auth.validate_reconnect_by_guid(guid, token, current_time)
	if not vr["ok"]:
		return _reject(vr["reason"])
	var old_peer_id: int = int(vr["peer_id"])
	# 把旧 peer_id 的全部服务器权威状态迁移到新 peer_id（重连接管，不丢 inventory/位置/状态）。
	connection_auth.migrate_peer(old_peer_id, new_peer_id)
	_migrate_peer_state(old_peer_id, new_peer_id)
	# 完成重连：恢复 ONLINE（peer_id 已迁移到 new_peer_id）。
	var res: Dictionary = connection_auth.resume(new_peer_id, token, current_time)
	if not res["ok"]:
		return _reject(res["reason"])
	# 重连 = 新连接，重置该 peer 的命令序列（防重放/乱序）
	_seq_tracker.reset_peer(new_peer_id)
	# 保证 live_state 仍在线（断线保留期未清除；迁移后键为 new_peer_id）
	if not _live_state.has(new_peer_id):
		_live_state[new_peer_id] = {"peer_id": new_peer_id, "is_alive": true, "position": Vector3.ZERO}
	# 下发完整重连快照（先全量，再增量）
	var snap: Dictionary = build_session_snapshot()
	var evt := {"event": NP.EVT_SESSION_SNAPSHOT, "peer_id": new_peer_id, "snapshot": snap}
	session_event.emit(evt)
	return {"success": true, "event": evt, "error_code": ""}

## 把某旧 peer_id 的服务器权威状态整体接管（迁移）到新 peer_id（重连后新连接的新 peer_id）。
## 保留 PlayerContext（含 inventory/属性/技能/装备）、权威位置/朝向/存活、出征背包基线、
## 攻击冷却/硬直状态，并更新 ctx→peer 反向索引与 spawned 标记。旧键随后由调用方各自清除。
func _migrate_peer_state(old_id: int, new_id: int) -> void:
	if old_id == new_id:
		return
	# registry：把旧 ctx 重新登记到新 peer_id（保留 PlayerContext 全部状态，不重建）
	var ctx = registry.get_context(old_id)
	if ctx != null:
		registry.unregister_peer(old_id)
		registry.register_peer(new_id, ctx, null)
		registry.set_spawned(new_id, true)
		_ctx_peer[ctx.get_instance_id()] = new_id
	# live_state：保留权威位置/朝向/存活
	if _live_state.has(old_id):
		_live_state[new_id] = _live_state[old_id]
		_live_state[new_id]["peer_id"] = new_id
		_live_state.erase(old_id)
	# 出征背包基线 / 攻击冷却 / 硬直 / 交互锁（interaction_auth 以 peer_id 为键，一并迁移）
	if _inventory_baseline.has(old_id):
		_inventory_baseline[new_id] = _inventory_baseline[old_id]
		_inventory_baseline.erase(old_id)
	if _attack_cd_until.has(old_id):
		_attack_cd_until[new_id] = _attack_cd_until[old_id]
		_attack_cd_until.erase(old_id)
	if _stagger.has(old_id):
		_stagger[new_id] = _stagger[old_id]
		_stagger.erase(old_id)
	interaction_auth.migrate_locks(old_id, new_id)

## 服务器收到一条客户端命令的统一入口（由 NetworkManager RPC 调用）。
## 返回命令处理结果：{"success":bool,"event":Dictionary,"error_code":String}
func on_command(peer_id: int, command: Dictionary) -> Dictionary:
	if not is_server:
		return _reject(NP.ERR_PERMISSION_DENIED)
	# GRACE 期（断线保留）只接受重连请求，其余命令一律拒绝（§13.1）。
	var cmd_type: String = String(command.get("type", ""))
	if cmd_type == NP.CMD_RESUME:
		# 重连：新 peer_id 在状态迁移前尚无 live_state/ctx，须先按 guid/token 锚定旧条目再接管，
		# 故跳过后续「在线态 / live_state / ctx」检查（那些检查由 _handle_resume 在迁移后完成）。
		command["peer_id"] = peer_id
		return router.route(command, null)
	if cmd_type != NP.CMD_RESUME and not connection_auth.is_online(peer_id):
		return _reject(NP.ERR_INVALID_STATE)
	if not validator.validate_protocol(int(command.get("protocol_version", 0))):
		return _reject(NP.ERR_INVALID_PROTOCOL)
	if not validator.validate_world_revision(int(command.get("world_revision", 0)), world.world_revision):
		return _reject(NP.ERR_INVALID_WORLD_REVISION)
	# 反作弊：拒绝任何携带「服务器权威字段」的客户端命令（Phase 2.3）。
	# 客户端不得自报 position/velocity/damage/current_life/inventory_delta/drop_amount/
	# weapon_stats/player_attributes/save_state——这些值必须由服务器权威计算。
	if not validator.validate_no_trusted_fields(command):
		return _reject(NP.ERR_PERMISSION_DENIED)
	var ls: Dictionary = _live_state.get(peer_id, {})
	if ls.is_empty() or not bool(ls.get("is_alive", false)):
		return _reject(NP.ERR_PLAYER_NOT_ALIVE)
	var ctx: PlayerContextClass = registry.get_context(peer_id)
	if ctx == null:
		return _reject(NP.ERR_PLAYER_NOT_READY)
	return router.route(command, ctx)

func _reject(error_code: String) -> Dictionary:
	var evt := {"event": NP.EVT_COMMAND_REJECTED, "error_code": error_code}
	session_event.emit(evt)
	return {"success": false, "event": evt, "error_code": error_code}

## 服务器权威世界状态发生结构性变更：递增 world_revision 并广播 EVT_WORLD_REVISION_CHANGED，
## 使远端客户端更新其「服务器当前 revision」（否则它们一直用旧 revision 上送→被 validate_world_revision 永久拒绝）。
## space 非空时先切换当前空间（如 "dungeon"/"tavern"）再 bump；否则仅 bump（实体增删/玩家进出等离散变更）。
## broadcast_event 由 NetworkManager 接线；单进程（无真实 peer）下 is_valid() 为 false→仅本地计数（测试可注入 spy）。
func _bump_world(space := "") -> int:
	if not space.is_empty():
		world.transition_space(space)
	else:
		world.bump_revision()
	var rev: int = world.world_revision
	if broadcast_event.is_valid():
		broadcast_event.call({"event": NP.EVT_WORLD_REVISION_CHANGED, "world_revision": rev, "current_space": world.current_space})
	return rev

## 注册权威处理器（也可被单测注入假处理器覆盖默认接线）。
func register_authority(command_type: String, handler: Callable) -> void:
	router.register_handler(command_type, handler)

## 挂载默认权威处理器（服务器初始化时调用）。
func wire_default_authorities() -> void:
	register_authority(NP.CMD_INTERACT, _handle_interaction)
	register_authority(NP.CMD_PICKUP, _handle_interaction)
	register_authority(NP.CMD_ATTACK, _handle_combat)
	register_authority(NP.CMD_INPUT, _handle_movement)
	register_authority(NP.CMD_EXPEDITION, _handle_start_expedition)
	register_authority(NP.CMD_REQUEST_LAYOUT, _handle_layout_request)
	register_authority(NP.CMD_EXTRACT, _handle_extract)
	register_authority(NP.CMD_RESUME, _handle_resume)
	register_authority(NP.CMD_SKILL, _handle_skill)
	register_authority(NP.CMD_EQUIP, _handle_equip)
	register_authority(NP.CMD_DROP, _handle_drop)
	register_authority(NP.CMD_SAVE, _handle_save)
	register_authority(NP.CMD_LEAVE, _handle_leave)

func _handle_interaction(command: Dictionary, ctx: PlayerContextClass) -> Dictionary:
	var peer_id: int = int(_ctx_peer.get(ctx.get_instance_id(), 0))
	var live: Dictionary = _live_state.get(peer_id, {})
	var res: Dictionary = interaction_auth.resolve_interaction(command, ctx, live, _entities)
	if bool(res.get("success", false)):
		# 拾取成功：从权威注册表移除掉落实体，并附带 entity_despawned 事件，
		# 使两端表现层移除可见掉落物（玩家拾取后掉落物应从世界消失）。
		var tid: int = int(res.get("target_entity_id", 0))
		if tid != 0 and _entities.has(tid):
			var dres: Dictionary = remove_entity(tid)
			if bool(dres.get("success", false)) and dres.has("event") and not dres["event"].is_empty():
				var extra: Array = res.get("extra_events", [])
				if extra == null:
					extra = []
				extra.append(dres["event"])
				res["extra_events"] = extra
	return res

## 攻击有效射程（服务器权威，基于攻方当前激活武器 / 攻击类型，绝不信任客户端）。
## 近战约 2.5m，远程（弩/法术）约 18m；远程要求玩家确实装备了对应武器（归属校验）。
func _attack_range_for(ctx: PlayerContextClass, command: Dictionary) -> float:
	var atk_type: String = String(command.get("attack_type", "melee"))
	if atk_type == "ranged" or atk_type == "crossbow" or atk_type == "spell":
		# 远程攻击：校验确由激活武器支撑（无武器则降级为近战射程，避免凭空远程）。
		var w: String = ctx.loadout.get_weapon_slot(ctx.loadout.active_weapon_slot)
		if w != "" and w != "unarmed":
			return 18.0
		return 2.5
	return 2.5

func _handle_combat(command: Dictionary, ctx: PlayerContextClass) -> Dictionary:
	var peer_id: int = int(_ctx_peer.get(ctx.get_instance_id(), 0))
	var live: Dictionary = _live_state.get(peer_id, {})
	var err: String = combat_auth.validate_attack_request(command, live, world.world_revision, _seq_tracker)
	if err != "":
		return {"success": false, "event": {}, "error_code": err}
	# Phase 3：服务器权威目标 / 姿态 / 状态校验（距离 / 扇区 / 视线 / 冷却 / 硬直）。
	# 全部基于服务器权威数据（位置来自 live_state / 实体注册表，绝不信任客户端自报）。
	var defender_entity_id: int = int(command.get("target_hint", 0))
	var target_data: Dictionary = _entities.get(defender_entity_id, {})
	var attacker_snapshot := {
		"position": live.get("position", Vector3.ZERO),
		"facing": live.get("facing", Vector3(0, 0, -1)),
		"cooldown_remaining": float(_attack_cd_until.get(peer_id, -1.0)) - current_time,
		"stagger_remaining": float(_stagger.get(peer_id, 0.0)),
	}
	var target_snapshot := {
		"exists": _entities.has(defender_entity_id),
		"position": target_data.get("position", Vector3.ZERO),
		"los_ok": bool(target_data.get("los_ok", true)),
	}
	var atk_cfg := {
		"max_range": _attack_range_for(ctx, command),
		"sector_half_cos": ATTACK_SECTOR_HALF_COS,
		"allow_missing_target": true,
	}
	var terr: String = combat_auth.validate_attack_targeting(attacker_snapshot, target_snapshot, atk_cfg)
	if terr != "":
		return {"success": false, "event": {}, "error_code": terr}
	# 构造攻方输入（从服务器权威 PlayerContext 读取属性，绝不信任客户端自报）
	var ai: DamageResolverClass.AttackInput = DamageResolverClass.AttackInput.new()
	ai.attacker_str = ctx.attributes.get_attr("str")
	ai.attacker_dex = ctx.attributes.get_attr("dex")
	ai.attacker_mag = ctx.attributes.get_attr("mag")
	ai.attacker_per = ctx.attributes.get_attr("per")
	ai.attacker_agi = ctx.attributes.get_attr("agi")
	ai.attacker_con = ctx.attributes.get_attr("con")
	ai.attack_type = String(command.get("attack_type", "melee"))
	# 防方：从实体注册表取 target_hint 对应的敌人数据（服务器权威）
	# 注意：defender_entity_id 已在上方 Phase 3 校验块声明，此处复用不再 var 重声明。
	var defender_data: Dictionary = _entities.get(defender_entity_id, {})
	var forward: Vector3 = Vector3(0, 0, -1)
	var out: Dictionary = combat_auth.resolve_attack(ai, defender_data, forward, peer_id, defender_entity_id)
	# 服务器权威攻击冷却（绝对时间），防连点秒怪 / 绕过动画。
	_attack_cd_until[peer_id] = current_time + SERVER_ATTACK_CD
	# 权威扣血写回实体注册表，并附带 entity_snapshot（受伤）/ entity_despawned（死亡）事件，
	# 使两端表现层更新敌人 HP 或移除死亡敌人。掉落由死亡触发（Phase ⑤，此处先出 despawn）。
	var extra: Array = []
	if defender_entity_id != 0 and _entities.has(defender_entity_id):
		var new_life: int = int(out.get("defender_life", 0))
		if new_life <= 0:
			var loot_events: Array = _on_entity_killed(defender_entity_id, peer_id)
			var dres: Dictionary = remove_entity(defender_entity_id)
			if bool(dres.get("success", false)):
				extra.append(dres["event"])
			for le in loot_events:
				extra.append(le)
		else:
			var ures: Dictionary = update_entity(defender_entity_id, {"current_life": new_life})
			if bool(ures.get("success", false)):
				extra.append(ures["event"])
	return {"success": true, "event": out["event"], "error_code": "", "extra_events": extra}

## 敌人死亡钩子（Phase ⑤ 掉落入口）：根据敌人 loot_table 掷确定性掉落，
## 生成掉落实体（kind=loot，含 item_id/item_kind/amount/position）并产出 entity_spawned 事件，
## 供两端表现层（MultiplayerSceneBridge）复制为可见掉落物节点。
## 掉落位置取击杀者（killer）服务器权威坐标——保证击杀者处于交互范围内可立即拾取；
## 真实玩法中近战击杀者本就在敌人身旁，远程击杀可改为敌人死亡坐标（待设计确认）。
## 返回事件数组（entity_spawned），由 _handle_combat 合并进 extra_events 一并广播给两端。
func _on_entity_killed(entity_id: int, killer_peer: int) -> Array:
	var events: Array = []
	var enemy: Dictionary = _entities.get(entity_id, {})
	var table: Dictionary = enemy.get("loot_table", {})
	if table.is_empty():
		return events
	# 击杀者服务器权威坐标（掉落在拾取者身边，保证可交互）。
	var drop_pos: Vector3 = Vector3.ZERO
	var ls: Dictionary = _live_state.get(killer_peer, {})
	if not ls.is_empty():
		drop_pos = ls.get("position", Vector3.ZERO)
	# 确定性种子：entity_id + 物品序号，保证同一击杀产出可重连回放（与 LootAuthority 一致）。
	var rolled: Dictionary = server_roll_loot(table, (entity_id * 2654435761 + _loot_seq) & 0x7FFFFFFF, 4)
	var idx: int = 0
	for item_id in rolled.keys():
		var amount: int = int(rolled[item_id])
		if amount <= 0:
			continue
		_loot_seq += 1
		var lid: int = _loot_seq
		# 多掉落物在击杀点附近确定性散布，避免完全重叠。
		var off: Vector3 = Vector3(float(idx) * 0.4, 0.0, float(idx) * 0.4)
		var data: Dictionary = {
			"kind": "loot",
			"label": String(item_id),
			"position": drop_pos + off,
			"item_id": String(item_id),
			"item_kind": String(table[item_id].get("kind", "material")),
			"amount": amount,
			"current_life": 0,
			"max_life": 0,
			"consumed": false,
		}
		var res: Dictionary = set_entity(lid, data)
		if bool(res.get("success", false)) and res.has("event"):
			events.append(res["event"])
		idx += 1
	return events

## 服务器采样客户端输入帧（§6.2）：从输入积分出权威位置，更新 live state，下发 player_snapshot。
## 关键：服务器计算位置，绝不信任客户端自报坐标（防穿墙/速度作弊/瞬移）。
func _handle_movement(command: Dictionary, ctx: PlayerContextClass) -> Dictionary:
	var peer_id: int = int(_ctx_peer.get(ctx.get_instance_id(), 0))
	var live: Dictionary = _live_state.get(peer_id, {})
	var old_pos: Vector3 = live.get("position", Vector3.ZERO)
	var out: Dictionary = movement_auth.resolve_input_frame(command, live, world.world_revision, _seq_tracker, SERVER_TICK_DT)
	if out["success"]:
		var new_pos: Vector3 = out["event"]["position"]
		set_player_position(peer_id, new_pos)
		# 服务器权威朝向：由「实际位移方向」(new_pos - old_pos) 推导，绝不信任客户端自报 look_yaw。
		# 静止时保留上次朝向（不抖动）。表现层据此让角色转向移动方向（第三人称手感），
		# 同时驱动战斗扇区校验（攻击者须面朝目标一定扇区）。
		var delta: Vector3 = new_pos - old_pos
		if delta.length_squared() > 1e-6:
			var yaw: float = atan2(delta.x, -delta.z)
			if _live_state.has(peer_id):
				_live_state[peer_id]["look_yaw"] = yaw
				_live_state[peer_id]["facing"] = _yaw_to_forward(yaw)
				out["event"]["look_yaw"] = yaw  # 同步进下发快照，表现层据此转向
	return out

## 由 yaw（弧度）求水平前向单位向量（Godot 约定：yaw=0 朝 -Z）。
static func _yaw_to_forward(yaw: float) -> Vector3:
	return Vector3(sin(yaw), 0.0, -cos(yaw)).normalized()

## 服务器开启出征（§Phase 7）：由服务器决定权威 seed 并广播 dungeon_layout 事件。
## 客户端可在 command 中带 seed（host 指定），否则服务器随机。
func _handle_start_expedition(command: Dictionary, ctx: PlayerContextClass) -> Dictionary:
	var peer_id: int = int(_ctx_peer.get(ctx.get_instance_id(), 0))
	var provided_seed: int = int(command.get("seed", -1))
	var evt: Dictionary = dungeon_auth.start_expedition(provided_seed)
	# 新出征：重置结算账本（对齐地牢 layout_revision），使各玩家本 run 可重新结算一次。
	save_auth.begin_expedition(dungeon_auth.layout_revision)
	# 进入地牢是空间切换→推进 world_revision 并广播（闭环）。
	_bump_world("dungeon")
	session_event.emit(evt)
	return {"success": true, "event": evt, "error_code": ""}

## 客户端请求当前地牢布局（重连用 / 落后客户端追平）：校验其声明的 seed / layout_version
## 是否与服务器一致，一致则回吐 dungeon_layout 事件，否则拒绝（防作弊 / 版本错配）。
func _handle_layout_request(command: Dictionary, ctx: PlayerContextClass) -> Dictionary:
	var peer_id: int = int(_ctx_peer.get(ctx.get_instance_id(), 0))
	var claimed_seed: int = int(command.get("seed", -1))
	var claimed_layout_version: int = int(command.get("layout_version", -1))
	var res: Dictionary = dungeon_auth.validate_layout_request(peer_id, claimed_seed, claimed_layout_version)
	if not res["ok"]:
		return _reject(res["error_code"])
	session_event.emit(res["event"])
	return {"success": true, "event": res["event"], "error_code": ""}

## 客户端请求释放技能（§Phase 3 战斗权威前哨）：服务器校验该技能确由该玩家绑定，
## 拒绝伪造/未拥有的技能 id，再广播 EVT_SKILL_STATE_CHANGED 供两端表现层播放预表现。
## 实际技能效果结算（消耗/冷却/范围/伤害）留待 Phase 3 的 SkillAuthority，此处只做权威确认。
func _handle_skill(command: Dictionary, ctx: PlayerContextClass) -> Dictionary:
	var peer_id: int = int(_ctx_peer.get(ctx.get_instance_id(), 0))
	if not _seq_tracker.accept(peer_id, int(command.get("sequence", 0))):
		return _reject(NP.ERR_INVALID_SEQUENCE)
	var skill_id: String = String(command.get("skill_id", ""))
	if skill_id.is_empty():
		return _reject(NP.ERR_INVALID_TARGET)
	# 服务器校验该玩家确实已绑定此技能（不信任客户端自报）。
	var owned := false
	var sk = ctx.skills
	if sk != null:
		var bound: Array = sk.get_bound_active_skills() + sk.get_bound_passive_skills()
		owned = skill_id in bound
	if not owned:
		return _reject(NP.ERR_INVALID_TARGET)
	var evt := {
		"event": NP.EVT_SKILL_STATE_CHANGED,
		"peer_id": peer_id,
		"skill_id": skill_id,
		"triggered": true,
	}
	session_event.emit(evt)
	return {"success": true, "event": evt, "error_code": ""}

## 客户端请求装备物品：服务器校验物品确在该玩家背包内（权威），再写入 loadout 槽位。
## 绝不信客户端自报的任何属性；物品 id/slot 仅为标识符，服务器逐一校验合法性。
func _handle_equip(command: Dictionary, ctx: PlayerContextClass) -> Dictionary:
	var peer_id: int = int(_ctx_peer.get(ctx.get_instance_id(), 0))
	if not _seq_tracker.accept(peer_id, int(command.get("sequence", 0))):
		return _reject(NP.ERR_INVALID_SEQUENCE)
	var item_id: String = String(command.get("item_id", ""))
	var slot = command.get("slot", null)
	if item_id.is_empty() or slot == null:
		return _reject(NP.ERR_INVALID_TARGET)
	# 物品必须在该玩家背包内（权威），否则视为非法请求。
	var inv = ctx.inventory
	var owned: bool = (inv.materials.has(item_id) or inv.runes.has(item_id) or inv.equipment.has(item_id))
	if not owned:
		return _reject(NP.ERR_INVALID_TARGET)
	var lo = ctx.loadout
	var ok: bool = false
	if slot is int:
		if int(slot) < 0 or int(slot) >= lo.WEAPON_SLOT_COUNT:
			return _reject(NP.ERR_INVALID_TARGET)
		ok = lo.set_weapon_slot(int(slot), item_id)
	elif slot is String:
		if not (String(slot) in lo.VALID_ARMOR_SLOTS):
			return _reject(NP.ERR_INVALID_TARGET)
		ok = lo.set_armor_slot(String(slot), item_id)
	else:
		return _reject(NP.ERR_INVALID_TARGET)
	if not ok:
		return _reject(NP.ERR_INVALID_TARGET)
	var evt := {
		"event": NP.EVT_EQUIPMENT_CHANGED,
		"peer_id": peer_id,
		"item_id": item_id,
		"slot": slot,
	}
	return {"success": true, "event": evt, "error_code": ""}

## 客户端请求丢弃物品：服务器权威夹紧丢弃数量到【玩家实际持有量】（绝不信任客户端自报的
## drop_amount/绝对数量），从背包移除后于玩家服务器权威坐标生成可拾取的掉落实体。
func _handle_drop(command: Dictionary, ctx: PlayerContextClass) -> Dictionary:
	var peer_id: int = int(_ctx_peer.get(ctx.get_instance_id(), 0))
	if not _seq_tracker.accept(peer_id, int(command.get("sequence", 0))):
		return _reject(NP.ERR_INVALID_SEQUENCE)
	var item_id: String = String(command.get("item_id", ""))
	var cat: String = String(command.get("category", "material"))  # material / rune / equipment
	var inv = ctx.inventory
	var held: int = 0
	match cat:
		"material": held = int(inv.materials.get(item_id, 0))
		"rune": held = int(inv.runes.get(item_id, 0))
		"equipment": held = int(inv.equipment.get(item_id, 0))
		_: return _reject(NP.ERR_INVALID_TARGET)
	if held <= 0:
		return _reject(NP.ERR_INVALID_TARGET)
	# 夹紧：丢弃量 ∈ [1, 实际持有]，拒绝任何超过持有的请求（防无限复制）。
	var requested: int = int(command.get("amount", 1))
	var amount: int = mini(maxi(requested, 1), held)
	match cat:
		"material": inv.remove_material(item_id, amount)
		"rune": inv.remove_rune(item_id, amount)
		"equipment": inv.remove_equipment(item_id, amount)
	var pos: Vector3 = _live_state.get(peer_id, {}).get("position", Vector3.ZERO)
	_loot_seq += 1
	var lid: int = _loot_seq
	var data: Dictionary = {
		"kind": "loot", "label": item_id, "position": pos,
		"item_id": item_id, "item_kind": cat, "amount": amount,
		"current_life": 0, "max_life": 0, "consumed": false,
	}
	var res: Dictionary = set_entity(lid, data)
	var extra: Array = []
	if res.has("event") and not res["event"].is_empty():
		extra.append(res["event"])
	var evt := {
		"event": NP.EVT_INVENTORY_CHANGED,
		"peer_id": peer_id,
		"item_id": item_id, "category": cat, "amount": -amount,
	}
	return {"success": true, "event": evt, "error_code": "", "extra_events": extra}

## 客户端请求存档（§Phase 5）：反作弊由 on_command 的 forbidden-fields 守卫兜底
## （拒绝客户端自报 save_state）。此处服务器【仅按权威上下文】计算该玩家的出征净获得，
## 经 EVT_EXTRACTION_RESULT 回传，由桥接层写回该玩家各自的单人存档（绝不写他人）。
## 幂等由 SaveAuthority 收口（重复请求返回缓存结果并置 already_settled，桥接层跳过写回）。
func _handle_save(command: Dictionary, ctx: PlayerContextClass) -> Dictionary:
	var peer_id: int = int(_ctx_peer.get(ctx.get_instance_id(), 0))
	if not _seq_tracker.accept(peer_id, int(command.get("sequence", 0))):
		return _reject(NP.ERR_INVALID_SEQUENCE)
	return _settle_expedition(peer_id, ctx, true)

## 出征结算（§Phase 5）：客户端完成出征后请求结算，服务器计算该玩家【本次净获得】
## （当前背包 - 进地牢时的基线），经 EVT_EXTRACTION_RESULT 回传，由桥接层写回该玩家各自的
## 单人存档（GameState.expedition_inventory）。联机仅地牢、酒馆经济为单人本地，故不汇入 TavernManager。
## 幂等由 SaveAuthority 收口，防止「重复发 CMD_EXTRACT 刷物品」（§17.4 安全测试）。
func _handle_extract(command: Dictionary, ctx: PlayerContextClass) -> Dictionary:
	var peer_id: int = int(_ctx_peer.get(ctx.get_instance_id(), 0))
	return _settle_expedition(peer_id, ctx, false)

## 结算收口（extract / save 共用）：以 player_guid 幂等锚定本次出征结算。
## 首次结算：计算净获得、记入 SaveAuthority、返回 already_settled=false（桥接层落地写回）。
## 重复结算：返回缓存 settlement、already_settled=true（桥接层跳过写回，杜绝刷物品）。
func _settle_expedition(peer_id: int, ctx: PlayerContextClass, requested_save: bool) -> Dictionary:
	var guid: String = _peer_guid(peer_id, ctx)
	if save_auth.is_settled(guid):
		var cached: Dictionary = save_auth.get_settlement(guid)
		var evt_dup := {
			"event": NP.EVT_EXTRACTION_RESULT,
			"peer_id": peer_id,
			"settlement": cached,
			"already_settled": true,
			"requested_save": requested_save,
		}
		return {"success": true, "event": evt_dup, "error_code": ""}
	var settlement: Dictionary = _compute_settlement(peer_id)
	save_auth.mark_settled(guid, settlement)
	var evt := {
		"event": NP.EVT_EXTRACTION_RESULT,
		"peer_id": peer_id,
		"settlement": settlement,
		"already_settled": false,
		"requested_save": requested_save,
	}
	return {"success": true, "event": evt, "error_code": ""}

## 取某 peer 的稳定身份 guid（优先 PlayerContext.player_guid，缺省按 peer_id 派生）。
func _peer_guid(peer_id: int, ctx: PlayerContextClass = null) -> String:
	if ctx != null and "player_guid" in ctx and String(ctx.player_guid) != "":
		return String(ctx.player_guid)
	var c: PlayerContextClass = registry.get_context(peer_id)
	if c != null and "player_guid" in c and String(c.player_guid) != "":
		return String(c.player_guid)
	return "peer_%d" % peer_id

## 客户端主动离开（不再重连）：立即清理 PlayerContext 并广播 despawned。
func _handle_leave(command: Dictionary, ctx: PlayerContextClass) -> Dictionary:
	var peer_id: int = int(_ctx_peer.get(ctx.get_instance_id(), 0))
	handle_peer_left(peer_id)
	return {"success": true, "event": {}, "error_code": ""}

## 计算某 peer 的出征净获得 = 当前背包 - 进地牢基线，按 materials/runes/equipment 三类求正差值。
## 返回 {materials:{id:amt}, runes:{id:amt}, equipment:{id:amt}}（仅含净增加项）。
func _compute_settlement(peer_id: int) -> Dictionary:
	var ctx: PlayerContextClass = registry.get_context(peer_id)
	if ctx == null or ctx.inventory == null:
		return {"materials": {}, "runes": {}, "equipment": {}}
	var cur: Dictionary = ctx.inventory.to_dict()
	var base: Dictionary = _inventory_baseline.get(peer_id, {"materials": {}, "runes": {}, "equipment": {}})
	var out: Dictionary = {"materials": {}, "runes": {}, "equipment": {}}
	for cat in ["materials", "runes", "equipment"]:
		var c: Dictionary = cur.get(cat, {})
		var b: Dictionary = base.get(cat, {})
		for k in c.keys():
			var delta: int = int(c[k]) - int(b.get(k, 0))
			if delta > 0:
				out[cat][k] = delta
	return out

## 服务器权威掉落（敌人死亡时调用，非客户端命令）。
func server_roll_loot(table: Dictionary, seed: int, max_items: int = 4) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return loot_auth.roll_loot(table, rng, max_items)

## 实体注册（服务器权威）：敌人/掉落/宝箱/门...
## 经 EntitySyncAuthority 维护，并产生 entity_spawned 复制事件（server 侧）。
func set_entity(entity_id: int, data: Dictionary) -> Dictionary:
	var is_new: bool = not _entities.has(entity_id)
	var res: Dictionary = entity_sync_auth.spawn_entity(entity_id, data, _entities)
	# 新增实体是结构性世界变更→推进 world_revision（重播已有实体不 bump，避免追平客户端时反复 churn）。
	if is_new:
		_bump_world()
	return res

## 移除实体（服务器权威）。返回 entity_despawned 复制事件（server 侧）。
func remove_entity(entity_id: int) -> Dictionary:
	var existed: bool = _entities.has(entity_id)
	var res: Dictionary = entity_sync_auth.despawn_entity(entity_id, _entities)
	# 实体消失是结构性世界变更→推进 world_revision（实体不存在时的 no-op 不 bump）。
	if existed:
		_bump_world()
	return res

## 更新实体部分字段（服务器权威），返回 entity_snapshot 复制事件（server 侧）。
func update_entity(entity_id: int, partial: Dictionary) -> Dictionary:
	return entity_sync_auth.update_entity(entity_id, partial, _entities)

func get_entity(entity_id: int) -> Dictionary:
	return _entities.get(entity_id, {})

## 返回全部实体注册表（entity_id -> 状态）。供 NetworkManager 向晚到客户端重播/追平。
func all_entities() -> Dictionary:
	return _entities

## 实体对账（服务器权威，Phase 10 生产化）：计算把某客户端【已知实体集 known】追平到
## 服务器【当前权威实体集 _entities】所需的最小复制事件集——
##   新增(known 无 / server 有) → entity_spawned；
##   变化(两端都有但字段不同) → entity_snapshot；
##   消失(known 有 / server 无) → entity_despawned（**这是 rebroadcast_entities 做不到的**：
##     朴素重播只会把 server 现有实体全量 spawned，无法清理重连客户端仍持有的陈旧实体）。
## known 为空即全量 spawned（等价旧 rebroadcast 行为，向后兼容）。
## 纯逻辑（委托 EntitySyncAuthority.build_delta），可单测；真实下发由 NetworkManager 接线。
func reconcile_entities(known: Dictionary) -> Array:
	return entity_sync_auth.build_delta(known, _entities)

## 更新玩家权威位置（服务器移动模拟后调用）。
func set_player_position(peer_id: int, position: Vector3) -> void:
	if _live_state.has(peer_id):
		_live_state[peer_id]["position"] = position

func set_player_alive(peer_id: int, alive: bool) -> void:
	if _live_state.has(peer_id):
		_live_state[peer_id]["is_alive"] = alive

## 构建重连快照（§13.2）：世界状态 + 在线玩家上下文摘要 + 实体。
func build_session_snapshot() -> Dictionary:
	var snap: Dictionary = world.build_session_snapshot()
	var players: Array = []
	for pid in registry.peer_ids():
		var ls: Dictionary = _live_state.get(pid, {})
		players.append({
			"peer_id": pid,
			"is_alive": bool(ls.get("is_alive", true)),
			"position": ls.get("position", Vector3.ZERO),
		})
	snap["players"] = players
	snap["entities"] = _entities.duplicate()
	snap["dungeon"] = dungeon_auth.serialize()
	# 结算账本纳入重连快照：防止「断线→重连→再结算」绕过幂等刷物品（§17.4）。
	snap["save"] = save_auth.serialize()
	return snap

## 从快照恢复（重连用）。
func apply_session_snapshot(snap: Dictionary) -> void:
	world.apply_session_snapshot(snap)
	if snap.has("entities"):
		_entities = snap["entities"].duplicate()
	if snap.has("dungeon"):
		dungeon_auth.deserialize(snap["dungeon"])
	if snap.has("save"):
		save_auth.deserialize(snap["save"])
