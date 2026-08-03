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
const SpellRecipeDataClass := preload("res://globals/combat/spell_recipe_data.gd")
const SpellAuthorityClass := preload("res://globals/combat/spell_authority.gd")
const AttackContextFactoryClass := preload("res://globals/combat/attack_context_factory.gd")
const AttackCadencePolicyClass := preload("res://globals/combat/attack_cadence_policy.gd")
const SpellAccessPolicyClass := preload("res://globals/combat/spell_access_policy.gd")
const SpellWorldExecutorClass := preload("res://globals/combat/spell_world_executor.gd")
const ServerCharacterMotorClass := preload("res://globals/multiplayer/server_character_motor.gd")
const EquipmentPolicyClass := preload("res://globals/core/equipment_policy.gd")
const ServerSaveRepositoryClass := preload("res://globals/multiplayer/server_save_repository.gd")
const ProgressionAuthorityClass := preload("res://globals/multiplayer/progression_authority.gd")

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

# Per-peer Node-based state services are owned by this container. PlayerContext
# keeps the typed references, while the container provides deterministic cleanup
# on leave, grace expiry, and SessionRoot teardown.
var _peer_state_root: Node
var _peer_state_nodes: Dictionary

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
var spell_auth: SpellAuthorityClass
# P0-1：服务器权威移动马达（真实碰撞 move_and_slide；无碰撞世界回退纯积分）。
var movement_motor: ServerCharacterMotorClass

# 服务器权威世界状态变更广播钩子：由 NetworkManager 接线为 _dispatch_world_event（含 RPC 下发到远端客户端）。
# 单进程无真实 peer 时 is_valid() 为 false→仅本地计数（单测可注入 spy 观察）。SessionRoot 经此广播
# EVT_WORLD_REVISION_CHANGED，使远端客户端更新其「服务器当前 revision」——
# 否则它们一直用旧 revision 上送→被 validate_world_revision 永久拒绝（world_revision 闭环的关键）。
var broadcast_event: Callable = Callable()

# 服务器固定采样步长（秒）：客户端以该频率发送 input_frame，服务器以此积分移动。
const SERVER_TICK_DT := 1.0 / 30.0

# 攻击扇区半角余弦（前 ~150° 弧内可命中；cos(75°)≈0.259）。
const ATTACK_SECTOR_HALF_COS := 0.259
# 客户端攻击意图命令允许携带的字段白名单（P0-2：绝不接受客户端 attack_type）。
# 攻击类型/射程/冷却/伤害全部由服务器从权威 loadout 派生（AttackContextFactory）。
const ATTACK_INTENT_FIELDS := ["type", "protocol_version", "world_revision", "client_tick", "sequence", "hand", "charge_ratio", "target_hint"]

# 攻击冷却到期时刻（peer_id -> 绝对时间），与 current_time 比较。
var _attack_cd_until: Dictionary = {}
# 玩家硬直剩余秒（peer_id -> float），受击时由伤害结算写入（Phase 3 预留）。
var _stagger: Dictionary = {}
# P0-2：per-peer 最新输入缓冲（peer_id -> 最新 input_frame 命令）。
# RPC 只更新缓冲（最新覆盖），服务器在固定 SERVER_TICK_DT 消费——客户端提高合法递增
# sequence 的发送频率不会让服务器按 RPC 次数重复积分（速度作弊/穿墙根防）。
var _input_queue: Dictionary = {}
# P1-1：服务器可信存档仓（按 player_guid 持久化权威背包/装配/法术状态）。
# 由 NetworkManager 注入；null 时退回「仅调用方传入摘要」的旧行为（测试/无仓环境）。
var server_save_repo: ServerSaveRepositoryClass = null
# P1（2124 审查）：会话拥有的法术投射物清单——会话销毁时统一回收，
# 避免全局对象池/场景切换残留跨会话的端口与节点。
var _session_projectiles: Array = []
# P0（2331 审查）：玩家战斗状态事件 revision（peer_id -> int，递增去重/顺序）。
var _combat_state_revision: Dictionary = {}
# P0（2331 审查）：权威敌人攻击模拟参数——服务器敌人每 1.5s 攻击近战范围内玩家，伤害 8。
const ENEMY_ATTACK_INTERVAL := 1.5
const ENEMY_ATTACK_RANGE := 1.8
const ENEMY_ATTACK_DAMAGE := 8

func _init() -> void:
	registry = PlayerRegistryClass.new()
	world = WorldStateClass.new()
	# These services are Nodes for compatibility with the session architecture;
	# attach them so SessionRoot owns and releases their lifecycle.
	registry.name = "PlayerRegistry"
	world.name = "WorldState"
	add_child(registry)
	add_child(world)
	_peer_state_root = Node.new()
	_peer_state_root.name = "PeerState"
	add_child(_peer_state_root)
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
	spell_auth = SpellAuthorityClass.new()
	movement_motor = ServerCharacterMotorClass.new()
	# 引用类型必须在 _init 内按实例独立初始化（GDScript 类级字面量跨实例共享）。
	_live_state = {}
	_entities = {}
	_ctx_peer = {}
	_seq_tracker = CommandValidatorClass.SequenceTracker.new()
	_loot_seq = 5000
	_inventory_baseline = {}
	_peer_state_nodes = {}
	_attack_cd_until = {}
	_stagger = {}
	_input_queue = {}
	_session_projectiles = []

func _notification(what: int) -> void:
	# P1（2124/2218 审查）：会话销毁时回收会话拥有的法术投射物。
	# 只回收仍有效且仍在场景树（active、未被全局池回收复用）的节点——
	# 避免「旧会话引用被池复用到新会话的节点」时错误释放。
	if what == NOTIFICATION_EXIT_TREE:
		for proj in _session_projectiles:
			if proj is Node and is_instance_valid(proj) and proj.is_inside_tree():
				proj.queue_free()
		_session_projectiles.clear()

