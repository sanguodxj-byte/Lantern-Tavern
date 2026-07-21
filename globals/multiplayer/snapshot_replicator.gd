extends RefCounted
## SnapshotReplicator（docs/25 §3.2 / §6.2 / §8.2 / §13.2）—— 把服务器维护的
## 实时状态字典转换为发送给客户端的快照/事件负载。
##
## 纯逻辑：所有输入都是数据字典（由 SessionRoot 从 PlayerRegistry/WorldState 收集），
## 不做任何场景树访问，便于单测。
##
## 归属 Phase：3/4（SessionRoot + 移动同步配套）。

const NP := preload("res://globals/multiplayer/network_protocol.gd")

## 构建单个玩家状态快照（§6.2 服务器状态）。
## live_state 需含：position:Vector3, velocity:Vector3, rotation_y:float,
##                  movement_state:String, grounded:bool
func build_player_snapshot(peer_id: int, live_state: Dictionary, server_tick: int = 0) -> Dictionary:
	return {
		"event": NP.EVT_PLAYER_SNAPSHOT,
		"peer_id": peer_id,
		"server_tick": server_tick,
		"position": live_state.get("position", Vector3.ZERO),
		"velocity": live_state.get("velocity", Vector3.ZERO),
		"rotation_y": float(live_state.get("rotation_y", 0.0)),
		"movement_state": live_state.get("movement_state", "idle"),
		"grounded": bool(live_state.get("grounded", true)),
	}

## 构建单个实体（敌人/掉落/门/箱）快照（§8.2）。
## entity 需含：entity_id, enemy_type, position, rotation, velocity, state,
##              current_life, max_life, target_peer_id, status_effects, is_dead
func build_entity_snapshot(entity: Dictionary) -> Dictionary:
	return {
		"event": NP.EVT_ENTITY_SNAPSHOT,
		"entity_id": entity.get("entity_id", 0),
		"enemy_type": entity.get("enemy_type", ""),
		"position": entity.get("position", Vector3.ZERO),
		"rotation": entity.get("rotation", Vector3.ZERO),
		"velocity": entity.get("velocity", Vector3.ZERO),
		"state": entity.get("state", ""),
		"current_life": int(entity.get("current_life", 0)),
		"max_life": int(entity.get("max_life", 0)),
		"target_peer_id": int(entity.get("target_peer_id", 0)),
		"status_effects": entity.get("status_effects", []),
		"is_dead": bool(entity.get("is_dead", false)),
	}

## 构建断线重连用的完整会话快照（§13.2）。
## 各参数为已收集的数据字典/数组（players/enemies/loot/doors/chests 为快照数组）。
func build_session_snapshot(world_revision: int, current_space: String, tavern_state: Dictionary, players: Array, enemies: Array, loot: Array, doors: Array, chests: Array, expedition_state: Dictionary) -> Dictionary:
	return {
		"event": "session_snapshot",
		"protocol_version": NP.PROTOCOL_VERSION,
		"world_revision": world_revision,
		"current_space": current_space,
		"tavern_state": tavern_state,
		"players": players,
		"enemies": enemies,
		"loot": loot,
		"doors": doors,
		"chests": chests,
		"expedition_state": expedition_state,
	}
