extends Node

## PlayerRegistry —— 在线玩家注册表（Phase 3，§3.3/§4.3）。
## 维护 peer_id → (PlayerContext, Player 节点, PlayerSession) 映射。
## 所有服务器逻辑经 get_context(peer_id) / get_player(peer_id) 访问玩家，
## 而非全局 GameState.current_player / AttrPanel / SkillRuntime。
##
## 经 preload 访问：const PR := preload("res://globals/multiplayer/player_registry.gd")
## 设计基线见 docs/25-联机总体方案.md §3.3。

const PlayerContextClass := preload("res://globals/core/player_context.gd")
const PlayerSessionClass := preload("res://globals/multiplayer/player_session.gd")

var contexts: Dictionary   # peer_id -> PlayerContext
var players: Dictionary    # peer_id -> Player (Node)
var sessions: Dictionary   # peer_id -> PlayerSession
var _spawned: Dictionary   # peer_id -> bool

# 引用类型必须在 _init 内按实例独立初始化：
# GDScript 类级 `= {}` 字面量会被所有实例共享，导致多玩家注册表相互污染。
func _init() -> void:
	contexts = {}
	players = {}
	sessions = {}
	_spawned = {}

## 注册一个 peer：建立其 PlayerContext 与 PlayerSession（可选绑定 Player 节点）。
func register_peer(peer_id: int, ctx: PlayerContextClass, player = null) -> void:
	contexts[peer_id] = ctx
	sessions[peer_id] = PlayerSessionClass.new(peer_id)
	if player != null:
		players[peer_id] = player

## 注销一个 peer：移除其全部注册信息（断线清理用）。
func unregister_peer(peer_id: int) -> void:
	contexts.erase(peer_id)
	players.erase(peer_id)
	sessions.erase(peer_id)
	_spawned.erase(peer_id)

func has_peer(peer_id: int) -> bool:
	return contexts.has(peer_id)

func get_context(peer_id: int) -> PlayerContextClass:
	return contexts.get(peer_id, null)

func get_player(peer_id: int):
	return players.get(peer_id, null)

func get_session(peer_id: int):
	return sessions.get(peer_id, null)

func peer_ids() -> Array:
	var ids: Array = []
	for id in contexts.keys():
		ids.append(int(id))
	ids.sort()
	return ids

func set_spawned(peer_id: int, value: bool) -> void:
	_spawned[peer_id] = value

func is_spawned(peer_id: int) -> bool:
	return bool(_spawned.get(peer_id, false))

func peer_count() -> int:
	return contexts.size()