## P1（2124 审查）：登记会话拥有的法术投射物（会话销毁时统一回收）。
func track_projectile(projectile: Node) -> void:
	if projectile != null and is_instance_valid(projectile):
		_session_projectiles.append(projectile)

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
## 架构审查 P0-1：在创建任何玩家子对象/库存基线【前】做在线 GUID 唯一性预检——
## 重复在线身份直接拒绝（返回 null），避免先建状态再覆盖身份索引导致的重连/结算串账。
func handle_spawn_request(peer_id: int, save_state: Dictionary = {}, player_guid: String = "") -> PlayerContextClass:
	if not is_server:
		return null
	if registry.has_peer(peer_id):
		return registry.get_context(peer_id)
	var guid: String = player_guid if player_guid != "" else ("peer_%d" % peer_id)
	# P0-1 预检：该 GUID 已被其他 ONLINE peer 占用 → 拒绝（不创建任何状态）。
	if connection_auth.has_online_guid(guid):
		return null
	var attrs := AttrPanelClass.new()
	attrs.init_defaults()
	var sk := SkillRuntimeClass.new()
	sk.init_defaults()
	attrs.name = "AttrPanel_%d" % peer_id
	sk.name = "SkillRuntime_%d" % peer_id
	_peer_state_root.add_child(attrs)
	_peer_state_root.add_child(sk)
	_peer_state_nodes[peer_id] = [attrs, sk]
	var inv := ExpeditionInventoryClass.new()
	var lo := EquipmentLoadoutClass.new()
	var ctx: PlayerContextClass = PlayerContextClass.for_peer(attrs, sk, inv, lo, null, guid)
	# P1-1：服务器可信存档仓优先——该身份在服务器已有权威存档时，以仓内状态恢复
	# （材料/装备/法术装配），绝不信任客户端字典；无仓/无存档才用调用方摘要或默认状态。
	var applied_save: Dictionary = {}
	if server_save_repo != null:
		applied_save = server_save_repo.load_save(guid)
	if applied_save.is_empty():
		applied_save = save_state
	if not applied_save.is_empty():
		_apply_save_state(ctx, inv, lo, applied_save)
	# 记录进地牢时的背包基线（用于结算时只回写净获得）。
	_inventory_baseline[peer_id] = inv.to_dict()
	register_player(peer_id, ctx, null, player_spawn_pos)
	# P0-1：结构化注册结果；预检后理论上必成功，失败则回滚（不留下半创建状态）。
	var reg: Dictionary = connection_auth.register_online(peer_id, guid, 0.0)
	if not bool(reg.get("ok", false)):
		unregister_player(peer_id)
		return null
	player_spawned.emit(peer_id)
	# 玩家加入是结构性世界变更→推进 world_revision 并广播（闭环）。
	_bump_world()
	return ctx

## 把玩家单人存档摘要应用到新生成的联机上下文（地牢继承存档状态）。
## 仅复制服务器可信的存档数据；不信任任何客户端自报值。
## P0-5：除 materials/loadout 外，还恢复 spell_state（权威法术装配：符文槽/冷却/法力），
## 使正常远端入口拥有服务器权威法术来源，不再默认空 SpellLoadout。
func _apply_save_state(ctx: PlayerContextClass, inv: ExpeditionInventoryClass, lo: EquipmentLoadoutClass, save_state: Dictionary) -> void:
	if save_state.has("materials") and save_state["materials"] is Dictionary:
		inv.materials = save_state["materials"].duplicate()
	if save_state.has("loadout") and save_state["loadout"] is Dictionary:
		lo.from_dict(save_state["loadout"])
	if save_state.has("spell_state") and save_state["spell_state"] is Dictionary:
		ctx.deserialize_spell_state(save_state["spell_state"])
	# P1-4：统一 DungeonPlayerSnapshot——属性/熟练度/等级与技能装配随存档摘要恢复，
	# 使服务器权威成长（击杀经验/升级选择）作用于玩家真实状态而非默认值。
	if save_state.has("attributes") and save_state["attributes"] is Dictionary and ctx.attributes != null:
		ctx.attributes.deserialize(save_state["attributes"])
	if save_state.has("skills") and save_state["skills"] is Dictionary and ctx.skills != null:
		ctx.skills.deserialize(save_state["skills"])

## 把真实 Player 实体绑定到 peer 的权威 PlayerContext（架构审查 P0-4）。
## 服务器法术权威执行依赖已绑定的 caster 节点；未绑定时施法在资源 commit 前被拒绝。
## 由表现层（DungeonSessionController 房主本地玩家 / MultiplayerSceneBridge 远端 avatar）
## 在实体创建后调用。返回是否绑定成功。
func bind_player_entity(peer_id: int, player_entity: Node3D) -> bool:
	if player_entity == null or not is_instance_valid(player_entity):
		return false
	var ctx: PlayerContextClass = registry.get_context(peer_id)
	if ctx == null:
		return false
	ctx.player_node = player_entity
	return true

## 注销玩家（断线清理）。
func unregister_player(peer_id: int) -> void:
	var ctx = registry.get_context(peer_id)
	if ctx != null:
		_ctx_peer.erase(ctx.get_instance_id())
	_free_peer_state_nodes(peer_id)
	registry.unregister_peer(peer_id)
	_live_state.erase(peer_id)
	_seq_tracker.reset_peer(peer_id)
	_inventory_baseline.erase(peer_id)
	player_unregistered.emit(peer_id)


func _free_peer_state_nodes(peer_id: int) -> void:
	var state_nodes: Array = _peer_state_nodes.get(peer_id, [])
	_peer_state_nodes.erase(peer_id)
	for node in state_nodes:
		if node is Node and is_instance_valid(node):
			node.free()

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
	if _peer_state_nodes.has(old_id):
		_peer_state_nodes[new_id] = _peer_state_nodes[old_id]
		_peer_state_nodes.erase(old_id)
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
	register_authority(NP.CMD_CAST_SPELL, _handle_cast_spell)
	register_authority(NP.CMD_EQUIP, _handle_equip)
	register_authority(NP.CMD_DROP, _handle_drop)
	register_authority(NP.CMD_SAVE, _handle_save)
	register_authority(NP.CMD_LEAVE, _handle_leave)
	register_authority(NP.CMD_LEVEL_UP_CHOICE, _handle_level_up_choice)
	register_authority(NP.CMD_LEVEL_UP_RUNE_CANDIDATES, _handle_level_up_rune_candidates)

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

