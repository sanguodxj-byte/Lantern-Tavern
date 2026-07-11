extends Node
## NetworkManager（autoload singleton，按 project.godot 注册名访问；不声明 class_name 避免与 autoload 同名冲突）

## 联机传输与 peer 注册层。
## 单机模式下保持惰性；真实玩家生成、复制和权威逻辑由后续 SessionRoot 接入。

signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal connected_to_server()
signal connection_failed()
signal server_disconnected()
signal lobby_updated()

const DEFAULT_PORT: int = 54321
const MAX_PLAYERS: int = 4

var is_active: bool = false
var is_host: bool = false
var local_peer_id: int = 0
var session_address: String = ""
var session_port: int = 0
var last_error: Error = OK

var peer_contexts: Dictionary = {}

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func host(port: int = DEFAULT_PORT, max_players: int = MAX_PLAYERS) -> Error:
	if is_active:
		return ERR_ALREADY_IN_USE
	if port < 1 or port > 65535 or max_players < 1:
		last_error = ERR_INVALID_PARAMETER
		return last_error
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, max_players)
	if err != OK:
		last_error = err
		return err
	multiplayer.multiplayer_peer = peer
	is_active = true
	is_host = true
	local_peer_id = multiplayer.get_unique_id()
	session_address = "0.0.0.0"
	session_port = port
	last_error = OK
	_register_peer(local_peer_id)
	lobby_updated.emit()
	return OK

func join(address: String, port: int = DEFAULT_PORT) -> Error:
	if is_active:
		return ERR_ALREADY_IN_USE
	if address.strip_edges().is_empty() or port < 1 or port > 65535:
		last_error = ERR_INVALID_PARAMETER
		return last_error
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		last_error = err
		return err
	multiplayer.multiplayer_peer = peer
	is_active = true
	is_host = false
	local_peer_id = 0
	session_address = address.strip_edges()
	session_port = port
	last_error = OK
	return OK

func disconnect_session() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	is_active = false
	is_host = false
	local_peer_id = 0
	session_address = ""
	session_port = 0
	last_error = OK
	peer_contexts.clear()
	lobby_updated.emit()

func register_peer_context(peer_id: int, ctx: PlayerContext) -> void:
	peer_contexts[peer_id] = ctx

func get_peer_context(peer_id: int) -> PlayerContext:
	return peer_contexts.get(peer_id, null)

func connected_peers() -> Array:
	var peers: Array[int] = []
	for peer_id in peer_contexts.keys():
		peers.append(int(peer_id))
	peers.sort()
	return peers

func peer_count() -> int:
	return peer_contexts.size()

func is_client() -> bool:
	return is_active and not is_host

func _register_peer(peer_id: int) -> void:
	if not peer_contexts.has(peer_id):
		peer_contexts[peer_id] = null

func _on_peer_connected(peer_id: int) -> void:
	_register_peer(peer_id)
	peer_joined.emit(peer_id)
	lobby_updated.emit()

func _on_peer_disconnected(peer_id: int) -> void:
	if peer_contexts.has(peer_id):
		peer_contexts.erase(peer_id)
		peer_left.emit(peer_id)
		lobby_updated.emit()

func _on_connected_to_server() -> void:
	local_peer_id = multiplayer.get_unique_id()
	connected_to_server.emit()

func _on_connection_failed() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null
	is_active = false
	is_host = false
	local_peer_id = 0
	session_address = ""
	session_port = 0
	connection_failed.emit()

func _on_server_disconnected() -> void:
	is_active = false
	is_host = false
	local_peer_id = 0
	session_address = ""
	session_port = 0
	peer_contexts.clear()
	server_disconnected.emit()
	lobby_updated.emit()

@rpc("any_peer", "call_remote", "reliable")
func request_player_spawn(_peer_id: int = 0) -> void:
	if not is_host:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id <= 0 or sender_id == multiplayer.get_unique_id():
		return
	_register_peer(sender_id)
	# TODO(Phase3): 生成玩家 + 注入 PlayerContext
