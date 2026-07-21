extends RefCounted

## CommandValidator —— 客户端命令的纯逻辑校验（Phase 3+，§5.2/§11/§12）。
## 不依赖场景树或网络，所有方法为静态/纯函数，便于单测（docs/25 §17.1）。
##
## 设计基线见 docs/25-联机总体方案.md §12（协议头/错误码）、§11（交互验证）、§6（移动验证）。
## 经 preload 访问：const CV := preload("res://globals/multiplayer/command_validator.gd")

const NP := preload("res://globals/multiplayer/network_protocol.gd")

## 禁止客户端在命令中携带【本应由服务器权威维护】的字段（§5.2 / Phase 2.3）。
## 这些字段若被客户端伪造并被信任，将造成穿墙 / 秒杀 / 无限资源等作弊。
## 注意：target_hint / item_id / slot / skill_id / seed(仅 host 出征) 等【标识符】允许，
## 因为它们只是指向服务器权威数据的键，服务器会自行校验其合法性后才使用。
const FORBIDDEN_TRUSTED_FIELDS := [
	"position", "velocity", "damage", "current_life",
	"inventory_delta", "drop_amount", "weapon_stats",
	"player_attributes", "save_state",
]

## 命令是否未携带任何被禁止的「服务器权威字段」（即客户端未尝试伪造权威状态）。
static func validate_no_trusted_fields(command: Dictionary) -> bool:
	for f in FORBIDDEN_TRUSTED_FIELDS:
		if command.has(f):
			return false
	return true

## 协议版本是否匹配
static func validate_protocol(client_proto: int) -> bool:
	return client_proto == NP.PROTOCOL_VERSION

## world_revision 是否匹配当前服务器 revision
static func validate_world_revision(client_rev: int, server_rev: int) -> bool:
	return client_rev == server_rev

## 距离校验：from → target 是否 <= max_dist（米）
static func validate_range(from: Vector3, target: Vector3, max_dist: float) -> bool:
	return from.distance_to(target) <= max_dist

## 冷却校验：剩余冷却 <= 0 才允许
static func validate_cooldown(remaining: float) -> bool:
	return remaining <= 0.0

## 序列号追踪器：防止重放/重复命令（§12.1 sequence）。
## 每个 peer 维护“最近已接受序列号”，仅接受严格递增的序列号。
class SequenceTracker:
	var _last: Dictionary = {}  # peer_id -> int

	## 接受序列号：严格大于上次才通过（拒绝重复/旧序列/重放）。返回是否接受。
	func accept(peer_id: int, seq: int) -> bool:
		var last: int = int(_last.get(peer_id, 0))
		if seq <= last:
			return false
		_last[peer_id] = seq
		return true

	func last_accepted(peer_id: int) -> int:
		return int(_last.get(peer_id, 0))

	func reset_peer(peer_id: int) -> void:
		_last.erase(peer_id)
