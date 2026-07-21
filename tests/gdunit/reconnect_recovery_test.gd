extends GdUnitTestSuite

## 断线重连恢复端到端测试（docs/25 §13 断线重连 × §9 实体同步；任务 #36 × Phase 10）。
##
## 背景：双进程 ENet 集成测试受沙箱 loopback 抖动阻塞，无法稳定复跑（见 MEMORY.md
## 「联机集成测试运行」）。本套件在【单进程】内经真实 NetworkManager 服务器入口
## （_server_handle_spawn / _server_handle_resume / _server_handle_command / reconcile_entities）
## 复现双进程 #36 恢复场景，锁定「重连 + 实体对账 + 结算幂等」这条组合恢复路径的正确性：
##   ① 玩家离线期间世界实体发生增删改 → 重连快照必须是【最新】服务器权威态（非陈旧全量）。
##   ② 重连后经 reconcile_entities(客户端已知集) 对账，只补 新增/变化、并 despawn 陈旧实体
##      —— 这是朴素 rebroadcast_entities() 做不到的（它只全量 spawned，无法清理陈旧实体）。
##   ③ reconcile 事件确经真实 NetworkManager 下发链路（event_dispatched）流出。
##   ④ 结算幂等跨重连（ENet 重连分配新 peer_id）仍生效，杜绝「断线→重连→再结算」刷物品。
##   ⑤ 把 delta 应用到客户端已知集后，客户端视图逐字节收敛到服务器权威实体集。

const NETWORK_MANAGER := preload("res://globals/core/network_manager.gd")
const NP := preload("res://globals/multiplayer/network_protocol.gd")

var _captured: Array = []

func _capture(e: Dictionary) -> void:
	_captured.append(e)

## 构建一个服务器态 NetworkManager，生成一名带稳定 guid 的在线玩家，并布置初始实体。
## 返回 {nm, token, known}：token=断线前签发的重连 token（供重连），
## known=玩家断线时的「客户端已知实体集」快照（重连后据此对账）。
func _make_server_with_entities() -> Dictionary:
	var nm := NETWORK_MANAGER.new()
	nm._ensure_session()
	nm.session.init_server()
	# 玩家 peer=3，稳定身份 guid=g3。
	nm._server_handle_spawn(3, {}, "g3")
	nm.session.set_player_position(3, Vector3(2, 0, 2))
	# 初始世界实体：一只老鼠(1) 与一个宝箱(2)。这是玩家在线时已同步到的「客户端已知集」。
	nm.session.set_entity(1, {"kind": "enemy", "label": "rat", "current_life": 8, "position": Vector3(5, 0, 5)})
	nm.session.set_entity(2, {"kind": "chest", "label": "chest", "current_life": 1, "position": Vector3(9, 0, 1)})
	var known: Dictionary = nm.session.all_entities().duplicate(true)
	return {"nm": nm, "token": "", "known": known}

## 模拟离线期间的世界演进：老鼠(1)被清除、宝箱(2)受损(字段变化)、新掉落物(3)生成。
func _mutate_world_offline(nm) -> void:
	nm.server_despawn_entity(1)  # 老鼠被其他玩家击杀 → despawn
	nm.server_update_entity(2, {"current_life": 0, "consumed": true})  # 宝箱被开 → snapshot 变化
	nm.server_spawn_entity(3, {"kind": "loot", "label": "iron_ore", "amount": 2, "position": Vector3(9, 0, 1)})

# ---------------------------------------------------------------------------
# ① 重连快照为最新服务器态
# ---------------------------------------------------------------------------

