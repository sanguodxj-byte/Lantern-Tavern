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
const EnemyCombatAuthorityClass := preload("res://globals/multiplayer/enemy_combat_authority.gd")
const SessionExpeditionServiceClass := preload("res://globals/multiplayer/session_expedition_service.gd")
const SessionCombatServiceClass := preload("res://globals/multiplayer/session_combat_service.gd")
const SessionLifecycleServiceClass := preload("res://globals/multiplayer/session_lifecycle_service.gd")
const SessionProgressionServiceClass := preload("res://globals/multiplayer/session_progression_service.gd")
const SessionInventoryServiceClass := preload("res://globals/multiplayer/session_inventory_service.gd")
const SkillAuthorityClass := preload("res://globals/multiplayer/skill_authority.gd")
const PhysicsSetupClass := preload("res://globals/core/physics_setup.gd")

signal session_event(event: Dictionary)
signal player_registered(peer_id: int)
signal player_spawned(peer_id: int)
signal player_unregistered(peer_id: int)

## A1（架构审查 P0）：标记「经 session_event 单一出口广播」的事件 kind。
## 网络层把 session.session_event 接线为会话内异步事件的统一出口（节流/RPC 下发）；
## 命令返回路径（NetworkManager._server_handle_command）对命中此集合的 kind 跳过二次下发，
## 保证每个逻辑事件恰好下发一次（其余事件仍走命令返回路径下发）。
## EVT_DUNGEON_LAYOUT 等事件以 "type" 键携带 kind，调用方需兼容两种键读取。
static func is_outbox_event(kind: String) -> bool:
	return kind in [NP.EVT_PLAYER_DESPAWNED, NP.EVT_SESSION_SNAPSHOT, NP.EVT_COMMAND_REJECTED,
		NP.EVT_DUNGEON_LAYOUT, NP.EVT_SPELL_RESOLVED, NP.EVT_PLAYER_COMBAT_STATE,
		NP.EVT_PROGRESSION_CHANGED, NP.EVT_PROGRESSION_RUNE_CANDIDATES,
		NP.EVT_SKILL_STATE_CHANGED]

var registry: PlayerRegistryClass
var world: WorldStateClass
var router: CommandRouterClass
var validator: CommandValidatorClass
var is_server: bool = false
## 房主 peer_id（P1-4/0304 审查）：由 NetworkManager 在 host() 时设置（= local_peer_id）。
## 0 = 服务器自身发起（dedicated 直调 start_expedition_authoritatively，不走命令路由）。
var host_peer_id: int = 0
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
var skill_auth: SkillAuthorityClass
var expedition_service: SessionExpeditionServiceClass
var combat_service: SessionCombatServiceClass
var inventory_service: SessionInventoryServiceClass
var progression_service: SessionProgressionServiceClass
var lifecycle_service: SessionLifecycleServiceClass
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
# 由 NetworkManager 注入。B2（0644 审查 / 决策 G1-A）：这是权威存档的【唯一来源】——
# 远端客户端只上送 guid，服务器按 guid 从本仓加载；仓无记录才回退调用方摘要（仅房主
# 本地路径 spawn_self 提供）或默认上下文。null 时退回「仅调用方传入摘要」的旧行为（测试/无仓环境）。
var server_save_repo: ServerSaveRepositoryClass = null
# P1（2124 审查）：会话拥有的法术投射物清单——会话销毁时统一回收，
# 避免全局对象池/场景切换残留跨会话的端口与节点。
var _session_projectiles: Array = []
# P0（2331 审查）：玩家战斗状态事件 revision（peer_id -> int，递增去重/顺序）。
var _combat_state_revision: Dictionary = {}
# A2（架构审查 P0）：权威敌人攻击模拟委托给 EnemyCombatAuthority——攻击参数（射程/间隔/伤害）
# 从敌人实体 data / 可配置 profile 派生，视线经 ray 检查，每敌人独立 next_attack_at 节奏，
# 绝不在会话层硬编码裸常量（旧 ENEMY_ATTACK_INTERVAL/RANGE/DAMAGE 已迁入 authority 默认 profile）。
var enemy_combat_auth: EnemyCombatAuthorityClass

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
	enemy_combat_auth = EnemyCombatAuthorityClass.new()
	skill_auth = SkillAuthorityClass.new()
	# ADR-003 渐进拆分：出征/结算/存档编排服务（构造注入本节点引用）。
	expedition_service = SessionExpeditionServiceClass.new(self)
	# ADR-003 渐进拆分：战斗命令编排服务（attack/cast/skill + 战斗副作用端口）。
	combat_service = SessionCombatServiceClass.new(self)
	# ADR-003 渐进拆分：装备/拾取/丢弃命令编排服务。
	inventory_service = SessionInventoryServiceClass.new(self)
	# ADR-003 渐进拆分：成长命令编排服务。
	progression_service = SessionProgressionServiceClass.new(self)
	# ADR-003 渐进拆分：会话生命周期编排服务（spawn/断线/重连/离开）。
	lifecycle_service = SessionLifecycleServiceClass.new(self)

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