## 从服务器权威 PlayerContext 构建本次攻击的唯一 AttackContext（架构审查 P0-2）。
## 手位/蓄力/目标提示取自命令意图（白名单字段）；攻击类型/射程/风格/伤害输入
## 全部由权威 loadout + WeaponRegistry 派生，绝不接受客户端 attack_type。
## registry 为空（无场景树）时按武器 id 派生，伤害输入退化为未解析武器（测试环境）。
func _build_attack_context(ctx: PlayerContextClass, command: Dictionary, registry: Object) -> Dictionary:
	var hand: String = String(command.get("hand", "primary"))
	if hand != "primary" and hand != "secondary":
		hand = "primary"
	var charge_ratio: float = clampf(float(command.get("charge_ratio", 1.0)), 0.0, 1.0)
	var attrs: Dictionary = ctx.attributes.get_player_attrs() if ctx.attributes != null else {}
	var level: int = ctx.attributes.get_level() if ctx.attributes != null else 1
	var actx = AttackContextFactoryClass.build_from_player_state(
		attrs, level, ctx.loadout, registry, hand, charge_ratio, command.get("target_hint", 0))
	return {
		"context": actx,
		"hand": hand,
		"charge_ratio": charge_ratio,
		"attack_input": AttackContextFactoryClass.to_attack_input(actx),
		"range": actx.attack_range(),
	}

func _handle_combat(command: Dictionary, ctx: PlayerContextClass) -> Dictionary:
	var peer_id: int = int(_ctx_peer.get(ctx.get_instance_id(), 0))
	var live: Dictionary = _live_state.get(peer_id, {})
	# P0-2：攻击意图命令只允许携带白名单字段（hand/charge_ratio/target_hint），
	# 拒绝任何攻击类型/伤害/属性自报字段（防伪报 ranged 骗射程）。
	for key in command.keys():
		if not (key in ATTACK_INTENT_FIELDS):
			return {"success": false, "event": {}, "error_code": NP.ERR_INVALID_STATE}
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
	# 攻击装配唯一真相：AttackContextFactory（攻击类型/射程/风格/伤害输入由权威 loadout 派生）。
	var built: Dictionary = _build_attack_context(ctx, command, _weapon_registry())
	var actx = built["context"]
	var atk_cfg := {
		"max_range": float(built["range"]),
		"sector_half_cos": ATTACK_SECTOR_HALF_COS,
		"allow_missing_target": true,
	}
	var terr: String = combat_auth.validate_attack_targeting(attacker_snapshot, target_snapshot, atk_cfg)
	if terr != "":
		return {"success": false, "event": {}, "error_code": terr}
	# 武器归属兜底（防后续路径引入未经 loadout 的武器）：权威 loadout 派生的武器必然在槽内。
	var owned_weapons: Array = []
	for raw_id in ctx.loadout.weapon_slots:
		owned_weapons.append(String(raw_id))
	if not CombatAuthorityClass.validate_weapon_ownership(actx.weapon_id(), owned_weapons):
		return {"success": false, "event": {}, "error_code": NP.ERR_INVALID_TARGET}
	var ai: DamageResolverClass.AttackInput = built["attack_input"]
	# 防方：从实体注册表取 target_hint 对应的敌人数据（服务器权威）
	var defender_data: Dictionary = _entities.get(defender_entity_id, {})
	var forward: Vector3 = Vector3(0, 0, -1)
	var out: Dictionary = combat_auth.resolve_attack(ai, defender_data, forward, peer_id, defender_entity_id)
	# 服务器权威攻击冷却：唯一真相 AttackCadencePolicy（架构审查 P0-3），
	# 与单机 PlayerCombatRuntime/HUD 同一公式（流派/手位派生；联机侧无连击栈与被动查询，
	# 传 0/false，DEX 等属性不影响冷却——与单机已裁定公式一致）。
	var cd: float = AttackCadencePolicyClass.compute_attack_cd(actx, false, 0)
	_attack_cd_until[peer_id] = current_time + cd
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

## 解析 WeaponRegistry（autoload）。无场景树（headless 单测）时返回 null。
func _weapon_registry() -> Object:
	var tree := Engine.get_main_loop()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("WeaponRegistry")

## 敌人死亡钩子（Phase ⑤ 掉落入口）：根据敌人 loot_table 掷确定性掉落，
## 生成掉落实体（kind=loot，含 item_id/item_kind/amount/position）并产出 entity_spawned 事件，
## 供两端表现层（MultiplayerSceneBridge）复制为可见掉落物节点。
## 掉落位置取击杀者（killer）服务器权威坐标——保证击杀者处于交互范围内可立即拾取；
## 真实玩法中近战击杀者本就在敌人身旁，远程击杀可改为敌人死亡坐标（待设计确认）。
## P1-4：击杀经验只授予 killer 的 per-peer 属性上下文并广播 EVT_PROGRESSION_CHANGED
## （服务器权威成长闭环；单机路径不变）。
## 返回事件数组（entity_spawned / progression_changed），由 _handle_combat 合并进
## extra_events 一并广播给两端。
func _on_entity_killed(entity_id: int, killer_peer: int) -> Array:
	var events: Array = []
	var enemy: Dictionary = _entities.get(entity_id, {})
	# P1-4：击杀归属 → 角色经验（仅 killer 的权威上下文；绝不写他人/全局 current_player）。
	var killer_ctx: PlayerContextClass = registry.get_context(killer_peer)
	if killer_ctx != null and killer_ctx.attributes != null:
		var reward: int = ProgressionAuthorityClass.compute_kill_reward(
			int(enemy.get("max_life", 0)),
			bool(enemy.get("is_elite", false)),
			bool(enemy.get("is_boss", false)))
		var levels_gained: int = ProgressionAuthorityClass.award_kill_experience(killer_ctx.attributes, reward)
		if levels_gained > 0 or reward > 0:
			var prog_evt := _progression_event(killer_peer, killer_ctx)
			events.append(prog_evt)
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