func test_reconnect_snapshot_reflects_current_world_not_stale() -> void:
	var ctx: Dictionary = _make_server_with_entities()
	var nm = ctx["nm"]
	var dis: Dictionary = nm.session.handle_peer_disconnected(3, nm.session.current_time)
	# 离线期间世界演进。
	_mutate_world_offline(nm)
	# 重连（ENet 分配新 peer_id=9），捕获下发事件。
	_captured.clear()
	nm.event_dispatched.connect(_capture)
	var res: Dictionary = nm._server_handle_resume(9, dis["token"], "g3")
	assert_bool(res["success"]).is_true()
	# 找到重连会话快照，断言其实体为【最新】态：老鼠(1)已消失、宝箱(2)已变化、掉落(3)已出现。
	var snap: Dictionary = {}
	for e in _captured:
		if e.get("event", "") == NP.EVT_SESSION_SNAPSHOT:
			snap = e.get("snapshot", {})
	assert_bool(snap.has("entities")).is_true()
	var ents: Dictionary = snap["entities"]
	assert_bool(ents.has(1)).is_false()                                   # 陈旧老鼠不在最新快照里
	assert_bool(ents.has(3)).is_true()                                    # 新掉落物在
	assert_int(int((ents[2] as Dictionary).get("current_life", -1))).is_equal(0)  # 宝箱最新态
	nm.free()

# ---------------------------------------------------------------------------
# ② 重连后 reconcile 对账：despawn 陈旧 + spawn 新增 + snapshot 变化
# ---------------------------------------------------------------------------

func test_reconcile_after_reconnect_emits_despawn_spawn_and_snapshot() -> void:
	var ctx: Dictionary = _make_server_with_entities()
	var nm = ctx["nm"]
	var known: Dictionary = ctx["known"]
	var dis: Dictionary = nm.session.handle_peer_disconnected(3, nm.session.current_time)
	_mutate_world_offline(nm)
	nm._server_handle_resume(9, dis["token"], "g3")
	# 客户端持【断线时的已知集 known】，重连后经 reconcile 对账追平到最新服务器态。
	_captured.clear()
	nm.event_dispatched.connect(_capture)
	var events: Array = nm.reconcile_entities(known)
	# 分类统计对账事件。
	var despawned: Array = []
	var spawned: Array = []
	var snapshotted: Array = []
	for e in events:
		match e.get("event", ""):
			NP.EVT_ENTITY_DESPAWNED: despawned.append(int(e["entity_id"]))
			NP.EVT_ENTITY_SPAWNED: spawned.append(int(e["entity_id"]))
			NP.EVT_ENTITY_SNAPSHOT: snapshotted.append(int(e["entity_id"]))
	assert_array(despawned).contains([1])       # 陈旧老鼠被清理（关键：rebroadcast 做不到）
	assert_array(spawned).contains([3])         # 新掉落物补生成
	assert_array(snapshotted).contains([2])     # 宝箱变化下发快照
	# 事件确经真实 NetworkManager 下发链路（event_dispatched）流出，数量与返回一致。
	assert_int(_captured.size()).is_equal(events.size())
	nm.free()

# ---------------------------------------------------------------------------
# ③ 回归对照：朴素 rebroadcast 无法 despawn 陈旧实体（Phase 10 修复动机）
# ---------------------------------------------------------------------------

func test_naive_rebroadcast_cannot_despawn_stale_entity() -> void:
	var ctx: Dictionary = _make_server_with_entities()
	var nm = ctx["nm"]
	var dis: Dictionary = nm.session.handle_peer_disconnected(3, nm.session.current_time)
	_mutate_world_offline(nm)
	nm._server_handle_resume(9, dis["token"], "g3")
	# rebroadcast_entities() == reconcile_entities({})：known 为空 → 只会全量 spawned，
	# 永远不产生 despawn，故重连客户端仍持有的陈旧老鼠(1)无法被清理。
	_captured.clear()
	nm.event_dispatched.connect(_capture)
	nm.rebroadcast_entities()
	var has_despawn := false
	for e in _captured:
		if e.get("event", "") == NP.EVT_ENTITY_DESPAWNED:
			has_despawn = true
	assert_bool(has_despawn).is_false()
	# 全量 spawned 覆盖当前所有实体（2 和 3；1 已不存在于服务器）。
	var spawned_ids: Array = []
	for e in _captured:
		if e.get("event", "") == NP.EVT_ENTITY_SPAWNED:
			spawned_ids.append(int(e["entity_id"]))
	assert_bool(spawned_ids.has(2)).is_true()
	assert_bool(spawned_ids.has(3)).is_true()
	assert_bool(spawned_ids.has(1)).is_false()
	nm.free()

