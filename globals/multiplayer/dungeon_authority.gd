extends RefCounted
## DungeonAuthority —— Phase 7 地牢 seed/layout 同步（服务器权威纯逻辑层）。
##
## 职责（docs/25 §10.3 / Phase 7）：
##   * 服务器决定并持有当前出征地牢的权威 seed / layout_version / layout_revision；
##   * 客户端仅持有 seed，按 seed 在本地确定性重生成同一地牢（server 不必下发整张布局）；
##   * 客户端声明自己的 seed / layout_version 时，服务器校验一致性，不一致则拒绝
##     （防作弊 / layout 版本错配，对应 docs/25 §19 拒绝原因「地牢布局版本不兼容」）。
##
## 无场景树依赖，可 headless 单测。访问方式：
##   const DA := preload("res://globals/multiplayer/dungeon_authority.gd")

const NetworkProtocolClass := preload("res://globals/multiplayer/network_protocol.gd")
const NP := NetworkProtocolClass

# 服务器权威地牢状态
var seed: int = 0
var layout_version: int = 0
var layout_revision: int = 0
var active: bool = false
var expedition_id: int = 0

# 服务器随机 seed 上限（不含）：seed ∈ [0, DEFAULT_SEED_RANGE)
const DEFAULT_SEED_RANGE := 1000000

func _init() -> void:
	layout_version = NP.DUNGEON_LAYOUT_VERSION

## 服务器开启一次出征：确定 seed（provided_seed<0 时服务器随机），bump layout_revision，
## 返回 dungeon_layout 同步事件（广播给所有客户端）。
## rng 仅供单测注入固定种子以获得确定性；不传则 randomize()。
func start_expedition(provided_seed: int = -1, rng: RandomNumberGenerator = null) -> Dictionary:
	if provided_seed >= 0:
		seed = provided_seed
	else:
		var r: RandomNumberGenerator = rng if rng != null else RandomNumberGenerator.new()
		if rng == null:
			r.randomize()
		seed = r.randi_range(0, DEFAULT_SEED_RANGE - 1)
	layout_revision += 1
	expedition_id += 1
	active = true
	return make_layout_event()

## 结束出征（撤离 / 失败结算）。
func end_expedition() -> void:
	active = false

## 产出 dungeon_layout 同步事件（推送给所有客户端）。
func make_layout_event() -> Dictionary:
	return {
		"type": NP.EVT_DUNGEON_LAYOUT,
		"seed": seed,
		"layout_version": layout_version,
		"layout_revision": layout_revision,
		"expedition_id": expedition_id,
		"active": active,
	}

## 校验客户端发来的 layout 声明（防止客户端用错 / 旧的 seed 或 layout 版本）。
## 返回 {"ok":bool, "error_code":String, "event":Dictionary}
func validate_layout_request(peer_id: int, claimed_seed: int, claimed_layout_version: int) -> Dictionary:
	if claimed_layout_version != layout_version:
		return {"ok": false, "error_code": NP.ERR_DUNGEON_LAYOUT_VERSION, "event": {}}
	if not active:
		return {"ok": false, "error_code": NP.ERR_INVALID_STATE, "event": {}}
	if claimed_seed != seed:
		return {"ok": false, "error_code": NP.ERR_DUNGEON_SEED_MISMATCH, "event": {}}
	return {"ok": true, "error_code": "", "event": make_layout_event()}

## 确定性：seed -> layout 指纹（纯函数，无需场景依赖）。
## 客户端按 seed 重生成地牢后，可用该指纹校验与服务器期望一致（防本地篡改布局）。
static func derive_layout_id(seed_value: int) -> int:
	var h: int = 0x811c9dc5
	var s: int = seed_value
	for _i in 4:
		h = (h ^ (s & 0xff)) & 0xffffffff
		h = (h * 0x01000193) & 0xffffffff
		s >>= 8
	return int(h)

## 序列化（重连快照用）：导出当前权威状态。
func serialize() -> Dictionary:
	return {
		"seed": seed,
		"layout_version": layout_version,
		"layout_revision": layout_revision,
		"active": active,
		"expedition_id": expedition_id,
	}

## 反序列化（重连用）。
func deserialize(data: Dictionary) -> void:
	seed = int(data.get("seed", 0))
	layout_version = int(data.get("layout_version", NP.DUNGEON_LAYOUT_VERSION))
	layout_revision = int(data.get("layout_revision", 0))
	active = bool(data.get("active", false))
	expedition_id = int(data.get("expedition_id", 0))