## 服务器采样客户端输入帧（§6.2）：从输入产出权威位置，更新 live state，下发 player_snapshot。
## 关键：服务器计算位置，绝不信任客户端自报坐标（防穿墙/速度作弊/瞬移）。
## P0-1：已绑定真实 CharacterBody3D（房主 Player / 远端 avatar）时经 ServerCharacterMotor
## 走 move_and_slide 真实碰撞；未绑定（headless 单测/无几何专用服务器）回退纯积分。
func _handle_movement(command: Dictionary, ctx: PlayerContextClass) -> Dictionary:
	var peer_id: int = int(_ctx_peer.get(ctx.get_instance_id(), 0))
	var live: Dictionary = _live_state.get(peer_id, {})
	var old_pos: Vector3 = live.get("position", Vector3.ZERO)
	var body: CharacterBody3D = ctx.player_node as CharacterBody3D
	var out: Dictionary = movement_auth.resolve_input_frame(command, live, world.world_revision, _seq_tracker, SERVER_TICK_DT, movement_motor, body)
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

# ---------------------------------------------------------------------------
# P0-2：服务器固定 tick 输入缓冲（docs/25 §6.2 生产化）
# ---------------------------------------------------------------------------

## 入队某 peer 的最新输入帧（RPC 路径调用；仅服务器且该 peer ONLINE 才接受）。
## 缓冲语义：每 peer 只保留【最新】一帧，重复帧直接覆盖——合法递增 sequence 的
## 高频洪泛不会造成输入累积（每 tick 每 peer 最多消费一次）。
func queue_input(peer_id: int, command: Dictionary) -> bool:
	if not is_server:
		return false
	if not connection_auth.is_online(peer_id):
		return false
	_input_queue[peer_id] = command.duplicate()
	return true

## 消费一个服务器固定 tick（SERVER_TICK_DT）的全部 pending 输入：每 peer 恰好消费
## 【最新】一帧，产出的 player_snapshot 由调用方（NetworkManager）统一节流下发。
## 返回处理结果数组（元素含 peer_id/command/result）。被更新的命令取代的输入帧
## （sequence 已落后于已接受序列）静默跳过，不做权威位移、不产生拒绝事件。
func consume_input_tick() -> Array:
	var results: Array = []
	if not is_server or _input_queue.is_empty():
		return results
	for pid in _input_queue.keys():
		var command: Dictionary = _input_queue[pid]
		_input_queue.erase(pid)
		var ctx: PlayerContextClass = registry.get_context(pid)
		if ctx == null:
			continue
		var res: Dictionary = _handle_movement(command, ctx)
		results.append({"peer_id": pid, "command": command, "result": res})
	return results

## 服务器输入缓冲当前待处理帧数（测试观测用）。
func pending_input_count() -> int:
	return _input_queue.size()

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

## 客户端请求施放法术：服务器校验槽位/配方/资格/法力/冷却后，按
## prepare → execute → verify → commit → publish 原子顺序执行（架构审查 P0-3/P0-4/P0-5）：
##   * 施法资格（法杖/魔导书/奥法之剑）经 SpellAccessPolicy 纯逻辑重新校验，绝不信任客户端；
##   * caster 实体未绑定（ctx.player_node == null）时在【任何资源 commit 前】拒绝 PLAYER_NOT_READY，
##     杜绝「扣法力+提交冷却但无世界效果」的事务断裂；
##   * 世界执行在【资源 commit 前】完成并校验 ok（预算满/实施不支持/服务缺失 → 拒绝，不扣资源）；
##   * 世界伤害（ray/area/ground/summon）经会话级执行器的 damage_entity_port 写回权威实体仓
##     _entities（生命/死亡/掉落复制与普通攻击同一路径），不再只打在可见节点上；
##   * 只有执行成功才提交法力与冷却，然后发布 EVT_SPELL_RESOLVED。
func _handle_cast_spell(command: Dictionary, ctx: PlayerContextClass) -> Dictionary:
	var peer_id: int = int(_ctx_peer.get(ctx.get_instance_id(), 0))
	if not _seq_tracker.accept(peer_id, int(command.get("sequence", 0))):
		return _reject(NP.ERR_INVALID_SEQUENCE)
	var slot_index := clampi(int(command.get("slot_index", -1)), 0, 4)
	# 服务端只从 per-peer PlayerContext 的权威 SpellLoadout 读取，绝不接受客户端 spell_id。
	if ctx.spell_loadout == null:
		return _reject(NP.ERR_INVALID_STATE)
	var spell: Dictionary = ctx.spell_loadout.get_spell(slot_index)
	if spell.is_empty() or SpellRecipeDataClass.resolve(spell.get("recipe", [])).is_empty():
		return _reject(NP.ERR_INVALID_TARGET)
	# P0-5：施法资格 —— SpellAccessPolicy 纯逻辑（权威 loadout 武器 + 奥法之剑被动），
	# 绕过本地 UI 直接提交施法在这里被拒绝。
	if not _validate_spell_access(ctx):
		return _reject(NP.ERR_INVALID_TARGET)
	# P0-4：caster 必须已绑定真实 Player 实体，否则在任何资源 commit 前拒绝。
	if ctx.player_node == null or not is_instance_valid(ctx.player_node):
		return _reject(NP.ERR_PLAYER_NOT_READY)
	var mana_cost := ctx.spell_runtime.mana_cost_for(spell)
	if ctx.spell_mana < mana_cost:
		return _reject(NP.ERR_INSUFFICIENT_RESOURCE)
	var spell_id := String(spell.get("id", ""))
	# 冷却只读预检（commit_authoritative_cooldown 会在提交时二重确认）。
	if ctx.spell_runtime.is_on_cooldown(spell_id):
		return _reject(NP.ERR_COOLDOWN_ACTIVE)
	# 世界执行可行性预检（commit 前）：不支持的实施类型不得消耗资源。
	var implementation := String(spell.get("implementation", "projectile"))
	if not SpellAuthorityClass.supports_implementation(implementation):
		return _reject(NP.ERR_INVALID_TARGET)
	# ---- 事务：execute → verify（commit 前）→ commit → publish ----
	# P0-3：会话级世界执行器（SessionRoot 挂树拥有，非 static 跨会话共享），
	# 并接线实体仓伤害端口（世界伤害写回 _entities 权威路径）。
	_ensure_spell_world_executor()
	var live: Dictionary = _live_state.get(peer_id, {})
	var origin: Vector3 = live.get("position", Vector3.ZERO)
	var direction: Vector3 = live.get("facing", Vector3(0, 0, -1))
	var effect_plan := ctx.spell_runtime._effect_plan({"implementation": implementation, "spell": spell})
	var authority_execution: Dictionary = spell_auth.execute(ctx.player_node, {"ok": true, "spell_id": spell_id, "imagery": spell.get("imagery", "unknown"), "origin": origin, "direction": direction, "target_hint": command.get("target_hint"), "effect_plan": effect_plan, "visual_event": {}}, ctx.player_node.get_parent(), peer_id)
	# P0-3：世界执行失败（预算满/实施不支持/服务缺失）→ 拒绝，法力与冷却均不提交。
	if not bool(authority_execution.get("ok", false)):
		return _reject(NP.ERR_INVALID_STATE)
	# P0-1-A：movement 位移以 caster（权威物理体）实际落点为真相，同步 _live_state
	# 权威位置——否则后续 player_snapshot 会把位移回弹覆盖。
	if implementation == "movement" and ctx.player_node != null and is_instance_valid(ctx.player_node):
		set_player_position(peer_id, ctx.player_node.global_position)
	# verify：ray 命中实体时，端口写回事件（snapshot/despawn/掉落）提升为 extra_events，
	# 由 NetworkManager 统一广播（P0-1-C 事件 outbox：ray 在施法响应窗口内同步出口）。
	var extra: Array = []
	var world_execution: Dictionary = authority_execution.get("world_execution", {})
	var port_result: Dictionary = world_execution.get("port_result", {})
	var port_events = port_result.get("events", [])
	if port_events is Array:
		for ev in port_events:
			if ev is Dictionary and not (ev as Dictionary).is_empty():
				extra.append(ev)
	# P1（2124 审查）：会话跟踪法术投射物（生命周期随会话，不残留全局池）。
	if implementation == "projectile" and authority_execution.has("projectile"):
		track_projectile(authority_execution["projectile"] as Node)
	# ---- commit（执行成功后才扣资源）----
	ctx.spell_mana -= mana_cost
	ctx.spell_runtime.commit_authoritative_cooldown(spell)
	var evt := {
		"event": NP.EVT_SPELL_RESOLVED,
		"peer_id": peer_id,
		"slot_index": slot_index,
		"spell_id": spell_id,
		"imagery": String(spell.get("imagery", "unknown")),
		"implementation": implementation,
		"origin": origin,
		"direction": direction,
		"color": spell.get("color", Color.WHITE),
		"mana_spent": mana_cost,
		"mana_remaining": ctx.spell_mana,
		"cooldown_ms": ctx.spell_runtime.remaining_cooldown_ms(spell_id),
		"authority_execution": authority_execution,
		"world_execution": world_execution,
		"effects": {
			"healed": int(authority_execution.get("healed", 0)),
			"absorb": int(authority_execution.get("absorb", 0)),
			"duration": float(authority_execution.get("duration", 0.0)),
			"distance": float(authority_execution.get("distance", 0.0)),
		},
	}
	# ---- publish ----
	session_event.emit(evt)
	return {"success": true, "event": evt, "error_code": "", "extra_events": extra}