# ---------------------------------------------------------------------------
# ④ 结算幂等跨重连（新 peer_id）不被绕过 —— 防「断线→重连→再结算」刷物品
# ---------------------------------------------------------------------------

func test_settlement_idempotent_across_reconnect_new_peer_id() -> void:
	var nm := NETWORK_MANAGER.new()
	nm._ensure_session()
	nm.session.init_server()
	# 玩家 peer=3 / guid=g3，地牢中拾取 goblin_tooth×2。
	nm._server_handle_spawn(3, {}, "g3")
	var c3 = nm.session.registry.get_context(3)
	c3.inventory.add_material("goblin_tooth", 2)
	# 首次结算（在线，peer=3）。
	var r1: Dictionary = nm._server_handle_command(3, {
		"type": NP.CMD_EXTRACT, "protocol_version": NP.PROTOCOL_VERSION,
		"world_revision": nm.session.world.world_revision, "sequence": 1,
	})
	assert_bool(r1["success"]).is_true()
	assert_bool(bool(r1["event"].get("already_settled", true))).is_false()
	# 断线 → 重连分配新 peer_id=9（携同一 guid，状态整体接管）。
	var dis: Dictionary = nm.session.handle_peer_disconnected(3, nm.session.current_time)
	var rr: Dictionary = nm._server_handle_resume(9, dis["token"], "g3")
	assert_bool(rr["success"]).is_true()
	# 重连后玩家试图再刷：即便背包又"变多"，重复结算必须幂等拒绝、置 already_settled，
	# 且缓存结算仍是首次净获得(2)，不是被刷后的天量值。
	var c9 = nm.session.registry.get_context(9)
	c9.inventory.add_material("goblin_tooth", 999)
	var r2: Dictionary = nm._server_handle_command(9, {
		"type": NP.CMD_EXTRACT, "protocol_version": NP.PROTOCOL_VERSION,
		"world_revision": nm.session.world.world_revision, "sequence": 1,
	})
	assert_bool(r2["success"]).is_true()
	assert_bool(bool(r2["event"]["already_settled"])).is_true()
	assert_int(int((r2["event"]["settlement"]["materials"] as Dictionary).get("goblin_tooth", 0))).is_equal(2)
	nm.free()

# ---------------------------------------------------------------------------
# ⑤ 收敛性：把 reconcile delta 应用到客户端已知集 → 逐实体收敛到服务器权威态
# ---------------------------------------------------------------------------

func test_client_view_converges_to_server_after_applying_delta() -> void:
	var ctx: Dictionary = _make_server_with_entities()
	var nm = ctx["nm"]
	var known: Dictionary = ctx["known"]
	var dis: Dictionary = nm.session.handle_peer_disconnected(3, nm.session.current_time)
	_mutate_world_offline(nm)
	nm._server_handle_resume(9, dis["token"], "g3")
	# 客户端以 known 为起点，逐条应用对账 delta（模拟表现层桥接对实体事件的落地）。
	var view: Dictionary = known.duplicate(true)
	for e in nm.reconcile_entities(known):
		match e.get("event", ""):
			NP.EVT_ENTITY_SPAWNED: view[int(e["entity_id"])] = (e["data"] as Dictionary).duplicate(true)
			NP.EVT_ENTITY_SNAPSHOT: view[int(e["entity_id"])] = (e["data"] as Dictionary).duplicate(true)
			NP.EVT_ENTITY_DESPAWNED: view.erase(int(e["entity_id"]))
	# 应用后客户端视图的实体 id 集合与服务器权威一致（1 消失、2 保留、3 新增）。
	var server_ids: Array = nm.session.all_entities().keys()
	server_ids.sort()
	var view_ids: Array = view.keys()
	view_ids.sort()
	assert_array(view_ids).is_equal(server_ids)
	# 且逐实体字段一致（收敛到服务器权威态，无残差）。
	for eid in server_ids:
		assert_dict(view[eid]).is_equal(nm.session.get_entity(int(eid)))
	nm.free()