## ---- ADR-003 生命周期服务公共 API 委托（实现见 SessionLifecycleService）----
func handle_spawn_request(peer_id: int, save_state: Dictionary = {}, player_guid: String = "") -> PlayerContextClass:
	return lifecycle_service.handle_spawn_request(peer_id, save_state, player_guid)

func register_player(peer_id: int, ctx: PlayerContextClass, player = null, position: Vector3 = Vector3.ZERO) -> void:
	lifecycle_service.register_player(peer_id, ctx, player, position)

func bind_player_entity(peer_id: int, player_entity: Node3D) -> bool:
	return lifecycle_service.bind_player_entity(peer_id, player_entity)

func unregister_player(peer_id: int) -> void:
	lifecycle_service.unregister_player(peer_id)

func heartbeat(peer_id: int, now: float = -1.0) -> void:
	lifecycle_service.heartbeat(peer_id, now)

func handle_peer_disconnected(peer_id: int, now: float = -1.0) -> Dictionary:
	return lifecycle_service.handle_peer_disconnected(peer_id, now)

func handle_peer_left(peer_id: int) -> void:
	lifecycle_service.handle_peer_left(peer_id)

func tick_connections(now: float = -1.0) -> Array:
	return lifecycle_service.tick_connections(now)

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

# ============================================================================
# 窄端口访问器（1727 审查 P2-3 / 2026-08-06 汇总 #1）：
# Session 服务经端口访问共享状态容器，禁止直接触碰 _r._private_field。
# 字典返回引用（GDScript 引用传递），端口读写与直接访问等价。
# ============================================================================

## 权威玩家状态容器（position/facing/is_alive 等）——共享状态容器端口。
func live_state() -> Dictionary:
	return _live_state

## 权威实体仓（敌人/掉落/宝箱）——共享状态容器端口。
func entities() -> Dictionary:
	return _entities

## ctx 实例 → peer_id 反向索引——共享状态容器端口。
func ctx_peer() -> Dictionary:
	return _ctx_peer

## 命令序列跟踪器（防重放/乱序）——共享状态容器端口。
func seq_tracker():
	return _seq_tracker

## 出征背包基线（结算净获得计算）——共享状态容器端口。
func inventory_baseline() -> Dictionary:
	return _inventory_baseline

## 攻击冷却表——共享状态容器端口。
func attack_cd_until() -> Dictionary:
	return _attack_cd_until

## 硬直表——共享状态容器端口。
func stagger() -> Dictionary:
	return _stagger

## per-peer 属性/技能状态节点——共享状态容器端口。
func peer_state_nodes() -> Dictionary:
	return _peer_state_nodes

## per-peer 状态节点挂载根——共享状态容器端口。
func peer_state_root() -> Node:
	return _peer_state_root

