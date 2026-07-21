extends Node
## MultiplayerSceneBridge —— 把权威状态映射到可见场景节点（联机表现层，仅地牢范围）。
##
## 责任（docs/25 §19 / 本轮 ①）：
##   - 监听 NetworkManager.peer_authorized（服务器侧 spawn 成功）→ 服务器生成远端 avatar
##     并经 rpc_spawn_avatar 广播给所有客户端（复制）；
##   - 监听 player_snapshot 事件 → 把权威位置/朝向路由到对应 peer 的 avatar（插值驱动）；
##   - 监听 EVT_PLAYER_DESPAWNED → 销毁对应 avatar。
##
## 为什么不用 MultiplayerSpawner：本 Godot 4.7 构建的 SceneTree 没有 .multiplayer 属性，
## MultiplayerSpawner 内部 _setup_spawn() 依赖 get_tree().get_multiplayer()，导致 spawn_path
## 无法向已连接 peer 注册、复制永不触发。改用本桥接层自带的显式 RPC（authority→call_remote），
## 可靠且完全可控，功能等价（远端玩家可见 + 插值跟随）。
##
## 隔离式设计：只生成/管理【远端玩家】的 avatar，本地玩家仍由真实 Player 控制器驱动，
## 不触碰单人流程（procedural_dungeon / player.gd），符合“联机仅地牢、不破坏单机”。
##
## 不声明 class_name：避免 headless 类注册 / .uid 同步问题；经 preload 引用。

const NP := preload("res://globals/multiplayer/network_protocol.gd")
const NetworkManagerClass := preload("res://globals/core/network_manager.gd")
const DEFAULT_AVATAR := preload("res://scenes/multiplayer/multiplayer_avatar.tscn")
const DEFAULT_ENTITY := preload("res://scenes/multiplayer/multiplayer_entity.tscn")

## avatar 场景（远端玩家可见节点）。可在场景中 override。
@export var avatar_scene: PackedScene = DEFAULT_AVATAR
## 实体场景（敌人/宝箱/门/掉落的可见节点）。可在场景中 override。
@export var entity_scene: PackedScene = DEFAULT_ENTITY

## 远端 avatar 容器（被复制的节点挂在这里）。
@onready var _container: Node3D = $RemoteAvatars
## peer_id -> 该 peer 的远端 avatar 节点（服务器/客户端各自维护）。
var _avatars: Dictionary = {}
## entity_id -> 该实体的可见节点（服务器/客户端各自维护，由 entity_* 事件驱动）。
var _entities: Dictionary = {}
## 实体节点容器（运行时创建；与 avatar 分离，便于清理与查询）。
var _entity_container: Node3D = null

func _ready() -> void:
	# 实体容器（.tscn 只声明 RemoteAvatars，实体容器运行时补建）。
	_entity_container = Node3D.new()
	_entity_container.name = "RemoteEntities"
	add_child(_entity_container)
	var nm: Node = _network_manager()
	if nm != null:
		if nm.has_signal("peer_authorized"):
			nm.peer_authorized.connect(_on_peer_authorized)
		# 服务器侧事件经 event_dispatched；客户端侧经 event_received。
		if nm.has_signal("event_dispatched"):
			nm.event_dispatched.connect(_on_event)
		if nm.has_signal("event_received"):
			nm.event_received.connect(_on_event)

# ---------------------------------------------------------------------------
# 生成 / 复制
# ---------------------------------------------------------------------------

## 服务器侧：一个远端 peer 成功 spawn 后，本地生成其 avatar 并广播给所有客户端。
## 本地 peer（房主本人）不生成 avatar——房主用真实 Player 控制器。
func _on_peer_authorized(peer_id: int, _context) -> void:
	if not _is_server():
		return
	if peer_id == _local_peer_id():
		return
	_spawn_local(peer_id, Vector3.ZERO)
	if _can_rpc():
		rpc_spawn_avatar.rpc(peer_id, Vector3.ZERO)
		# 把【已存在】的远端玩家 avatar 也下发给新接入的客户端，
		# 实现晚到/重连客户端的“真实场景恢复”——能看到会话中既有玩家（非仅房主）。
		for existing in _avatars.keys():
			if existing == peer_id or existing == _local_peer_id():
				continue
			var av: Node3D = _avatars.get(existing, null)
			if av != null:
				rpc_spawn_avatar.rpc_id(peer_id, existing, av.global_position)

## 本地生成某 peer 的 avatar（幂等）。返回节点或 null。
func _spawn_local(peer_id: int, position: Vector3) -> Node3D:
	if peer_id == _local_peer_id():
		return null
	if avatar_scene == null:
		return null
	if _avatars.has(peer_id):
		return _avatars[peer_id]
	var av: Node3D = avatar_scene.instantiate()
	av.name = "Avatar_%d" % peer_id
	av.peer_id = peer_id
	_container.add_child(av)
	av.global_position = position
	_avatars[peer_id] = av
	return av

