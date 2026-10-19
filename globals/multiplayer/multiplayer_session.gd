extends Node
## MultiplayerSession —— 联机大厅 / 出征的真实入口（⑩ + 架构债消解）。
##
## 把集成测试里内联的「房主/客户端进入真实地牢」逻辑提升为共享控制器，
## 使【真实游戏（大厅 UI）】与【集成测试】走同一条路径，避免双份实现漂移。
##
## 不声明 class_name：遵循本项目联机脚本约定（同 multiplayer_scene_bridge.gd）。
##
## 关键职责：
##   * 房主 host_room()：起服务器 + 注册本地 PlayerContext + 监听 peer_authorized（晚到重播）。
##   * 房主 start_expedition()：服务器选 seed → 构建真实地牢 + 权威实体。
##   * 客户端 join_room()：连服务器 + send_spawn + 监听 dungeon_layout → 同 seed 重建真实地牢。
##   * 保证 MultiplayerSceneBridge 常驻树（负责把权威状态物化为可见 avatar/实体）。

const DungeonSessionControllerClass := preload("res://scenes/multiplayer/dungeon_session_controller.gd")
const BridgeScene := preload("res://globals/multiplayer/multiplayer_scene_bridge.tscn")
const NP := preload("res://globals/multiplayer/network_protocol.gd")
const ClientIdentity := preload("res://globals/multiplayer/client_identity.gd")

var controller: Node = null          ## DungeonSessionController 实例（真实地牢 + 本地 Player）
var bridge: Node = null              ## MultiplayerSceneBridge 实例（表现层）
var local_player: Node = null        ## 本地真实 Player
var seed_value: int = 0
var is_in_dungeon: bool = false
var is_host_mode: bool = false

signal dungeon_entered(seed_value: int)
signal room_updated(peer_ids: Array)
signal connection_failed(reason: String)
signal host_failed(reason: String)

func _ready() -> void:
	_ensure_bridge()

## 确保表现层桥接节点常驻树（物化 avatar / 实体 / 快照）。
func _ensure_bridge() -> void:
	bridge = get_node_or_null("/root/MultiplayerSceneBridge")
	if bridge == null:
		bridge = BridgeScene.instantiate()
		bridge.name = "MultiplayerSceneBridge"
		# _ready 期间 root 正在构建子节点，直接 add_child 会报错，
		# 延迟到下一帧空闲再挂树（桥接节点被引用即可，晚挂无害）。
		get_tree().root.call_deferred("add_child", bridge)

# ---------------------------------------------------------------------------
# 房主：创建房间（不立即出征，等待玩家加入）
# ---------------------------------------------------------------------------
## 房主：创建房间（不立即出征，等待玩家加入）
## player_guid：空时使用本机持久化稳定身份（P0-1：禁止固定默认值）。
func host_room(port: int, max_players: int = 8, player_guid: String = "") -> void:
	if player_guid.is_empty():
		player_guid = ClientIdentity.load_or_create()
	var err := NetworkManager.host(port, max_players)
	if err != OK:
		host_failed.emit("创建房间失败 (端口 %d: %d)" % [port, err])
		return
	is_host_mode = true
	# P0-5：房主以【单人存档摘要】（materials/loadout/spell_state）建立权威 PlayerContext，
	# 使房主在联机地牢中拥有服务器权威法术装配（不再默认空 SpellLoadout）。
	var gs: Node = get_node_or_null("/root/GameState")
	var save_state: Dictionary = gs.build_network_save_state() if gs != null and gs.has_method("build_network_save_state") else {}
	NetworkManager.spawn_self(save_state, player_guid)
	if not NetworkManager.peer_authorized.is_connected(_on_peer_authorized):
		NetworkManager.peer_authorized.connect(_on_peer_authorized)
	_emit_room()

## 房主：开始出征（构建真实地牢 + 服务器权威实体）。
func start_expedition(seed_hint: int = -1) -> void:
	if not NetworkManager.is_host:
		return
	var result: Dictionary = NetworkManager.start_expedition(seed_hint)
	if result.is_empty() or not bool(result.get("success", false)):
		return
	var evt: Dictionary = result.get("event", {})
	seed_value = int(evt.get("seed", 0))
	_build_dungeon(seed_value)
	if controller != null and controller.has_method("spawn_server_entities"):
		controller.spawn_server_entities()
	is_in_dungeon = true
	dungeon_entered.emit(seed_value)

# ---------------------------------------------------------------------------
# 客户端：加入房间
# ---------------------------------------------------------------------------
func join_room(address: String, port: int, player_guid: String = "") -> void:
	if player_guid.is_empty():
		player_guid = ClientIdentity.load_or_create()
	is_host_mode = false
	NetworkManager.join(address, port)
	# 等待连接建立（local_peer_id 由 0 变为非 0）再 send_spawn，避免竞态。
	for i in range(300):
		await get_tree().process_frame
		if NetworkManager.local_peer_id != 0:
			break
	if NetworkManager.local_peer_id == 0:
		connection_failed.emit("无法连接到 %s:%d" % [address, port])
		return
	NetworkManager.send_spawn(player_guid)
	if not NetworkManager.event_received.is_connected(_on_event):
		NetworkManager.event_received.connect(_on_event)