## 掉落序号递增并返回新值（确定性种子来源）——共享状态容器端口。
func next_loot_seq() -> int:
	_loot_seq += 1
	return _loot_seq

## 当前掉落序号（只读；用于确定性种子）——共享状态容器端口。
func loot_seq() -> int:
	return _loot_seq

## 结构变更广播（递增 world_revision）——操作端口。
func bump_world(space := "") -> int:
	return _bump_world(space)

## 命令拒绝结果构造——操作端口。
func reject(error_code: String) -> Dictionary:
	return _reject(error_code)

## WeaponRegistry 解析（headless 单测返回 null）——操作端口。
func weapon_registry() -> Object:
	return _weapon_registry()

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

## 挂载默认权威处理器（服务器初始化时调用）。ADR-003 拆分后部分命令族委托给服务。
func wire_default_authorities() -> void:
	register_authority(NP.CMD_INTERACT, inventory_service.handle_interaction)
	register_authority(NP.CMD_PICKUP, inventory_service.handle_interaction)
	register_authority(NP.CMD_ATTACK, combat_service.handle_combat)
	register_authority(NP.CMD_INPUT, _handle_movement)
	register_authority(NP.CMD_EXPEDITION, expedition_service.handle_start_expedition)
	register_authority(NP.CMD_REQUEST_LAYOUT, _handle_layout_request)
	register_authority(NP.CMD_EXTRACT, expedition_service.handle_extract)
	register_authority(NP.CMD_RESUME, lifecycle_service.handle_resume)
	register_authority(NP.CMD_SKILL, combat_service.handle_skill)
	register_authority(NP.CMD_CAST_SPELL, combat_service.handle_cast_spell)
	register_authority(NP.CMD_EQUIP, inventory_service.handle_equip)
	register_authority(NP.CMD_DROP, inventory_service.handle_drop)
	register_authority(NP.CMD_SAVE, expedition_service.handle_save)
	register_authority(NP.CMD_LEAVE, _handle_leave)
	register_authority(NP.CMD_LEVEL_UP_CHOICE, progression_service.handle_level_up_choice)
	register_authority(NP.CMD_LEVEL_UP_RUNE_CANDIDATES, progression_service.handle_level_up_rune_candidates)




## 解析 WeaponRegistry（autoload）。无场景树（headless 单测）时返回 null。
func _weapon_registry() -> Object:
	var tree := Engine.get_main_loop()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("WeaponRegistry")


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


## 出征唯一权威事务入口（委托 SessionExpeditionService；ADR-003 拆分）。
## 生产入口（房主本地 MultiplayerSession）与命令路由 CMD_EXPEDITION 共用同一事务。
func start_expedition_authoritatively(seed_hint: int = -1) -> Dictionary:
	return expedition_service.start_expedition_authoritatively(seed_hint)

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

## P0（2331 审查 / A2 架构审查）：服务器权威敌人攻击模拟——遍历存活 enemy 实体，
## 委托 EnemyCombatAuthority 做攻击决策（射程/间隔/伤害来自实体 data 或可配置 profile，
## 视线经 ray 检查，每敌人独立 next_attack_at 节奏），命中后经 apply_damage_to_player 权威链
## 造成伤害（先扣盾再扣命）。由 NetworkManager.tick 调用。返回攻击事件数。
func tick_enemy_combat(now: float = -1.0) -> int:
	if now < 0.0:
		now = current_time
	_ensure_enemy_combat_authority()
	var attacks := 0
	for eid in _entities.keys():
		var data: Dictionary = _entities[eid]
		if String(data.get("kind", "")) != "enemy":
			continue
		if int(data.get("current_life", 0)) <= 0:
			continue
		var decision: Dictionary = enemy_combat_auth.decide_attack(data, _live_players_snapshot(), now)
		if not bool(decision.get("attack", false)):
			continue
		var target_peer: int = int(decision.get("target_peer", 0))
		if target_peer == 0:
			continue
		# A2：把该敌人的独立攻击节奏写回实体 data（decide_attack 为纯函数，不修改 data）。
		_entities[eid]["next_attack_at"] = float(decision.get("next_attack_at", now))
		var damage: int = int(decision.get("damage", 0))
		if damage <= 0:
			continue
		var res: Dictionary = apply_damage_to_player(target_peer, damage)
		if res.get("killed", false):
			set_player_alive(target_peer, false)
		attacks += 1
	return attacks

