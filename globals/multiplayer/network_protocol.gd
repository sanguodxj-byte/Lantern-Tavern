extends RefCounted

## network_protocol —— 联机协议常量与消息契约（Phase 3 起被引用）。
##
## 设计基线见 docs/25-联机总体方案.md §12、§12.4、§19。
## 当前仅放置常量骨架，不包含序列化/反序列化逻辑（Phase 3 实现）。
##
## 使用方式（无 class_name，经 preload 访问）：
##   const NP := preload("res://globals/multiplayer/network_protocol.gd")
##   if client_proto != NP.PROTOCOL_VERSION: ...

## ---- 统一版本号（§19）----
const PROTOCOL_VERSION := 1
const SAVE_VERSION := 1
const DUNGEON_LAYOUT_VERSION := 1
const WEAPON_DATA_VERSION := 1

## ---- 客户端命令类型（§12.2）----
const CMD_JOIN := "request_join"
const CMD_READY := "request_ready"
const CMD_SPAWN := "request_spawn"
const CMD_INPUT := "input_frame"
const CMD_INTERACT := "request_interact"
const CMD_ATTACK := "request_attack"
const CMD_SKILL := "request_skill"
const CMD_EQUIP := "request_equip"
const CMD_DROP := "request_drop_item"
const CMD_PICKUP := "request_pickup"
const CMD_EXPEDITION := "request_start_expedition"
const CMD_REQUEST_LAYOUT := "request_dungeon_layout"
const CMD_EXTRACT := "request_extract"
const CMD_SAVE := "request_save"
const CMD_LEAVE := "request_leave"
const CMD_RESUME := "request_resume"

## ---- 服务器事件类型（§12.3）----
const EVT_SESSION_READY := "session_ready"
const EVT_PLAYER_JOINED := "player_joined"
const EVT_PLAYER_SPAWNED := "player_spawned"
const EVT_PLAYER_DESPAWNED := "player_despawned"
const EVT_PLAYER_SNAPSHOT := "player_snapshot"
const EVT_ENTITY_SPAWNED := "entity_spawned"
const EVT_ENTITY_DESPAWNED := "entity_despawned"
const EVT_ENTITY_SNAPSHOT := "entity_snapshot"
const EVT_INTERACTION_RESULT := "interaction_result"
const EVT_COMBAT_RESOLVED := "combat_resolved"
const EVT_INVENTORY_CHANGED := "inventory_changed"
const EVT_EQUIPMENT_CHANGED := "equipment_changed"
const EVT_SKILL_STATE_CHANGED := "skill_state_changed"
const EVT_SPACE_SNAPSHOT := "space_snapshot"
const EVT_SESSION_SNAPSHOT := "session_snapshot"
const EVT_DUNGEON_LAYOUT := "dungeon_layout"
const EVT_WORLD_REVISION_CHANGED := "world_revision_changed"
const EVT_COMMAND_REJECTED := "command_rejected"
const EVT_SERVER_MESSAGE := "server_message"
const EVT_EXTRACTION_RESULT := "extraction_result"

## ---- 统一错误码（§12.4）----
const ERR_INVALID_PROTOCOL := "INVALID_PROTOCOL"
const ERR_INVALID_WORLD_REVISION := "INVALID_WORLD_REVISION"
const ERR_INVALID_SEQUENCE := "INVALID_SEQUENCE"
const ERR_PLAYER_NOT_READY := "PLAYER_NOT_READY"
const ERR_PLAYER_NOT_ALIVE := "PLAYER_NOT_ALIVE"
const ERR_OUT_OF_RANGE := "OUT_OF_RANGE"
const ERR_LINE_OF_SIGHT_FAILED := "LINE_OF_SIGHT_FAILED"
const ERR_COOLDOWN_ACTIVE := "COOLDOWN_ACTIVE"
const ERR_INSUFFICIENT_RESOURCE := "INSUFFICIENT_RESOURCE"
const ERR_INVALID_TARGET := "INVALID_TARGET"
const ERR_TARGET_ALREADY_CONSUMED := "TARGET_ALREADY_CONSUMED"
const ERR_INVALID_STATE := "INVALID_STATE"
const ERR_PERMISSION_DENIED := "PERMISSION_DENIED"
const ERR_SERVER_BUSY := "SERVER_BUSY"
const ERR_VERSION_MISMATCH := "VERSION_MISMATCH"
const ERR_DUNGEON_LAYOUT_VERSION := "DUNGEON_LAYOUT_VERSION"
const ERR_DUNGEON_SEED_MISMATCH := "DUNGEON_SEED_MISMATCH"
const ERR_RECONNECT_TOKEN_INVALID := "RECONNECT_TOKEN_INVALID"
const ERR_RECONNECT_TOKEN_EXPIRED := "RECONNECT_TOKEN_EXPIRED"
const ERR_RECONNECT_PEER_UNKNOWN := "RECONNECT_PEER_UNKNOWN"
const ERR_RECONNECT_GUID_NOT_FOUND := "RECONNECT_GUID_NOT_FOUND"
const ERR_ATTACK_NOT_FACING := "ATTACK_NOT_FACING"

## 是否为合法客户端命令类型
static func is_valid_command(cmd: String) -> bool:
	return cmd in [CMD_JOIN, CMD_READY, CMD_SPAWN, CMD_INPUT, CMD_INTERACT, CMD_ATTACK,
		CMD_SKILL, CMD_EQUIP, CMD_DROP, CMD_PICKUP,
		CMD_EXPEDITION, CMD_REQUEST_LAYOUT, CMD_EXTRACT, CMD_SAVE, CMD_LEAVE, CMD_RESUME]

## 是否为合法服务器事件类型
static func is_valid_event(evt: String) -> bool:
	return evt in [EVT_SESSION_READY, EVT_PLAYER_JOINED, EVT_PLAYER_SPAWNED, EVT_PLAYER_DESPAWNED,
		EVT_PLAYER_SNAPSHOT, EVT_ENTITY_SPAWNED, EVT_ENTITY_DESPAWNED, EVT_ENTITY_SNAPSHOT,
		EVT_INTERACTION_RESULT, EVT_COMBAT_RESOLVED, EVT_INVENTORY_CHANGED, EVT_EQUIPMENT_CHANGED,
		EVT_SKILL_STATE_CHANGED,
		EVT_SPACE_SNAPSHOT, EVT_SESSION_SNAPSHOT, EVT_DUNGEON_LAYOUT, EVT_WORLD_REVISION_CHANGED, EVT_COMMAND_REJECTED, EVT_SERVER_MESSAGE, EVT_EXTRACTION_RESULT]

## 构造协议头（§12.1）
static func make_header(protocol_version: int, world_revision: int, client_tick: int, sequence: int) -> Dictionary:
	return {
		"protocol_version": protocol_version,
		"world_revision": world_revision,
		"client_tick": client_tick,
		"sequence": sequence,
	}