## P0-3：确保会话级世界执行器存在（挂为 SessionRoot 子节点，随会话生命周期释放），
## 并把实体仓伤害端口接到本会话（世界伤害写回 _entities → 生命/死亡/掉落复制事件）。
## P0（2124 审查）：同时注入 per-peer 自目标效果端口（heal/barrier/buff 权威状态）。
func _ensure_spell_world_executor() -> void:
	var ex: Node = spell_auth.get_world_executor()
	if ex == null or not is_instance_valid(ex):
		var executor := SpellWorldExecutorClass.new()
		executor.name = "SpellWorldExecutor"
		add_child(executor)
		spell_auth.set_world_executor(executor)
		ex = executor
	if "damage_entity_port" in ex:
		ex.damage_entity_port = _spell_damage_entity
	# P0（2218 审查）：会话权威目标查询端口（召唤物自动寻敌——查实体仓而非表现组）。
	if "query_targets_port" in ex:
		ex.query_targets_port = _query_spell_targets
	spell_auth.set_self_effect_port(_apply_self_effect)

## P0（2218 审查）：会话权威法术目标查询——返回范围内可受击敌人（kind=enemy 且存活）。
## 供召唤物/范围法术选择目标；位置来自服务器权威实体仓（不依赖表现层 group）。
func _query_spell_targets(origin: Vector3, range: float) -> Array:
	var out: Array = []
	for eid in _entities.keys():
		var data: Dictionary = _entities[eid]
		if String(data.get("kind", "")) != "enemy":
			continue
		if int(data.get("current_life", 0)) <= 0:
			continue
		var pos: Vector3 = data.get("position", Vector3.ZERO)
		if origin.distance_to(pos) <= range:
			out.append({"entity_id": int(eid), "position": pos})
	return out

## P0（2124 审查）：per-peer 自目标法术效果端口——
## 写 PlayerContext 权威战斗状态（真实生命/护盾/buff），并对绑定节点的真实组件做表现同步
## （房主真实 Player 有 health/buffs；远端 avatar 无组件则只记权威状态，施法成功）。
func _apply_self_effect(peer_id: int, effect_type: String, amount: int, duration: float) -> void:
	var ctx: PlayerContextClass = registry.get_context(peer_id)
	if ctx == null:
		return
	var life_before: int = ctx.current_life
	ctx.record_spell_effect(effect_type, amount, duration)
	# P0（2331 审查）：自目标法术改变战斗状态 → 立即广播（客户端 HUD/角色镜像）。
	broadcast_player_combat_state(peer_id)
	var node: Node = ctx.player_node
	if node == null or not is_instance_valid(node):
		return
	match effect_type:
		"heal":
			# 表现同步：按【真实生命变化量】heal 节点组件（房主真实 Player）。
			var healed: int = ctx.current_life - life_before
			if healed > 0 and "health" in node and node.health != null and node.health.has_method("heal"):
				node.health.heal(healed)
		"barrier":
			if "buffs" in node and node.buffs != null and node.buffs.has_method("add"):
				var max_life := int(node.health.max_life) if "health" in node and node.health != null else 100
				var absorb_pct := float(amount) / float(maxi(max_life, 1)) * 100.0
				node.buffs.add("damage_absorb", duration, {"percent": absorb_pct})
		"buff":
			if "buffs" in node and node.buffs != null and node.buffs.has_method("add"):
				node.buffs.add("spell_power", duration, {"percent": 20.0})