## A2：确保权威敌人攻击器存在并接线生产视线查询端口（真实 intersect_ray）。
## 测试可先注入自己的 ray_query stub——此处只在端口未接线时补默认，不覆盖注入。
func _ensure_enemy_combat_authority() -> void:
	if enemy_combat_auth == null:
		enemy_combat_auth = EnemyCombatAuthorityClass.new()
	if not enemy_combat_auth.ray_query.is_valid():
		enemy_combat_auth.ray_query = _enemy_los_query

## A2（架构审查 P0）：敌人→玩家视线查询（生产接线）。
## PhysicsDirectSpaceState3D.intersect_ray；collision_mask 用视野遮挡层
## （环境+场景物体，physics_setup.MASK_VISION_OBSTRUCTION）——玩家/敌人本就不在该 mask，
## 射线天然只测墙/家具等遮挡（与 spell_world_executor 的 ray 查询同模式）。
## headless/无场景时返回空字典（视为无遮挡，保持旧行为不回归）。
func _enemy_los_query(from: Vector3, to: Vector3) -> Dictionary:
	var main_loop: MainLoop = Engine.get_main_loop()
	if main_loop == null:
		return {}
	var scene_tree: SceneTree = main_loop as SceneTree
	if scene_tree == null:
		return {}
	var root: Window = scene_tree.root
	if root == null:
		return {}
	var world: World3D = root.get_world_3d()
	if world == null:
		return {}
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	if space == null:
		return {}
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = PhysicsSetupClass.MASK_VISION_OBSTRUCTION
	return space.intersect_ray(query)

## A2：构造权威敌人攻击的在线玩家快照数组（peer_id/position/is_alive，来自服务器权威 _live_state）。
func _live_players_snapshot() -> Array:
	var out: Array = []
	for pid in _live_state.keys():
		var ls: Dictionary = _live_state[pid]
		out.append({
			"peer_id": int(pid),
			"position": ls.get("position", Vector3.ZERO),
			"is_alive": bool(ls.get("is_alive", false)),
		})
	return out

## P0（2218 审查 / A4 架构审查）：推进所有在线玩家 buff 过期（服务器 tick 调用）。
## A4：expire_buffs 返回被清除的 buff id 列表——任一 buff 过期即该 peer 战斗状态变更，
## 必须广播 EVT_PLAYER_COMBAT_STATE（否则客户端 HUD/角色镜像的 buff 条目残留到过期后）。
func tick_player_buffs(now_ms: int = -1) -> void:
	if now_ms < 0:
		now_ms = Time.get_ticks_msec()
	for pid in registry.peer_ids():
		var ctx: PlayerContextClass = registry.get_context(pid)
		if ctx == null:
			continue
		var expired: Array = ctx.expire_buffs(now_ms)
		if not expired.is_empty():
			broadcast_player_combat_state(pid)


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








## 装备策略数据源（P0-4）：从 WeaponRegistry 解析物品类别/手位/护甲部位。
## 可由测试注入 stub（headless 无 autoload）。






## 服务器权威存档 schema 版本（1122 审查 P1-3）：加载时未知未来版本硬拒绝。
const SERVER_SAVE_SCHEMA_VERSION := 1



## 客户端主动离开（不再重连）：立即清理 PlayerContext 并广播 despawned（委托生命周期服务）。
func _handle_leave(command: Dictionary, ctx: PlayerContextClass) -> Dictionary:
	lifecycle_service.handle_peer_left(int(_ctx_peer.get(ctx.get_instance_id(), 0)))
	return {"success": true, "event": {}, "error_code": ""}


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