## 客户端收到：实例化对应 peer 的远端 avatar（服务器已本地生成，不再重复）。
@rpc("authority", "call_remote", "reliable")
func rpc_spawn_avatar(peer_id: int, position: Vector3) -> void:
	if _is_server():
		return  # 服务器已本地生成，避免重复
	_spawn_local(peer_id, position)

# ---------------------------------------------------------------------------
# 快照路由（服务器权威 → 本地可见 + 广播客户端）
# ---------------------------------------------------------------------------

## 事件路由：player_snapshot → 对应 avatar 插值；player_despawned → 销毁。
func _on_event(event: Dictionary) -> void:
	if event.is_empty():
		return
	var kind: String = event.get("event", "")
	match kind:
		NP.EVT_PLAYER_SNAPSHOT:
			var pid: int = int(event.get("peer_id", 0))
			var pos: Vector3 = event.get("position", Vector3.ZERO)
			var yaw: float = float(event.get("look_yaw", 0.0))
			if _is_server():
				# 服务器：更新本地可见的远端 avatar，并广播给客户端。
				var av: Node3D = _avatars.get(pid, null)
				if av != null and av.has_method("apply_snapshot"):
					av.apply_snapshot(pos, yaw)
				if _can_rpc():
					rpc_snapshot.rpc(pid, pos, yaw)
			else:
				# 客户端：直接用快照驱动本地（服务器复制来的）avatar。
				var av: Node3D = _avatars.get(pid, null)
				if av != null and av.has_method("apply_snapshot"):
					av.apply_snapshot(pos, yaw)
		NP.EVT_PLAYER_DESPAWNED:
			_despawn(int(event.get("peer_id", 0)))
		NP.EVT_ENTITY_SPAWNED:
			# 实体事件在服务器/客户端同经 _dispatch_event/rpc_server_event 广播，
			# 故两端都在此生成可见节点（无需像 avatar 那样单独 RPC）。
			_spawn_entity_local(int(event.get("entity_id", 0)), event.get("data", {}))
		NP.EVT_ENTITY_SNAPSHOT:
			_update_entity_local(int(event.get("entity_id", 0)), event.get("data", {}))
		NP.EVT_ENTITY_DESPAWNED:
			_despawn_entity_local(int(event.get("entity_id", 0)))
		NP.EVT_SESSION_SNAPSHOT:
			# 重连/晚到快照落地：把权威实体全集物化为可见节点（幂等，补齐可能漏收的 entity_spawned）。
			if event.has("snapshot"):
				_apply_session_snapshot(event["snapshot"])
		NP.EVT_EXTRACTION_RESULT:
			# 仅本机玩家（peer_id == 本地）的结算结果写回各自的单人存档；
			# 服务器/其他玩家的结算事件由各自进程处理，本进程忽略。
			# already_settled=true 表示服务器判定本次出征已结算过（重复 extract/save），
			# 桥接层跳过写回，杜绝重复累加刷物品（Phase 5 幂等，§17.4 安全测试）。
			if int(event.get("peer_id", -1)) == _local_peer_id() and not bool(event.get("already_settled", false)):
				_apply_extraction_settlement(event.get("settlement", {}))

## 客户端收到：把某 peer 的权威快照应用到本地 avatar（插值由 avatar 自身完成）。
@rpc("authority", "call_remote", "reliable")
func rpc_snapshot(peer_id: int, position: Vector3, yaw: float) -> void:
	if _is_server():
		return
	var av: Node3D = _avatars.get(peer_id, null)
	if av != null and av.has_method("apply_snapshot"):
		av.apply_snapshot(position, yaw)

func _despawn(peer_id: int) -> void:
	var av: Node = _avatars.get(peer_id, null)
	if av != null:
		_avatars.erase(peer_id)
		av.queue_free()

# ---------------------------------------------------------------------------
# 实体复制（敌人/宝箱/门/掉落 → 两端可见节点）
# ---------------------------------------------------------------------------

## 生成/更新某实体的可见节点（幂等：已存在则改走更新，供重播/追平不产生重复节点）。
func _spawn_entity_local(entity_id: int, data: Dictionary) -> Node3D:
	if entity_id == 0 or entity_scene == null:
		return null
	if _entities.has(entity_id):
		_update_entity_local(entity_id, data)
		return _entities[entity_id]
	var ent: Node3D = entity_scene.instantiate()
	ent.name = "Entity_%d" % entity_id
	ent.entity_id = entity_id
	if data.has("kind"):
		ent.kind = String(data["kind"])
	_entity_container.add_child(ent)
	if ent.has_method("apply_spawn"):
		ent.apply_spawn(data)
	_entities[entity_id] = ent
	return ent

## 更新某实体（HP/位置）；节点不存在时按 spawn 兜底（避免 snapshot 早于 spawn 到达丢失）。
func _update_entity_local(entity_id: int, data: Dictionary) -> void:
	var ent: Node = _entities.get(entity_id, null)
	if ent == null:
		_spawn_entity_local(entity_id, data)
		return
	if ent.has_method("apply_snapshot"):
		ent.apply_snapshot(data)