## P0（2218 审查）：对某 peer 玩家施加权威伤害（敌方/环境伤害入口，阶段 B 敌人 AI 完成后调用）。
## 经 PlayerContext.apply_damage（先扣盾再扣命）；死亡广播 player_despawned 语义由调用方决定。
## 返回 {"life_lost": int, "shield_used": int, "killed": bool}。
func apply_damage_to_player(peer_id: int, damage: int) -> Dictionary:
	var ctx: PlayerContextClass = registry.get_context(peer_id)
	if ctx == null or damage <= 0:
		return {"life_lost": 0, "shield_used": 0, "killed": false}
	var shield_before: int = ctx.shield
	var life_lost: int = ctx.apply_damage(damage)
	var shield_used: int = shield_before - ctx.shield
	# 表现同步：房主真实 Player 受击节点。
	var node: Node = ctx.player_node
	if node != null and is_instance_valid(node) and life_lost > 0 \
			and "health" in node and node.health != null and node.health.has_method("take_damage"):
		node.health.take_damage(life_lost)
	var killed: bool = not ctx.is_alive()
	# P0（2331 审查）：受伤/死亡即发布战斗状态事件（客户端 HUD/角色镜像）。
	broadcast_player_combat_state(peer_id)
	return {"life_lost": life_lost, "shield_used": shield_used, "killed": killed}

## P0（2331 审查）：广播某玩家的权威战斗状态事件（reliable）。
## 含 current_life/max_life/shield/buffs/spell_mana 与递增 revision——客户端据此镜像
## 本地 Player/HUD（只读应用，不允许反向写服务器）。
func broadcast_player_combat_state(peer_id: int) -> void:
	var ctx: PlayerContextClass = registry.get_context(peer_id)
	if ctx == null:
		return
	_combat_state_revision[peer_id] = int(_combat_state_revision.get(peer_id, 0)) + 1
	var evt := {
		"event": NP.EVT_PLAYER_COMBAT_STATE,
		"peer_id": peer_id,
		"revision": int(_combat_state_revision[peer_id]),
		"current_life": ctx.current_life,
		"max_life": ctx.max_life,
		"shield": ctx.shield,
		"buffs": ctx.buffs.duplicate(),
		"spell_mana": ctx.spell_mana,
		"spell_max_mana": ctx.spell_max_mana,
	}
	session_event.emit(evt)

## P0（2331 审查）：服务器权威敌人攻击模拟——遍历存活 enemy 实体，对近战范围内的
## 在线玩家周期性造成伤害（经 apply_damage_to_player 权威链）。由 NetworkManager.tick 调用。
## 每敌人维护 next_attack_at（实体 data 字段，服务器时间秒）。返回攻击事件数。
func tick_enemy_combat(now: float = -1.0) -> int:
	if now < 0.0:
		now = current_time
	var attacks := 0
	for eid in _entities.keys():
		var data: Dictionary = _entities[eid]
		if String(data.get("kind", "")) != "enemy":
			continue
		if int(data.get("current_life", 0)) <= 0:
			continue
		if float(data.get("next_attack_at", 0.0)) > now:
			continue
		var epos: Vector3 = data.get("position", Vector3.ZERO)
		var target_peer := 0
		var best := ENEMY_ATTACK_RANGE
		for pid in _live_state.keys():
			var ls: Dictionary = _live_state.get(pid, {})
			if not bool(ls.get("is_alive", false)):
				continue
			var ppos: Vector3 = ls.get("position", Vector3.ZERO)
			var d := epos.distance_to(ppos)
			if d <= best:
				best = d
				target_peer = int(pid)
		if target_peer == 0:
			continue
		_entities[eid]["next_attack_at"] = now + ENEMY_ATTACK_INTERVAL
		var res: Dictionary = apply_damage_to_player(target_peer, ENEMY_ATTACK_DAMAGE)
		if res.get("killed", false):
			set_player_alive(target_peer, false)
		attacks += 1
	return attacks

## P0（2218 审查）：推进所有在线玩家 buff 过期（服务器 tick 调用）。
func tick_player_buffs(now_ms: int = -1) -> void:
	if now_ms < 0:
		now_ms = Time.get_ticks_msec()
	for pid in registry.peer_ids():
		var ctx: PlayerContextClass = registry.get_context(pid)
		if ctx != null:
			ctx.expire_buffs(now_ms)

## P0-3：法术世界伤害写回权威实体仓（与普通攻击同路径）：
##   扣血 → 死亡（掉落 + despawn） / 存活（entity_snapshot）。
## 返回 {ok, killed, events}（events 为复制事件，供发布端广播）。
func _spell_damage_entity(entity_id: int, damage: int, caster_peer: int) -> Dictionary:
	var out := {"ok": false, "killed": false, "events": []}
	if damage <= 0 or not _entities.has(entity_id):
		return out
	# P0（2218 审查）：施法者权威 buff（spell_power）影响法术结算——乘算伤害。
	# 远端 PlayerContext 的 buff 是权威真值；无 buff 时倍率 1.0。
	var ctx: PlayerContextClass = registry.get_context(caster_peer)
	if ctx != null:
		damage = int(round(float(damage) * ctx.spell_power_mult()))
	if damage <= 0:
		return out
	var data: Dictionary = _entities[entity_id]
	var new_life: int = int(data.get("current_life", 0)) - damage
	var events: Array = []
	if new_life <= 0:
		var loot_events: Array = _on_entity_killed(entity_id, caster_peer)
		var dres: Dictionary = remove_entity(entity_id)
		if bool(dres.get("success", false)):
			events.append(dres["event"])
		for le in loot_events:
			events.append(le)
		out["killed"] = true
	else:
		var ures: Dictionary = update_entity(entity_id, {"current_life": new_life})
		if bool(ures.get("success", false)):
			events.append(ures["event"])
	out["ok"] = true
	out["events"] = events
	return out