# ---------------------------------------------------------------------------
# 客户端：收到服务器 dungeon_layout → 同 seed 确定性重建真实地牢
# ---------------------------------------------------------------------------
func _on_event(event: Dictionary) -> void:
	if event.is_empty():
		return
	var kind: String = event.get("event", event.get("type", ""))
	if kind != NP.EVT_DUNGEON_LAYOUT:
		return
	if is_in_dungeon:
		return
	seed_value = int(event.get("seed", 0))
	_build_dungeon(seed_value)
	is_in_dungeon = true
	dungeon_entered.emit(seed_value)

func _build_dungeon(seed_value: int) -> void:
	# 防重入：若已有地牢（重复 start / 重连重建），先释放旧节点，避免泄漏与双节点。
	if controller != null and is_instance_valid(controller):
		controller.queue_free()
		controller = null
	controller = DungeonSessionControllerClass.new()
	controller.name = "DungeonSession"
	add_child(controller)
	# P0-2（0643 审查）：联机撤离闭环——portal 信号已在 controller.build_and_enter 内
	# 装配到 request_extraction（CMD_EXTRACT）；服务器结算应用后 extraction_completed
	# 触发离场（释放地牢与会话，回城）。禁止生产路径再走本地 DungeonRuntime 直算。
	if not controller.extraction_completed.is_connected(_on_extraction_completed):
		controller.extraction_completed.connect(_on_extraction_completed)
	local_player = controller.build_and_enter(seed_value)

## P0-2（0643 审查）：联机撤离完成后的生产离场——结算已由服务器应用并
## 写回（ServerSaveRepository），此处只负责收尾：释放真实地牢节点并复位状态。
func _on_extraction_completed(_settlement: Dictionary) -> void:
	if not is_in_dungeon:
		return
	# 释放真实地牢节点（本身是 MultiplayerSession 的子节点），避免泄漏。
	if controller != null and is_instance_valid(controller):
		controller.queue_free()
		controller = null
	is_in_dungeon = false
	local_player = null
	seed_value = 0

# ---------------------------------------------------------------------------
# 房主：新客户端接入 → 重播 layout / 实体 / 房主 avatar / 完整会话快照
# （Late-join / 重连「真实场景恢复」，逻辑源自已验证的集成测试）
# ---------------------------------------------------------------------------
func _on_peer_authorized(peer_id: int, _ctx) -> void:
	var nm: Node = NetworkManager
	if nm.session != null and nm.session.dungeon_auth != null:
		nm._dispatch_event(nm.session.dungeon_auth.make_layout_event(), 0)
	if nm.has_method("rebroadcast_entities"):
		nm.rebroadcast_entities()
	if bridge != null and bridge.has_method("rpc_spawn_avatar"):
		# B3（0644 审查）：房主 avatar 出生位置取服务器权威 live_state 位置，
		# 不再硬编码 rpc(1, Vector3.ZERO)（世界原点 + 魔法 peer 1）。
		bridge.rpc_spawn_avatar.rpc(NetworkManager.HOST_PEER_ID, _host_avatar_position(nm.session))
	if nm.session != null and nm.has_method("rpc_server_event"):
		var snap_evt := {"event": NP.EVT_SESSION_SNAPSHOT, "peer_id": peer_id,
			"snapshot": nm.session.build_session_snapshot()}
		nm.rpc_server_event.rpc_id(peer_id, snap_evt)
	_emit_room()

## B3（0644 审查）：晚到客户端的房主 avatar 出生位置 = 服务器权威 live_state[HOST_PEER_ID]。
## session 为 null / 无该 peer 状态 / 无 position 时回退世界原点（不猜测）。
static func _host_avatar_position(session: Node) -> Vector3:
	if session == null:
		return Vector3.ZERO
	var live_state = session.get("_live_state")
	if live_state is Dictionary and live_state.has(NetworkManager.HOST_PEER_ID):
		var host_ls: Dictionary = live_state[NetworkManager.HOST_PEER_ID]
		if not host_ls.is_empty() and host_ls.has("position"):
			return host_ls.get("position", Vector3.ZERO)
	return Vector3.ZERO

func _emit_room() -> void:
	if NetworkManager.session != null:
		room_updated.emit(NetworkManager.connected_peers())

## 透传：返回当前已连接 peer 列表（大厅 UI 玩家列表用）。
func connected_peers() -> Array:
	if NetworkManager != null and NetworkManager.has_method("connected_peers"):
		return NetworkManager.connected_peers()
	return []

## 离开房间（断开并彻底复位状态，释放真实地牢节点）。
func leave_room() -> void:
	if NetworkManager.peer_authorized.is_connected(_on_peer_authorized):
		NetworkManager.peer_authorized.disconnect(_on_peer_authorized)
	if NetworkManager.event_received.is_connected(_on_event):
		NetworkManager.event_received.disconnect(_on_event)
	NetworkManager.disconnect_session()
	# 释放真实地牢节点（本身是 MultiplayerSession 的子节点），避免泄漏。
	if controller != null and is_instance_valid(controller):
		controller.queue_free()
	is_in_dungeon = false
	is_host_mode = false
	seed_value = 0
	local_player = null
	controller = null
	# 通知大厅 UI 房间已空（玩家列表清空）。
	room_updated.emit([])