func _despawn_entity_local(entity_id: int) -> void:
	var ent: Node = _entities.get(entity_id, null)
	if ent != null:
		_entities.erase(entity_id)
		if ent.has_method("apply_despawn"):
			ent.apply_despawn()
		else:
			ent.queue_free()

## 测试 / 外部查询：返回某实体的可见节点（未生成/未复制则返回 null）。
func get_entity_node(entity_id: int) -> Node3D:
	return _entities.get(entity_id, null)

## 重连/晚到快照落地：把 snap["entities"] 全集物化为可见节点（幂等，已存在则跳过）。
## 用于（重）接入客户端补齐权威实体，使其真实场景与服务器一致。
func _apply_session_snapshot(snap: Dictionary) -> void:
	if snap == null:
		return
	var authoritative_ids: Dictionary = {}
	if snap.has("entities"):
		var ents: Dictionary = snap["entities"]
		for eid in ents.keys():
			var eid_i: int = int(eid)
			authoritative_ids[eid_i] = true
			_spawn_entity_local(eid_i, ents[eid])
		# 收敛（Phase 10 优化）：重连/晚到客户端的 _entities 可能残留服务器已不存在的
		# 陈旧实体（断线期间被击杀/拾取），仅全量 spawn 会留下“幽灵节点”。按权威快照反查，
		# despawn 任何不在快照中的本地实体。语义与 EntitySyncAuthority.build_delta 的
		# despawn 分支一致；对全新晚到客户端(_entities 为空)为 no-op。
		for local_id in _entities.keys():
			if not authoritative_ids.has(local_id):
				_despawn_entity_local(local_id)
	# 补齐既有玩家 avatar（重连/晚到客户端可靠追平“真实场景”——能看到会话中全部玩家）。
	if snap.has("players"):
		for p in snap["players"]:
			if not (p is Dictionary):
				continue
			var pid: int = int(p.get("peer_id", 0))
			if pid == 0 or pid == _local_peer_id():
				continue
			_spawn_local(pid, p.get("position", Vector3.ZERO))

## 当前已生成的实体数量（测试断言用）。
func entity_count() -> int:
	return _entities.size()

# ---------------------------------------------------------------------------
# 查询 / 工具
# ---------------------------------------------------------------------------

## 测试 / 外部查询：返回某 peer 的远端 avatar（未生成/未复制则返回 null）。
func get_avatar(peer_id: int) -> Node3D:
	return _avatars.get(peer_id, null)

## 测试 / 外部查询：返回全部已物化远端 avatar 的 peer_id 列表（含房主，不含本地自身）。
func get_avatar_peers() -> Array:
	return _avatars.keys()

func _can_rpc() -> bool:
	var nm: Node = _network_manager()
	return nm != null and is_instance_valid(nm.multiplayer) and nm.multiplayer.multiplayer_peer != null

func _is_server() -> bool:
	var nm: Node = _network_manager()
	if nm != null and "is_host" in nm:
		return bool(nm.is_host)
	return false

func _local_peer_id() -> int:
	var nm: Node = _network_manager()
	if nm != null and "local_peer_id" in nm:
		return int(nm.local_peer_id)
	return 0

## 出征结算写回（Phase ⑧）：把服务器回传的【本次净获得】合并进本机玩家各自的单人存档
## （GameState.expedition_inventory：materials/runes/equipment 三类分别累加），并持久化到存档槽位。
## 联机仅地牢、酒馆经济为单人本地，故不汇入 TavernManager（与单人 extraction 的 deposit 行为不同）。
## settlement 结构：{"materials":{id:amt}, "runes":{id:amt}, "equipment":{id:amt}}。
func _apply_extraction_settlement(settlement: Dictionary) -> void:
	if settlement == null or settlement.is_empty():
		return
	var gs: Node = get_node_or_null("/root/GameState")
	if gs == null:
		return
	for k in (settlement.get("materials", {}) as Dictionary).keys():
		if gs.has_method("add_carried_material"):
			gs.add_carried_material(String(k), int((settlement["materials"] as Dictionary)[k]))
	for k in (settlement.get("runes", {}) as Dictionary).keys():
		if gs.has_method("add_carried_rune"):
			gs.add_carried_rune(String(k), int((settlement["runes"] as Dictionary)[k]))
	for k in (settlement.get("equipment", {}) as Dictionary).keys():
		if gs.has_method("add_carried_equipment"):
			gs.add_carried_equipment(String(k), int((settlement["equipment"] as Dictionary)[k]))
	# 持久化：联机出征结算写入固定槽位 0（垂直切片简化；生产应接当前存档槽位）。
	var sm: Node = get_node_or_null("/root/SaveManager")
	if sm != null and sm.has_method("save_to_slot"):
		sm.save_to_slot(0)

## 取得 NetworkManager 单例（autoload）。未挂载（纯逻辑单测）时返回 null。
func _network_manager() -> Node:
	return get_node_or_null("/root/NetworkManager")