## P0-1-C：排空 field/summon 异步 tick 产生的实体复制事件（outbox）。
## 由 NetworkManager.tick 定期调用并广播；返回事件数组。
func poll_spell_world_events() -> Array:
	var ex: Node = spell_auth.get_world_executor()
	if ex == null or not is_instance_valid(ex):
		return []
	if ex.has_method("drain_pending_events"):
		return ex.drain_pending_events()
	return []

## P1（2124 审查）：周期权威实体基线——对全部实体生成 entity_snapshot 事件。
## entity_snapshot 走 unreliable 通道，丢包后若实体不再变化，客户端 HP 会永久停留旧值；
## 服务器每 ENTITY_BASELINE_INTERVAL 广播一次全量权威基线（reliable），保证收敛。
func build_entity_baseline_events() -> Array:
	var events: Array = []
	for eid in _entities.keys():
		var data: Dictionary = _entities[eid]
		events.append({
			"event": NP.EVT_ENTITY_SNAPSHOT,
			"entity_id": int(eid),
			"data": {
				"current_life": int(data.get("current_life", 0)),
				"max_life": int(data.get("max_life", 0)),
				"position": data.get("position", Vector3.ZERO),
				"kind": String(data.get("kind", "")),
				"consumed": bool(data.get("consumed", false)),
			},
		})
	return events

## 施法资格纯逻辑校验（P0-5）：读取权威 loadout 的激活武器，经 SpellAccessPolicy
## 检查法杖/魔导书/奥法之剑资格；奥法之剑被动来自 per-peer SkillRuntime（服务器权威）。
## 无 WeaponRegistry（headless 纯逻辑单测）时返回 true——资格校验由带场景的测试覆盖。
func _validate_spell_access(ctx: PlayerContextClass) -> bool:
	var reg := _weapon_registry()
	if reg == null:
		return true
	var weapon_id: String = ctx.loadout.get_weapon_slot(ctx.loadout.active_weapon_slot)
	var weapon = reg.get_weapon_data(weapon_id) if not weapon_id.is_empty() else null
	if weapon == null:
		return false
	var has_arcane_sword := false
	if ctx.skills != null and ctx.skills.has_method("has_mechanism_passive"):
		has_arcane_sword = ctx.skills.has_mechanism_passive(SpellAccessPolicyClass.ARCANE_SWORD_PASSIVE_ID)
	return SpellAccessPolicyClass.can_use_spell_interface(weapon, has_arcane_sword)


## 客户端提交升级选择意图（P1-4 权威闭环）：服务器校验 pending 次数/候选合法性后应用，
## 应用成功广播 EVT_PROGRESSION_CHANGED；失败不消耗任何升级机会。客户端面板
## 只发送意图，绝不直接修改服务器权威属性。
func _handle_level_up_choice(command: Dictionary, ctx: PlayerContextClass) -> Dictionary:
	var peer_id: int = int(_ctx_peer.get(ctx.get_instance_id(), 0))
	if not _seq_tracker.accept(peer_id, int(command.get("sequence", 0))):
		return _reject(NP.ERR_INVALID_SEQUENCE)
	var intent := {
		"kind": String(command.get("kind", "")),
		"attr_key": String(command.get("attr_key", "")),
		"rune_id": String(command.get("rune_id", "")),
	}
	var res: Dictionary = ProgressionAuthorityClass.apply_level_up_choice(ctx.attributes, ctx.inventory, intent)
	if not bool(res.get("ok", false)):
		return _reject(String(res.get("error_code", NP.ERR_INVALID_TARGET)))
	var evt := _progression_event(peer_id, ctx)
	session_event.emit(evt)
	return {"success": true, "event": evt, "error_code": ""}

## 客户端请求本次升级的符文候选：服务器按 player_guid 确定性掷出（重连/回放同一组），
## 经 EVT_PROGRESSION_RUNE_CANDIDATES 下发；候选锁定在权威 AttrPanel。
func _handle_level_up_rune_candidates(command: Dictionary, ctx: PlayerContextClass) -> Dictionary:
	var peer_id: int = int(_ctx_peer.get(ctx.get_instance_id(), 0))
	if not _seq_tracker.accept(peer_id, int(command.get("sequence", 0))):
		return _reject(NP.ERR_INVALID_SEQUENCE)
	var candidates: Array = ProgressionAuthorityClass.roll_rune_candidates(ctx.attributes, _peer_guid(peer_id, ctx))
	if candidates.is_empty():
		return _reject(NP.ERR_INVALID_STATE)
	var evt := {
		"event": NP.EVT_PROGRESSION_RUNE_CANDIDATES,
		"peer_id": peer_id,
		"candidates": candidates,
	}
	session_event.emit(evt)
	return {"success": true, "event": evt, "error_code": ""}

## 权威成长状态事件（P1-4）：killer/选择者 peer 的等级/经验/待升级队列快照。
func _progression_event(peer_id: int, ctx: PlayerContextClass) -> Dictionary:
	var attrs = ctx.attributes
	return {
		"event": NP.EVT_PROGRESSION_CHANGED,
		"peer_id": peer_id,
		"level": int(attrs.get_level()) if attrs != null else 1,
		"level_exp": int(attrs.level_exp) if attrs != null else 0,
		"threshold": int(attrs.get_level_upgrade_threshold()) if attrs != null else 100,
		"pending_level_choices": int(attrs.get_pending_level_choices()) if attrs != null else 0,
	}

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

## 客户端请求装备物品：服务器校验物品确在该玩家背包内（权威），再经唯一装备策略
## EquipmentPolicy 解析类别/槽位兼容/占槽关系后写入 loadout 槽位（架构审查 P0-4）。
## 协议：slot_kind("weapon"/"armor") + slot_index(int)/slot_name(String)；兼容旧版 slot
## （int=武器槽 / String=护甲槽名）。材料/符文/未知物品一律拒绝——绝不污染权威 loadout。
func _handle_equip(command: Dictionary, ctx: PlayerContextClass) -> Dictionary:
	var peer_id: int = int(_ctx_peer.get(ctx.get_instance_id(), 0))
	if not _seq_tracker.accept(peer_id, int(command.get("sequence", 0))):
		return _reject(NP.ERR_INVALID_SEQUENCE)
	var item_id: String = String(command.get("item_id", ""))
	# 新协议：slot_kind + slot_index/slot_name；旧协议 slot（int/string）兼容解析。
	var slot_kind: String = String(command.get("slot_kind", ""))
	var slot_index: int = int(command.get("slot_index", -1))
	var slot_name: String = String(command.get("slot_name", ""))
	var legacy_slot = command.get("slot", null)
	if legacy_slot is int:
		slot_kind = "weapon"
		slot_index = int(legacy_slot)
	elif legacy_slot is String:
		slot_kind = "armor"
		slot_name = String(legacy_slot)
	if item_id.is_empty():
		return _reject(NP.ERR_INVALID_TARGET)
	# 物品必须在该玩家背包内（权威），否则视为非法请求。
	var inv = ctx.inventory
	var owned: bool = (inv.materials.has(item_id) or inv.runes.has(item_id) or inv.equipment.has(item_id))
	if not owned:
		return _reject(NP.ERR_INVALID_TARGET)
	var lo = ctx.loadout
	# P0-4：唯一装备策略（类别/槽位兼容/双手↔盾互斥/唯一性），拒绝任何非装备污染槽位。
	var res: Dictionary = EquipmentPolicyClass.resolve(item_id, slot_kind, slot_index, slot_name,
		lo, _equipment_data_source())
	if not bool(res.get("ok", false)):
		return _reject(NP.ERR_INVALID_TARGET)
	var ok: bool = false
	if String(res["slot_kind"]) == EquipmentPolicyClass.SLOT_KIND_WEAPON:
		ok = lo.set_weapon_slot(int(res["slot_index"]), item_id)
	else:
		ok = lo.set_armor_slot(String(res["slot_name"]), item_id)
	if not ok:
		return _reject(NP.ERR_INVALID_TARGET)
	var evt := {
		"event": NP.EVT_EQUIPMENT_CHANGED,
		"peer_id": peer_id,
		"item_id": item_id,
		"slot_kind": res["slot_kind"],
		"slot_index": res["slot_index"],
		"slot_name": res["slot_name"],
	}
	return {"success": true, "event": evt, "error_code": ""}

## 装备策略数据源（P0-4）：从 WeaponRegistry 解析物品类别/手位/护甲部位。
## 可由测试注入 stub（headless 无 autoload）。
var _equipment_data_source_custom: Callable = Callable()

func _equipment_data_source() -> Callable:
	if _equipment_data_source_custom.is_valid():
		return _equipment_data_source_custom
	var reg := _weapon_registry()
	if reg == null or not reg.has_method("get_weapon_data"):
		return EquipmentPolicyClass.DEFAULT_DATA_SOURCE
	return func(item_id: String) -> Dictionary:
		var wd = reg.get_weapon_data(item_id)
		if wd == null:
			return {}
		return {"category": String(wd.equipment_category), "hands": String(wd.hands),
			"armor_slot": String(wd.armor_slot)}

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
	# P1-1：结算成功 → 把该玩家当前权威状态（背包/装配/法术）写回服务器存档仓，
	# 作为其下次 spawn 的可信来源（服务器持久化闭环；客户端不参与写入）。
	if server_save_repo != null:
		server_save_repo.save_save(guid, _build_server_save_state(ctx))
	var evt := {
		"event": NP.EVT_EXTRACTION_RESULT,
		"peer_id": peer_id,
		"settlement": settlement,
		"already_settled": false,
		"requested_save": requested_save,
	}
	return {"success": true, "event": evt, "error_code": ""}

## P1-1：构建服务器存档仓快照（与 GameState.build_network_save_state 同构：
## materials(三类字典)/loadout/spell_state/attributes/skills）。
func _build_server_save_state(ctx: PlayerContextClass) -> Dictionary:
	var state := {
		"materials": ctx.inventory.materials.duplicate(),
		"loadout": ctx.loadout.to_dict(),
		"spell_state": ctx.serialize_spell_state(),
	}
	if ctx.attributes != null and ctx.attributes.has_method("serialize"):
		state["attributes"] = ctx.attributes.serialize()
	if ctx.skills != null and ctx.skills.has_method("serialize"):
		state["skills"] = ctx.skills.serialize()
	return state

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
## P1-4：附带 attributes 权威快照（联机期间获得的经验/升级/熟练度），
## 由桥接层在结算写回时应用到单人存档，保证联机成长带回酒馆。
## 返回 {materials:{id:amt}, runes:{id:amt}, equipment:{id:amt}, attributes:{...}}（仅含净增加项）。
func _compute_settlement(peer_id: int) -> Dictionary:
	var ctx: PlayerContextClass = registry.get_context(peer_id)
	if ctx == null or ctx.inventory == null:
		return {"materials": {}, "runes": {}, "equipment": {}, "attributes": {}}
	var cur: Dictionary = ctx.inventory.to_dict()
	var base: Dictionary = _inventory_baseline.get(peer_id, {"materials": {}, "runes": {}, "equipment": {}})
	var out: Dictionary = {"materials": {}, "runes": {}, "equipment": {}, "attributes": {}}
	for cat in ["materials", "runes", "equipment"]:
		var c: Dictionary = cur.get(cat, {})
		var b: Dictionary = base.get(cat, {})
		for k in c.keys():
			var delta: int = int(c[k]) - int(b.get(k, 0))
			if delta > 0:
				out[cat][k] = delta
	if ctx.attributes != null and ctx.attributes.has_method("serialize"):
		out["attributes"] = ctx.attributes.serialize()
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
		var ctx: PlayerContextClass = registry.get_context(pid)
		players.append({
			"peer_id": pid,
			"is_alive": bool(ls.get("is_alive", true)),
			"position": ls.get("position", Vector3.ZERO),
			"spell_state": ctx.serialize_spell_state() if ctx != null else {},
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
	if snap.has("players"):
		for player_data in snap["players"]:
			if player_data is Dictionary and player_data.has("spell_state"):
				var ctx: PlayerContextClass = registry.get_context(int(player_data.get("peer_id", 0)))
				if ctx != null:
					ctx.deserialize_spell_state(Dictionary(player_data.spell_state))
